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

  alias Firmowid.Ash.Analysis.CategoryTotals
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

  resources do
    resource TagDefinition

    resource EntityTag
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  @doc """
  Computes income, expenses, and net profit for a date range.

  Invoices are assigned to the month of sale (not issue). Only truly standalone
  transactions (skipped AND not matched) are included to prevent double-counting.
  Transfers between the organization's own bank accounts are excluded.

  Entities tagged as `:internal` remain editable in entry lists but are excluded from totals.

  Returns the existing signed totals and entity lists, plus `:income_categories`
  and `:expense_categories`. Category rows contain `:key` (`{:project, id}`,
  `:company` or `:unassigned`), `:name` (nil for built-ins), `:color` and a positive
  Decimal PLN `:amount`. Each normalized entity amount is rounded to cents and
   allocated equally between projects, with sorted IDs receiving leftover cents.
   Totals and categories use the same allocated amounts.

  ## Options

    * `:tag_filters` — list of tag filter tuples. When non-empty, only shares
      matching at least one filter contribute to totals and categories (OR
      semantics). Entry lists retain whole matching entities for editing.
      Supported tuples:
      * `{:company}` — entities tagged as company
      * `{:project, tag_definition_id}` — entities tagged with a specific project tag
  """
  @spec get_organization_totals(Date.t(), Date.t(), keyword(), Scope.t()) :: map()
  def get_organization_totals(date_from, date_to, opts \\ [], scope) do
    tag_filters = Keyword.get(opts, :tag_filters, [])

    entries = get_organization_entries(date_from, date_to, scope)

    sales_invoices =
      Enum.filter(entries.sales_invoices, &visible_entry?(&1.entity_tags, tag_filters))

    cost_invoices =
      Enum.filter(entries.cost_invoices, &visible_entry?(&1.entity_tags, tag_filters))

    transactions =
      Enum.filter(entries.transactions, &visible_entry?(&1.entity_tags, tag_filters))

    totals =
      (sales_invoices ++ cost_invoices ++ transactions)
      |> Enum.flat_map(&normalized_entity(&1, Date.utc_today()))
      |> CategoryTotals.aggregate(tag_filters)

    Map.merge(totals, %{
      transactions: transactions,
      sales_invoices: sales_invoices,
      cost_invoices: cost_invoices
    })
  end

  @doc "Lists the same analysis-relevant entries as the totals, without currency conversion or UI filters."
  @spec get_organization_entries(Date.t(), Date.t(), Scope.t()) :: map()
  def get_organization_entries(date_from, date_to, scope) do
    analysis_scope = analysis_scope(scope)
    own_account_ibans = own_account_ibans(scope)

    sales_invoices =
      %{date_from: date_from, date_to: date_to, date_field: :sale_date}
      |> Invoicing.list_sales_invoices!(
        load: [:buyer_display_name_label, :effective_amount, :sales_invoice_items, :transactions],
        scope: analysis_scope
      )
      |> Enum.filter(&analysis_relevant_invoice?(&1, own_account_ibans))

    cost_invoices =
      %{date_from: date_from, date_to: date_to, date_field: :sale_date, corrections: :exclude}
      |> Invoicing.list_cost_invoices!(
        load: [
          :transactions,
          :effective_seller_display_name,
          :effective_sale_date,
          :effective_amount
        ],
        scope: analysis_scope
      )
      |> Enum.filter(&analysis_relevant_invoice?(&1, own_account_ibans))

    transactions =
      %{date_from: date_from, date_to: date_to, reconciliation: :skipped}
      |> Finances.list_transactions!(scope: analysis_scope)
      |> Enum.reject(&own_account_transfer?(&1, own_account_ibans))

    all_entities = build_entity_id_list(sales_invoices, cost_invoices, transactions)
    entity_tags_map = load_entity_tags_map(all_entities, scope)

    %{
      transactions: filter_entities(transactions, :transaction, entity_tags_map, []),
      sales_invoices: filter_entities(sales_invoices, :sales_invoice, entity_tags_map, []),
      cost_invoices: filter_entities(cost_invoices, :cost_invoice, entity_tags_map, [])
    }
  end

  @doc """
  Returns a list of dates (first day of each month) that have analysis-relevant
  entries. Uses `sale_date` for invoices and `booking_date` for standalone
  (skipped, unmatched) transactions.

  Only includes invoices that are matched to an external transaction or marked
  `skip_invoicing`.
  Excludes transfers between the organization's own bank accounts.
  Includes months with entries tagged as `:internal` so they remain editable.
  """
  @spec get_months_with_entries(Scope.t()) :: [Date.t()]
  def get_months_with_entries(scope) do
    opts = [scope: analysis_scope(scope)]
    own_account_ibans = own_account_ibans(scope)

    tx_months =
      %{reconciliation: :skipped}
      |> Finances.list_transactions!(opts)
      |> Enum.reject(&own_account_transfer?(&1, own_account_ibans))
      |> Enum.map(&Date.beginning_of_month(&1.booking_date))

    si_months =
      invoice_months(
        &Invoicing.list_sales_invoices!/2,
        :sale_date,
        %{},
        opts,
        own_account_ibans
      )

    ci_months =
      invoice_months(
        &Invoicing.list_cost_invoices!/2,
        :sale_date,
        %{corrections: :exclude},
        opts,
        own_account_ibans
      )

    (tx_months ++ si_months ++ ci_months)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp invoice_months(list_fn, date_field, base_args, opts, own_account_ibans) do
    opts = Keyword.put(opts, :load, [:transactions])

    (list_fn.(Map.put(base_args, :reconciliation, :matched), opts) ++
       list_fn.(Map.put(base_args, :reconciliation, :skipped), opts))
    |> Enum.filter(&analysis_relevant_invoice?(&1, own_account_ibans))
    |> Enum.map(&Date.beginning_of_month(Map.fetch!(&1, date_field)))
  end

  defp get_amount_and_currency(%SalesInvoice{effective_amount: %Money{} = amount}) do
    {:ok, Money.abs(amount)}
  end

  defp get_amount_and_currency(%SalesInvoice{}), do: :skip

  defp get_amount_and_currency(%CostInvoice{effective_amount: %Money{} = amount}) do
    {:ok, amount |> Money.abs() |> Money.negate!()}
  end

  defp get_amount_and_currency(%CostInvoice{}), do: :skip

  defp get_amount_and_currency(%Transaction{} = entity) do
    {:ok, entity.amount}
  end

  defp normalized_entity(entity, today) do
    case get_amount_and_currency(entity) do
      :skip ->
        []

      {:ok, amount} ->
        normalized_amount =
          Currencies.normalize_amount_to_pln(
            Money.to_decimal(amount),
            amount |> Money.to_currency_code() |> Atom.to_string(),
            today
          )

        [{normalized_amount, entity.entity_tags}]
    end
  end

  defp analysis_relevant_invoice?(%{skip_invoicing: true}, _own_account_ibans), do: true

  defp analysis_relevant_invoice?(%{transactions: transactions}, own_account_ibans) when is_list(transactions) do
    Enum.any?(transactions, &(not own_account_transfer?(&1, own_account_ibans)))
  end

  defp analysis_relevant_invoice?(_, _own_account_ibans), do: false

  defp own_account_ibans(scope) do
    %{}
    |> Finances.list_bank_accounts!(scope: scope)
    |> MapSet.new(&normalize_iban(&1.iban))
    |> MapSet.delete(nil)
  end

  defp own_account_transfer?(%Transaction{amount: amount} = transaction, own_account_ibans) do
    account =
      cond do
        Money.positive?(amount) -> transaction.debtor_account
        Money.negative?(amount) -> transaction.creditor_account
        true -> nil
      end

    MapSet.member?(own_account_ibans, normalize_iban(account))
  end

  defp normalize_iban(account) when is_binary(account) do
    account
    |> String.replace(~r/[^[:alnum:]]/, "")
    |> String.upcase()
    |> case do
      "" ->
        nil

      "NA" ->
        nil

      <<"PL", account::binary-size(26)>> = iban ->
        if String.match?(account, ~r/^\d{26}$/), do: account, else: iban

      iban ->
        iban
    end
  end

  defp normalize_iban(_account), do: nil

  defp build_entity_id_list(sales_invoices, cost_invoices, transactions) do
    si = Enum.map(sales_invoices, &{:sales_invoice, &1.id})
    ci = Enum.map(cost_invoices, &{:cost_invoice, &1.id})
    tx = Enum.map(transactions, &{:transaction, &1.id})
    si ++ ci ++ tx
  end

  defp load_entity_tags_map([], _scope), do: %{}

  defp load_entity_tags_map(entity_ids, scope) do
    grouped = Enum.group_by(entity_ids, &elem(&1, 0), &elem(&1, 1))

    grouped
    |> Enum.flat_map(fn {entity_type, ids} ->
      %{entity_type: entity_type, resource_ids: ids}
      |> EntityTag.list!(
        scope: scope,
        load: :tag_definition
      )
      |> Enum.map(&{entity_type, &1})
    end)
    |> Enum.group_by(fn {type, tag} -> {type, tag.resource_id} end, fn {_type, tag} -> tag end)
  end

  defp analysis_scope(%Scope{tenant: tenant}) do
    %Scope{actor: %SystemActor{org_id: tenant, role: :analysis_reader}, tenant: tenant}
  end

  defp entity_id(%SalesInvoice{id: id}), do: id
  defp entity_id(%CostInvoice{id: id}), do: id
  defp entity_id(%Transaction{id: id}), do: id

  defp filter_entities(entities, entity_type, entity_tags_map, tag_filters) do
    entities
    |> Enum.map(fn entity ->
      tags = Map.get(entity_tags_map, {entity_type, entity_id(entity)}, [])
      {Map.put(entity, :entity_tags, tags), tags}
    end)
    |> Enum.filter(fn {_entity, tags} ->
      visible_entry?(tags, tag_filters)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp internal?(tags), do: Enum.any?(tags, &(&1.kind == :internal))

  defp visible_entry?(tags, filters), do: internal?(tags) or matches_tag_filters?(tags, filters)

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
