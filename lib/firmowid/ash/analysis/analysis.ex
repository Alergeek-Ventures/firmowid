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

  import Ecto.Query, warn: false

  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Currencies.Converter, as: Currencies
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction, as: EctoTransaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceTransaction
  alias Firmowid.Ash.Scope
  alias Firmowid.Repo

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

    sales_invoices =
      %{date_from: date_from, date_to: date_to, date_field: :sale_date}
      |> SalesInvoice.read!(
        load: [:sales_invoice_items, :transactions],
        tenant: scope.current_tenant,
        actor: scope.current_user,
        authorize?: false
      )
      |> Enum.filter(&matched_or_skipped?/1)

    # TODO: replace authorize?: false + actor: %{} with system actor once available
    cost_invoices =
      %{date_from: date_from, date_to: date_to, date_field: :sale_date}
      |> CostInvoice.read!(
        load: [:transactions, :effective_total_amount, :effective_currency],
        tenant: scope.current_tenant,
        actor: scope.current_user,
        authorize?: false
      )
      |> Enum.filter(&matched_or_skipped?/1)

    transactions =
      Finances.list_transactions!(
        %{date_from: date_from, date_to: date_to, reconciliation: :skipped},
        tenant: scope.current_tenant,
        actor: scope.current_user,
        authorize?: false
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
          {amount, currency} = get_amount_and_currency(entity)
          normalized_amount = Currencies.normalize_amount_to_pln(amount, currency, today)

          if Decimal.negative?(normalized_amount) do
            Map.update!(acc, :expenses, &Decimal.add(&1, normalized_amount))
          else
            Map.update!(acc, :income, &Decimal.add(&1, normalized_amount))
          end
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
    # Set org_id for Ecto queries (Repo.prepare_query reads process dict)
    Repo.put_org_id(scope.current_tenant)

    sales_match_query =
      from(sit in SalesInvoiceTransaction,
        where: sit.transaction_id == parent_as(:transaction).id
      )

    cost_match_query =
      from(cit in CostInvoiceTransaction,
        where: cit.transaction_id == parent_as(:transaction).id
      )

    # Internal exclusion subqueries — now per-table instead of filtering on entity_type
    tx_internal_query =
      from(et in {"transaction_entity_tags", EntityTag},
        where:
          et.kind == :internal and
            et.resource_id == parent_as(:transaction).id
      )

    si_internal_query =
      from(et in {"sales_invoice_entity_tags", EntityTag},
        where:
          et.kind == :internal and
            et.resource_id == parent_as(:entity).id
      )

    ci_internal_query =
      from(et in {"cost_invoice_entity_tags", EntityTag},
        where:
          et.kind == :internal and
            et.resource_id == parent_as(:entity).id
      )

    transactions_query =
      from(t in EctoTransaction,
        as: :transaction,
        where: t.skip_invoicing == true,
        where: not exists(subquery(sales_match_query)),
        where: not exists(subquery(cost_match_query)),
        where: not exists(subquery(tx_internal_query)),
        select: %{month: t.booking_date, organization_id: t.organization_id}
      )

    si_matched_query =
      from(sit in SalesInvoiceTransaction,
        where: sit.sales_invoice_id == parent_as(:entity).id
      )

    ci_matched_query =
      from(cit in CostInvoiceTransaction,
        where: cit.cost_invoice_id == parent_as(:entity).id
      )

    sales_invoices_query =
      from(si in SalesInvoice,
        as: :entity,
        where: si.skip_invoicing == true or exists(subquery(si_matched_query)),
        where: not exists(subquery(si_internal_query)),
        select: %{month: si.sale_date, organization_id: si.organization_id}
      )

    cost_invoices_query =
      from(ci in CostInvoice,
        as: :entity,
        where: ci.skip_invoicing == true or exists(subquery(ci_matched_query)),
        where: not exists(subquery(ci_internal_query)),
        select: %{month: ci.sale_date, organization_id: ci.organization_id}
      )

    union_query =
      transactions_query
      |> union(^sales_invoices_query)
      |> union(^cost_invoices_query)

    from(u in subquery(union_query),
      select: u.month,
      distinct: true
    )
    |> Repo.all()
    |> Enum.map(&Date.beginning_of_month/1)
  end

  # ── Private helpers ──────────────────────────────────────────────────

  defp get_amount_and_currency(%SalesInvoice{} = entity) do
    value = Decimal.abs(entity.gross_value)

    {value, entity.currency}
  end

  defp get_amount_and_currency(%CostInvoice{} = entity) do
    value = entity.effective_total_amount |> Decimal.abs() |> Decimal.mult(Decimal.new("-1"))
    {value, entity.effective_currency}
  end

  defp get_amount_and_currency(%EctoTransaction{} = entity) do
    {entity.transaction_amount, entity.transaction_currency}
  end

  # An invoice is analysis-relevant when it has been matched to at least one
  # bank transaction or explicitly marked `skip_invoicing`.
  #
  # IMPORTANT: This rule is duplicated in SQL inside `get_months_with_entries/1`.
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
        |> Ash.read!(scope: scope, authorize?: false)
        |> Enum.map(&{entity_type, &1})
      end
    end)
    |> Enum.group_by(fn {type, tag} -> {type, tag.resource_id} end, fn {_type, tag} -> tag end)
  end

  defp entity_id(%SalesInvoice{id: id}), do: id
  defp entity_id(%CostInvoice{id: id}), do: id
  defp entity_id(%EctoTransaction{id: id}), do: id

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
