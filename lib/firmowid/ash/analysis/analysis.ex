defmodule Firmowid.Ash.Analysis do
  @moduledoc """
  Ash domain for financial analysis: tag management, entity tagging, and
  organization-level totals calculation.

  Replaces the legacy `Firmowid.Analysis` Ecto context. Tag CRUD and entity
  tagging go through Ash actions with policy-based authorization and attribute
  multitenancy via `organization_id`.

  Cross-domain aggregation functions (`get_organization_totals/4`,
  `get_months_with_entries/1`) live here as regular functions because they
  orchestrate calls across both Ash resources (`CostInvoice`, `SalesInvoice`)
  and legacy Ecto contexts (`Finances`, `Currencies`) still being migrated.
  """
  use Ash.Domain

  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Currencies.Converter, as: Currencies
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Ash.Query

  resources do
    resource TagDefinition
    resource EntityTag
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  # ── Cross-domain aggregation ──────────────────────────────────────────
  #
  # These functions still call into Ecto contexts that haven't migrated to
  # Ash. The only structural change from the old `Firmowid.Analysis` context
  # is that entity tag loading now queries 3 separate tables via Ash reads
  # instead of 1 monolithic table via Ecto.

  @doc """
  Computes income, expenses, and net profit for a date range.

  Invoices are assigned to the month of sale (not issue). Only truly standalone
  transactions (skipped AND not matched) are included to prevent double-counting.

  Entities tagged as `:internal` are always excluded from totals.

  ## Options

    * `:tag_filters` — list of tag filter tuples. When non-empty, only entities
      matching at least one filter are included (OR semantics). Supported tuples:
      * `{:company}` — entities tagged as company
      * `{:project, tag_definition_id}` — entities tagged with a specific project tag
  """
  @spec get_organization_totals(Date.t(), Date.t(), keyword(), Scope.t()) :: map()
  def get_organization_totals(date_from, date_to, opts \\ [], scope) do
    tag_filters = Keyword.get(opts, :tag_filters, [])

    analysis_scope = analysis_scope(scope)

    sales_invoices =
      %{date_from: date_from, date_to: date_to, date_field: :sale_date}
      |> Invoicing.list_sales_invoices!(
        load: [:buyer_display_name_label, :gross_value, :sales_invoice_items, :transactions],
        scope: analysis_scope
      )
      |> Enum.filter(&matched_or_skipped?/1)

    cost_invoices =
      %{date_from: date_from, date_to: date_to, date_field: :sale_date, corrections: :exclude}
      |> Invoicing.list_cost_invoices!(
        load: [
          :transactions,
          :effective_currency,
          :effective_seller_display_name,
          :effective_sale_date,
          :effective_total_amount
        ],
        scope: analysis_scope
      )
      |> Enum.filter(&matched_or_skipped?/1)

    transactions =
      Finances.list_transactions!(
        %{date_from: date_from, date_to: date_to, reconciliation: :skipped},
        scope: analysis_scope
      )

    all_entities = build_entity_id_list(sales_invoices, cost_invoices, transactions)
    entity_tags_map = load_entity_tags_map(all_entities, scope)

    sales_invoices = filter_entities(sales_invoices, :sales_invoice, entity_tags_map, tag_filters)
    cost_invoices = filter_entities(cost_invoices, :cost_invoice, entity_tags_map, tag_filters)
    transactions = filter_entities(transactions, :transaction, entity_tags_map, tag_filters)

    today = Date.utc_today()

    %{income: income, expenses: expenses} =
      Enum.reduce(
        sales_invoices ++ cost_invoices ++ transactions,
        %{income: Decimal.new(0), expenses: Decimal.new(0)},
        fn entity, acc ->
          entity
          |> get_amount_and_currency()
          |> accumulate_amount(acc, today)
        end
      )

    %{
      total_income: income,
      total_expenses: expenses,
      net_profit: Decimal.add(income, expenses),
      transactions: transactions,
      sales_invoices: sales_invoices,
      cost_invoices: cost_invoices
    }
  end

  @doc """
  Returns a list of dates (first day of each month) that have analysis-relevant
  entries. Uses `sale_date` for invoices and `booking_date` for standalone
  (skipped, unmatched) transactions.

  Only includes invoices that are matched or marked `skip_invoicing`.
  Excludes entities tagged as `:internal`.
  """
  @spec get_months_with_entries(Scope.t()) :: [Date.t()]
  def get_months_with_entries(scope) do
    opts = [scope: analysis_scope(scope)]

    tx_months =
      %{reconciliation: :skipped}
      |> Finances.list_transactions!(opts)
      |> Enum.map(&Date.beginning_of_month(&1.booking_date))

    si_months = invoice_months(&Invoicing.list_sales_invoices!/2, :sale_date, %{}, opts)

    ci_months =
      invoice_months(&Invoicing.list_cost_invoices!/2, :sale_date, %{corrections: :exclude}, opts)

    (tx_months ++ si_months ++ ci_months)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp invoice_months(list_fn, date_field, base_args, opts) do
    Enum.map(
      list_fn.(Map.put(base_args, :reconciliation, :matched), opts) ++
        list_fn.(Map.put(base_args, :reconciliation, :skipped), opts),
      &Date.beginning_of_month(Map.fetch!(&1, date_field))
    )
  end

  defp get_amount_and_currency(%SalesInvoice{gross_value: %Decimal{} = gross_value, currency: currency}) do
    {:ok, {Decimal.abs(gross_value), currency}}
  end

  defp get_amount_and_currency(%SalesInvoice{}), do: :skip

  defp get_amount_and_currency(%CostInvoice{
         effective_total_amount: %Decimal{} = total_amount,
         effective_currency: currency
       }) do
    value = total_amount |> Decimal.abs() |> Decimal.mult(Decimal.new("-1"))
    {:ok, {value, currency}}
  end

  defp get_amount_and_currency(%CostInvoice{}), do: :skip

  defp get_amount_and_currency(%Transaction{} = entity) do
    {:ok, {Money.to_decimal(entity.amount), entity.amount |> Money.to_currency_code() |> Atom.to_string()}}
  end

  defp accumulate_amount(:skip, acc, _today), do: acc

  defp accumulate_amount({:ok, {amount, currency}}, acc, today) do
    normalized_amount = Currencies.normalize_amount_to_pln(amount, currency, today)

    if Decimal.negative?(normalized_amount) do
      Map.update!(acc, :expenses, &Decimal.add(&1, normalized_amount))
    else
      Map.update!(acc, :income, &Decimal.add(&1, normalized_amount))
    end
  end

  # An invoice is analysis-relevant when it has been matched to at least one
  # bank transaction or explicitly marked `skip_invoicing`.
  #
  # IMPORTANT: This rule is also used in `get_months_with_entries/1` above.
  # If you change this logic, update both places.
  defp matched_or_skipped?(%{skip_invoicing: true}), do: true
  defp matched_or_skipped?(%{transactions: txs}) when is_list(txs) and txs != [], do: true
  defp matched_or_skipped?(_), do: false

  defp build_entity_id_list(sales_invoices, cost_invoices, transactions) do
    si = Enum.map(sales_invoices, &{:sales_invoice, &1.id})
    ci = Enum.map(cost_invoices, &{:cost_invoice, &1.id})
    tx = Enum.map(transactions, &{:transaction, &1.id})
    si ++ ci ++ tx
  end

  # Loads entity tags from the 3 polymorphic tables via Ash reads and merges.
  # Returns a map: {entity_type, entity_id} => [%EntityTag{}]
  defp load_entity_tags_map([], _scope), do: %{}

  defp load_entity_tags_map(entity_ids, scope) do
    grouped = Enum.group_by(entity_ids, &elem(&1, 0), &elem(&1, 1))

    tables = [
      {:sales_invoice, "sales_invoice_entity_tags"},
      {:cost_invoice, "cost_invoice_entity_tags"},
      {:transaction, "transaction_entity_tags"}
    ]

    tables
    |> Enum.flat_map(fn {entity_type, table} ->
      ids = Map.get(grouped, entity_type, [])

      if ids == [] do
        []
      else
        EntityTag
        |> Ash.Query.set_context(%{data_layer: %{table: table}})
        |> Ash.Query.filter(resource_id in ^ids)
        |> Ash.Query.load(:tag_definition)
        |> Ash.read!(scope: scope)
        |> Enum.map(&{entity_type, &1})
      end
    end)
    |> Enum.group_by(fn {type, tag} -> {type, tag.resource_id} end, fn {_type, tag} -> tag end)
  end

  defp analysis_scope(%Scope{tenant: tenant}) do
    %Scope{actor: %SystemActor{org_id: tenant, role: :analysis_reader}, tenant: tenant}
  end

  defp entity_id(%SalesInvoice{id: id}), do: id
  defp entity_id(%CostInvoice{id: id}), do: id
  defp entity_id(%Transaction{id: id}), do: id

  # Filters entities and attaches entity_tags to each struct:
  # 1. Always excludes internal-tagged entities
  # 2. When tag_filters is non-empty, includes only entities matching at least one filter (OR)
  # 3. Overwrites entity.entity_tags with a plain list for display in the entries table
  defp filter_entities(entities, entity_type, entity_tags_map, tag_filters) do
    entities
    |> Enum.map(fn entity ->
      tags = Map.get(entity_tags_map, {entity_type, entity_id(entity)}, [])
      {Map.put(entity, :entity_tags, tags), tags}
    end)
    |> Enum.filter(fn {_entity, tags} ->
      not internal?(tags) and matches_tag_filters?(tags, tag_filters)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp internal?(tags), do: Enum.any?(tags, &(&1.kind == :internal))

  defp matches_tag_filters?(_tags, []), do: true

  defp matches_tag_filters?(tags, filters) do
    Enum.any?(filters, fn
      {:company} ->
        Enum.any?(tags, &(&1.kind == :company))

      {:project, tag_def_id} ->
        Enum.any?(tags, &(&1.kind == :project and &1.tag_definition_id == tag_def_id))
    end)
  end
end
