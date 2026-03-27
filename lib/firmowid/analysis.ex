defmodule Firmowid.Analysis do
  @moduledoc """
  Context for financial analysis: tag management, entity tagging, and
  organization-level totals calculation.

  Tags come in three kinds (mutually exclusive per entity):

    * `:project` — user-created labels with name and color, backed by `TagDefinition`
    * `:company` — built-in "firma" category (company overhead)
    * `:internal` — built-in category that excludes the entity from all calculations

  Only entities that are matched (linked to an invoice/transaction via join table)
  or marked `skip_invoicing` can be tagged. This is enforced at the database level.
  """
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Firmowid.Analysis.EntityTag
  alias Firmowid.Analysis.TagDefinition
  alias Firmowid.CostInvoices
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.CostInvoices.CostInvoicesTransactions
  alias Firmowid.Currencies
  alias Firmowid.Finances
  alias Firmowid.Finances.Transaction
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.SalesInvoices.SalesInvoicesTransactions

  def authorize(:read, %{role: :admin}, _), do: true
  def authorize(:create, %{role: :admin}, _), do: true
  def authorize(:update, %{role: :admin}, _), do: true
  def authorize(:delete, %{role: :admin}, _), do: true
  def authorize(_, _, _), do: false

  # ---------------------------------------------------------------------------
  # Tag definitions CRUD (project tags only — company/internal are code-defined)
  # ---------------------------------------------------------------------------

  @doc "Lists all tag definitions for the current organization, ordered by name."
  @spec list_tag_definitions() :: [TagDefinition.t()]
  def list_tag_definitions do
    TagDefinition
    |> order_by([t], t.name)
    |> Repo.all()
  end

  @doc "Gets a single tag definition by ID."
  @spec get_tag_definition!(binary()) :: TagDefinition.t()
  def get_tag_definition!(id), do: Repo.get!(TagDefinition, id)

  @doc "Creates a new tag definition."
  @spec create_tag_definition(map()) :: {:ok, TagDefinition.t()} | {:error, Ecto.Changeset.t()}
  def create_tag_definition(attrs \\ %{}) do
    %TagDefinition{}
    |> TagDefinition.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates an existing tag definition."
  @spec update_tag_definition(TagDefinition.t(), map()) ::
          {:ok, TagDefinition.t()} | {:error, Ecto.Changeset.t()}
  def update_tag_definition(%TagDefinition{} = tag, attrs) do
    tag
    |> TagDefinition.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a tag definition and all associated entity tags."
  @spec delete_tag_definition(TagDefinition.t()) ::
          {:ok, TagDefinition.t()} | {:error, Ecto.Changeset.t()}
  def delete_tag_definition(%TagDefinition{} = tag) do
    Repo.delete(tag)
  end

  @doc "Returns a changeset for a tag definition form."
  @spec change_tag_definition(TagDefinition.t(), map()) :: Ecto.Changeset.t()
  def change_tag_definition(%TagDefinition{} = tag, attrs \\ %{}) do
    TagDefinition.changeset(tag, attrs)
  end

  # ---------------------------------------------------------------------------
  # Project ↔ tag definition integration
  # ---------------------------------------------------------------------------

  @project_tag_colors ~w(#2563EB #059669 #D97706 #7C3AED #DB2777 #0891B2 #4F46E5 #DC2626 #65A30D #0D9488)

  @doc """
  Creates a `TagDefinition` for a project, returning its ID.

  Picks a color from a rotating palette based on the count of existing
  tag definitions. Called by `Timetracker.create_project/1`.
  """
  @spec create_project_tag(String.t()) :: {:ok, TagDefinition.t()} | {:error, Ecto.Changeset.t()}
  def create_project_tag(name) do
    color = pick_project_tag_color()
    create_tag_definition(%{name: name, color: color})
  end

  @doc """
  Syncs a project's tag definition name when the project is renamed.

  No-op when the tag definition already has the same name or when
  `tag_definition_id` is nil. Returns `{:ok, :synced}` on success so it
  can be used inside `Ecto.Multi.run/3`.
  """
  @spec sync_project_tag_name(binary() | nil, String.t()) ::
          {:ok, :synced} | {:error, Ecto.Changeset.t()}
  def sync_project_tag_name(nil, _name), do: {:ok, :synced}

  def sync_project_tag_name(tag_definition_id, name) do
    case Repo.get(TagDefinition, tag_definition_id) do
      nil ->
        {:ok, :synced}

      %TagDefinition{name: ^name} ->
        {:ok, :synced}

      tag_def ->
        case Repo.update(TagDefinition.changeset(tag_def, %{name: name})) do
          {:ok, _} -> {:ok, :synced}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @doc """
  Deletes orphaned tag definitions by ID. Called after a project is deleted.

  The tag definition's ON DELETE CASCADE handles entity_tags cleanup.
  Returns `{:ok, :deleted}` so it can be used inside `Ecto.Multi.run/3`.
  """
  @spec delete_tag_definition_by_id(binary() | nil) :: {:ok, :deleted}
  def delete_tag_definition_by_id(nil), do: {:ok, :deleted}

  def delete_tag_definition_by_id(id) do
    Repo.delete_all(from(t in TagDefinition, where: t.id == ^id))
    {:ok, :deleted}
  end

  defp pick_project_tag_color do
    count = Repo.aggregate(TagDefinition, :count)
    Enum.at(@project_tag_colors, rem(count, length(@project_tag_colors)))
  end

  # ---------------------------------------------------------------------------
  # Entity tagging
  # ---------------------------------------------------------------------------

  @doc """
  Sets a built-in category (`:company` or `:internal`) on an entity.

  Clears any existing tags for the entity first (within a transaction) to
  maintain mutual exclusivity between categories.
  """
  @spec set_entity_category(atom(), binary(), :company | :internal) ::
          {:ok, EntityTag.t()} | {:error, any()}
  def set_entity_category(entity_type, entity_id, kind) when kind in [:company, :internal] do
    Multi.new()
    |> Multi.delete_all(
      :clear_tags,
      from(et in EntityTag,
        where: et.entity_type == ^entity_type and et.entity_id == ^entity_id
      )
    )
    |> Multi.insert(:insert_tag, fn _changes ->
      EntityTag.changeset(%EntityTag{}, %{
        kind: kind,
        entity_type: entity_type,
        entity_id: entity_id
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{insert_tag: entity_tag}} -> {:ok, entity_tag}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Sets project tags on an entity, replacing any existing tags.

  Pass an empty list to remove all tags. Runs within a transaction to
  maintain mutual exclusivity between categories.
  """
  @spec set_entity_project_tags(atom(), binary(), [binary()]) ::
          {:ok, [EntityTag.t()]} | {:error, any()}
  def set_entity_project_tags(entity_type, entity_id, tag_definition_ids) do
    multi =
      Multi.delete_all(
        Multi.new(),
        :clear_tags,
        from(et in EntityTag,
          where: et.entity_type == ^entity_type and et.entity_id == ^entity_id
        )
      )

    multi =
      tag_definition_ids
      |> Enum.with_index()
      |> Enum.reduce(multi, fn {tag_def_id, idx}, acc ->
        Multi.insert(acc, {:insert_tag, idx}, fn _changes ->
          EntityTag.changeset(%EntityTag{}, %{
            kind: :project,
            tag_definition_id: tag_def_id,
            entity_type: entity_type,
            entity_id: entity_id
          })
        end)
      end)

    multi
    |> Repo.transaction()
    |> case do
      {:ok, changes} ->
        tags =
          changes
          |> Enum.filter(fn {key, _} -> match?({:insert_tag, _}, key) end)
          |> Enum.sort_by(fn {{:insert_tag, idx}, _} -> idx end)
          |> Enum.map(fn {_, tag} -> tag end)

        {:ok, tags}

      {:error, _step, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Removes all tags from an entity.
  """
  @spec clear_entity_tags(atom(), binary()) :: {non_neg_integer(), nil}
  def clear_entity_tags(entity_type, entity_id) do
    Repo.delete_all(from(et in EntityTag, where: et.entity_type == ^entity_type and et.entity_id == ^entity_id))
  end

  @doc """
  Returns all entity tags for a given entity, preloaded with tag definitions.
  """
  @spec get_entity_tags(atom(), binary()) :: [EntityTag.t()]
  def get_entity_tags(entity_type, entity_id) do
    EntityTag
    |> where([et], et.entity_type == ^entity_type and et.entity_id == ^entity_id)
    |> preload(:tag_definition)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Organization totals calculation
  # ---------------------------------------------------------------------------

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
  @spec get_organization_totals(Date.t(), Date.t(), keyword()) :: map()
  def get_organization_totals(date_from, date_to, opts \\ []) do
    tag_filters = Keyword.get(opts, :tag_filters, [])

    # Fetch entities for the date range, keeping only analysis-relevant ones.
    # Invoices must be matched (has linked transactions) or skipped; standalone
    # transactions are already filtered by `list_skipped_unmatched_transactions`.
    sales_invoices =
      date_from
      |> SalesInvoices.list_sales_invoices_by_sale_date(date_to)
      |> Enum.filter(&matched_or_skipped?/1)

    cost_invoices =
      date_from
      |> CostInvoices.list_cost_invoices_by_sale_date(date_to)
      |> Enum.filter(&matched_or_skipped?/1)

    transactions = Finances.list_skipped_unmatched_transactions(date_from, date_to)

    # Load entity tags for filtering
    all_entities = build_entity_id_list(sales_invoices, cost_invoices, transactions)
    entity_tags_map = load_entity_tags_map(all_entities)

    # Filter: always exclude internal, then apply tag_filters if any
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
  (skipped, unmatched) transactions — consistent with `get_organization_totals/3`.

  Only includes invoices that are matched (linked to bank transactions) or
  marked `skip_invoicing`. Excludes entities tagged as `:internal`.
  """
  @spec get_months_with_entries() :: [Date.t()]
  def get_months_with_entries do
    sales_match_query =
      from(sit in SalesInvoicesTransactions,
        where: sit.transaction_id == parent_as(:transaction).id
      )

    cost_match_query =
      from(cit in CostInvoicesTransactions,
        where: cit.transaction_id == parent_as(:transaction).id
      )

    # Internal transfer exclusion subqueries use different parent bindings:
    # :transaction for the transactions query, :entity for invoices.
    tx_internal_query =
      from(et in EntityTag,
        where:
          et.entity_type == :transaction and
            et.kind == :internal and
            et.entity_id == parent_as(:transaction).id
      )

    si_internal_query =
      from(et in EntityTag,
        where:
          et.entity_type == :sales_invoice and
            et.kind == :internal and
            et.entity_id == parent_as(:entity).id
      )

    ci_internal_query =
      from(et in EntityTag,
        where:
          et.entity_type == :cost_invoice and
            et.kind == :internal and
            et.entity_id == parent_as(:entity).id
      )

    # Each branch must select organization_id so the Repo's automatic
    # organization scoping can filter on the outer subquery.
    transactions_query =
      from(t in Transaction,
        as: :transaction,
        where: t.skip_invoicing == true,
        where: not exists(subquery(sales_match_query)),
        where: not exists(subquery(cost_match_query)),
        where: not exists(subquery(tx_internal_query)),
        select: %{month: t.booking_date, organization_id: t.organization_id}
      )

    # Only include invoices that are matched or skipped (analysis-relevant).
    # IMPORTANT: This is the SQL equivalent of `matched_or_skipped?/1` used
    # in `get_organization_totals/3`. Keep both in sync.
    si_matched_query =
      from(sit in SalesInvoicesTransactions,
        where: sit.sales_invoice_id == parent_as(:entity).id
      )

    ci_matched_query =
      from(cit in CostInvoicesTransactions,
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

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp get_amount_and_currency(%SalesInvoice{} = entity) do
    value =
      entity
      |> SalesInvoice.get_gross_value()
      |> Decimal.abs()

    {value, entity.currency}
  end

  defp get_amount_and_currency(%CostInvoice{} = entity) do
    value = entity.total_amount |> Decimal.abs() |> Decimal.mult(Decimal.new("-1"))
    {value, entity.currency}
  end

  defp get_amount_and_currency(%Transaction{} = entity) do
    {entity.transaction_amount, entity.transaction_currency}
  end

  # An invoice is analysis-relevant when it has been matched to at least one
  # bank transaction or explicitly marked `skip_invoicing`.  Unmatched,
  # non-skipped invoices are still in-flight in the invoicing workflow and
  # must not appear on the analysis dashboard.
  #
  # IMPORTANT: This rule is duplicated in SQL inside `get_months_with_entries/0`
  # (the `si_matched_query`/`ci_matched_query` subqueries and the
  # `skip_invoicing == true` WHERE clauses). If you change this logic, update
  # both places.
  defp matched_or_skipped?(%{skip_invoicing: true}), do: true
  defp matched_or_skipped?(%{transactions: txs}) when is_list(txs) and txs != [], do: true
  defp matched_or_skipped?(_), do: false

  # Builds a list of {entity_type, entity_id} tuples for bulk tag loading.
  defp build_entity_id_list(sales_invoices, cost_invoices, transactions) do
    si = Enum.map(sales_invoices, &{:sales_invoice, &1.id})
    ci = Enum.map(cost_invoices, &{:cost_invoice, &1.id})
    tx = Enum.map(transactions, &{:transaction, &1.id})
    si ++ ci ++ tx
  end

  # Loads all entity tags for the given entities in a single query.
  # Returns a map: {entity_type, entity_id} => [%EntityTag{}]
  defp load_entity_tags_map([]), do: %{}

  defp load_entity_tags_map(entity_ids) do
    # Group by entity_type for efficient querying
    grouped = Enum.group_by(entity_ids, &elem(&1, 0), &elem(&1, 1))

    conditions =
      Enum.reduce(grouped, dynamic(false), fn {entity_type, ids}, acc ->
        dynamic(
          [et],
          ^acc or (et.entity_type == ^entity_type and et.entity_id in ^ids)
        )
      end)

    EntityTag
    |> where(^conditions)
    |> preload(:tag_definition)
    |> Repo.all()
    |> Enum.group_by(&{&1.entity_type, &1.entity_id})
  end

  # Returns the entity's ID (works for any of the three entity structs).
  defp entity_id(%SalesInvoice{id: id}), do: id
  defp entity_id(%CostInvoice{id: id}), do: id
  defp entity_id(%Transaction{id: id}), do: id

  # Filters a list of entities and attaches entity_tags to each struct:
  # 1. Always excludes internal-tagged entities
  # 2. When tag_filters is non-empty, includes only entities matching at least one filter (OR)
  # 3. Overwrites entity.entity_tags with a plain list for display in the entries table.
  #    This is intentional — the entities are not persisted or re-preloaded after this point.
  defp filter_entities(entities, entity_type, entity_tags_map, tag_filters) do
    entities
    |> Enum.map(fn entity ->
      tags = Map.get(entity_tags_map, {entity_type, entity_id(entity)}, [])
      {%{entity | entity_tags: tags}, tags}
    end)
    |> Enum.filter(fn {_entity, tags} ->
      not internal?(tags) and matches_tag_filters?(tags, tag_filters)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp internal?(tags) do
    Enum.any?(tags, &(&1.kind == :internal))
  end

  # When no filters are active, all (non-internal-transfer) entities match.
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
