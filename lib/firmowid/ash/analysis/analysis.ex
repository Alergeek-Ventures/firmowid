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
  use Ash.Domain, extensions: [AshAi]

  alias Firmowid.Ash.Analysis.CategoryTotals
  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Analysis.Entry
  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Currencies.Converter, as: Currencies
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Ash.Timetracker

  tools do
    tool :list_analysis_tags, TagDefinition, :list_tag_definitions do
      annotations title: "List analysis project tags",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "List the authenticated organization's project tags with IDs and names. " <>
                    "Use these IDs as tag_definition_ids in set_analysis_entry_project_tags. " <>
                    "Company and internal are built-in categories, not project tags."

      select [:id, :name, :color]
    end

    tool :list_analysis_entries, Entry, :list do
      annotations title: "List analysis entries",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "List the entries behind the monthly income and expense analysis: sales invoices, cost invoices " <>
                    "and standalone bank transactions with their full document amounts and categories. " <>
                    "Categories are project tags (shared equally), company, or internal (excluded from totals); " <>
                    "an entry without categories is unassigned. Results belong to the authenticated organization."
    end

    tool :set_analysis_entry_category, EntityTag, :set_entity_category do
      annotations title: "Set analysis entry category",
                  read_only_hint: false,
                  destructive_hint: true,
                  idempotent_hint: true,
                  open_world_hint: false

      description "Replace all categories of an analysis entry with company (general company income or expense) " <>
                    "or internal (excluded from analysis totals). Use entity_type and the entry's id as resource_id " <>
                    "from list_analysis_entries. Requires at least the accountant role. " <>
                    "Salary-pinned transfers have automatic categories derived from tracked time; do not tag them manually."
    end

    tool :set_analysis_entry_project_tags, EntityTag, :set_entity_project_tags do
      annotations title: "Set analysis entry project tags",
                  read_only_hint: false,
                  destructive_hint: true,
                  idempotent_hint: true,
                  open_world_hint: false

      description "Replace all categories of an analysis entry with the selected project tags, sharing its amount " <>
                    "equally between them. Use entity_type and the entry's id as resource_id from list_analysis_entries, " <>
                    "and tag_definition_ids from list_analysis_tags. An empty tag_definition_ids list removes all " <>
                    "categories, leaving the entry unassigned. Requires at least the accountant role. " <>
                    "Salary-pinned transfers have automatic categories derived from tracked time; do not tag them manually."
    end
  end

  resources do
    resource TagDefinition

    resource EntityTag

    resource Entry
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  @doc """
  Computes income, expenses, and net profit for a date range.

  Invoices are assigned to the month of sale (not issue). Only truly standalone
  transactions (skipped AND not matched) and transfers pinned to a salary are
  included to prevent double-counting. Transfers between the organization's own
  bank accounts are excluded.

  Transfers pinned to a salary are assigned to the salary month, not the
  booking date. Pinned salaries carry derived, unsaved project tags for every
  project the employee logged time on in the salary month, weighted by that
  time, or the company tag without such work.

  Entities tagged as `:internal` remain editable in entry lists but are excluded from totals.

  Returns the existing signed totals and entity lists, plus `:income_categories`
  and `:expense_categories`. Category rows contain `:key` (`{:project, id}`,
  `:company` or `:unassigned`), `:name` (nil for built-ins), `:color` and a positive
  Decimal PLN `:amount`. Each normalized entity amount is rounded to cents and
   allocated between projects by tag weight (equally unless weighted).
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
      %{date_from: date_from, date_to: date_to, date_field: :sale_date, merge_corrections: true}
      |> Invoicing.list_sales_invoices!(
        load: [:buyer_display_name_label, :effective_amount, :sales_invoice_items, :transactions],
        scope: analysis_scope
      )
      |> Enum.filter(&analysis_relevant_invoice?(&1, own_account_ibans))

    cost_invoices =
      %{date_from: date_from, date_to: date_to, date_field: :sale_date, merge_corrections: true}
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

    skipped_transactions =
      %{date_from: date_from, date_to: date_to, reconciliation: :skipped}
      |> Finances.list_transactions!(scope: analysis_scope)
      |> Enum.reject(&own_account_transfer?(&1, own_account_ibans))

    salary_transactions =
      %{salary_assigned: true}
      |> Finances.list_transactions!(scope: analysis_scope)
      |> Enum.filter(&(&1.salary_month in Date.range(date_from, date_to)))

    transactions = skipped_transactions ++ salary_transactions

    all_entities = build_entity_id_list(sales_invoices, cost_invoices, skipped_transactions)

    entity_tags_map =
      all_entities
      |> load_entity_tags_map(scope)
      |> Map.merge(salary_tags_map(salary_transactions, analysis_scope, scope))

    %{
      transactions: filter_entities(transactions, :transaction, entity_tags_map, []),
      sales_invoices: filter_entities(sales_invoices, :sales_invoice, entity_tags_map, []),
      cost_invoices: filter_entities(cost_invoices, :cost_invoice, entity_tags_map, [])
    }
  end

  @doc """
  Lists unrealized entries up to `date_to`, which are missing from the totals:
  issued invoices (by sale date) without a linked transaction and transactions
  (by booking date) without an invoice or salary, neither skipped. Transfers
  between own accounts are excluded. Entries are split by direction and sorted
  by date; `:income` and `:expenses` are their positive PLN sums.
  """
  @spec get_unrealized_entries(Date.t(), Scope.t()) :: %{
          income_entries: [SalesInvoice.t() | Transaction.t()],
          expense_entries: [CostInvoice.t() | Transaction.t()],
          income: Decimal.t(),
          expenses: Decimal.t()
        }
  def get_unrealized_entries(date_to, scope) do
    analysis_scope = analysis_scope(scope)
    own_account_ibans = own_account_ibans(scope)

    args = %{
      date_to: date_to,
      date_field: :sale_date,
      merge_corrections: true,
      reconciliation: :pending
    }

    sales_invoices =
      args
      |> Map.put(:submission, :confirmed)
      |> Invoicing.list_sales_invoices!(
        load: [
          :buyer_display_name_label,
          :effective_amount,
          :effective_due_date,
          :sales_invoice_items
        ],
        scope: analysis_scope
      )

    cost_invoices =
      Invoicing.list_cost_invoices!(args,
        load: [
          :effective_seller_display_name,
          :effective_sale_date,
          :effective_amount,
          :effective_due_date
        ],
        scope: analysis_scope
      )

    {incoming, outgoing} =
      %{date_to: date_to, reconciliation: :pending}
      |> Finances.list_transactions!(scope: analysis_scope)
      |> Enum.reject(&own_account_transfer?(&1, own_account_ibans))
      |> Enum.split_with(&Money.positive?(&1.amount))

    income_entries = Enum.sort_by(sales_invoices ++ incoming, &unrealized_date/1, Date)
    expense_entries = Enum.sort_by(cost_invoices ++ outgoing, &unrealized_date/1, Date)

    %{
      income_entries: income_entries,
      expense_entries: expense_entries,
      income: unrealized_sum(income_entries),
      expenses: unrealized_sum(expense_entries)
    }
  end

  defp unrealized_date(%Transaction{booking_date: date}), do: date
  defp unrealized_date(%{sale_date: date}), do: date

  defp unrealized_sum(entries) do
    today = Date.utc_today()

    entries
    |> Enum.flat_map(&normalized_entity(Map.put(&1, :entity_tags, []), today))
    |> Enum.reduce(Decimal.new(0), fn {amount, _tags}, sum ->
      amount |> Decimal.abs() |> Decimal.round(2) |> Decimal.add(sum)
    end)
  end

  @doc """
  Returns a list of dates (first day of each month) that have analysis-relevant
  entries. Uses `sale_date` for invoices, `booking_date` for standalone
  (skipped, unmatched) transactions and `salary_month` for salary-pinned ones.

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
      |> Enum.concat(
        %{salary_assigned: true}
        |> Finances.list_transactions!(opts)
        |> Enum.map(& &1.salary_month)
      )

    si_months =
      invoice_months(
        &Invoicing.list_sales_invoices!/2,
        :sale_date,
        %{merge_corrections: true},
        opts,
        own_account_ibans
      )

    ci_months =
      invoice_months(
        &Invoicing.list_cost_invoices!/2,
        :sale_date,
        %{merge_corrections: true},
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

  defp salary_tags_map([], _analysis_scope, _scope), do: %{}

  defp salary_tags_map(transactions, analysis_scope, scope) do
    seconds_by_salary =
      transactions
      |> Enum.map(& &1.salary_month)
      |> Enum.uniq()
      |> Enum.flat_map(fn month ->
        Timetracker.list_sessions!(
          %{month: month.month, year: month.year},
          load: [:duration, :member],
          query: [filter: [member: [user_id: [in: Enum.map(transactions, & &1.salary_user_id)]]]],
          scope: analysis_scope
        )
      end)
      |> Enum.reject(&(is_nil(&1.project_id) or &1.duration <= 0))
      |> Enum.group_by(&{&1.member.user_id, Date.beginning_of_month(DateTime.to_date(&1.start_datetime))})
      |> Map.new(fn {salary, sessions} ->
        {salary,
         sessions
         |> Enum.group_by(& &1.project_id, & &1.duration)
         |> Map.new(fn {id, d} -> {id, Enum.sum(d)} end)}
      end)

    tag_definitions_by_project =
      %{ids: seconds_by_salary |> Map.values() |> Enum.flat_map(&Map.keys/1) |> Enum.uniq()}
      |> Timetracker.list_projects!(load: [:tag_definition], scope: scope)
      |> Map.new(&{&1.id, &1.tag_definition})

    Map.new(transactions, fn transaction ->
      salary = {transaction.salary_user_id, transaction.salary_month}

      tags =
        for {project_id, seconds} <- Map.get(seconds_by_salary, salary, %{}),
            definition = Map.get(tag_definitions_by_project, project_id),
            definition != nil do
          Ash.Resource.put_metadata(
            %EntityTag{
              kind: :project,
              tag_definition_id: definition.id,
              tag_definition: definition
            },
            :weight,
            seconds
          )
        end

      {{:transaction, transaction.id}, if(tags == [], do: [%EntityTag{kind: :company}], else: tags)}
    end)
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
