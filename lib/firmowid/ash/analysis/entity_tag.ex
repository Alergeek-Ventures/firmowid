defmodule Firmowid.Ash.Analysis.EntityTag do
  @moduledoc """
  Polymorphic join between tag definitions and taggable entities
  (transactions, sales invoices, cost invoices).

  Uses AshPostgres `polymorphic? true`, with per-action table context selecting
  `sales_invoice_entity_tags`, `cost_invoice_entity_tags`, or `transaction_entity_tags`.

  A tag's `kind` is `:project` (requires a `TagDefinition`), `:company` (the built-in
  "firma" category), or `:internal` (excluded from calculations). Per-table database
  triggers enforce mutually exclusive categories: one or more project tags,
  company, or internal. `assignment_source` separates human examples from Jev assignments.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Analysis,
    authorizers: [Ash.Policy.Authorizer],
    fragments: [Firmowid.Ash.Analysis.EntityTag.Persistence]

  alias Firmowid.Ash.Checks.AtLeastRole
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Invoicing

  require Ash.Query

  code_interface do
    define :read
    define :destroy
    define :for_sales_invoices
    define :for_cost_invoices
    define :for_transactions
    define :set_entity_category
    define :set_entity_project_tags
    define :clear_entity_tags
    define :tag_sales_invoice
    define :tag_cost_invoice
    define :tag_transaction
    define :create_classified
    define :list
    define :classify_month
    define :assign_month
    define :assign_if_unassigned
  end

  actions do
    defaults [:read, :destroy]

    read :list do
      description "List tags for an entity type, optionally restricted to resource IDs."

      argument :entity_type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:sales_invoice, :cost_invoice, :transaction]]

      argument :resource_ids, {:array, :uuid}

      prepare fn query, _context ->
        query =
          Ash.Query.set_context(query, %{
            data_layer: %{
              table: table_for_entity_type(Ash.Query.get_argument(query, :entity_type))
            }
          })

        case Ash.Query.get_argument(query, :resource_ids) do
          nil -> query
          ids -> Ash.Query.filter(query, resource_id in ^ids)
        end
      end
    end

    action :classify_month, :struct do
      description "Start background classification of unassigned entities for a month."
      argument :month, :date, allow_nil?: false
      run Firmowid.Ash.Analysis.Actions.ClassifyMonth
    end

    action :assign_month, :boolean do
      description "Assign classification shares to unassigned entities for a month."
      argument :month, :date, allow_nil?: false
      run Firmowid.Ash.Analysis.Actions.AssignMonth
    end

    action :assign_if_unassigned, {:array, :struct} do
      description "Lock an entity and assign classification shares only if it has no tags."

      argument :entity_type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:sales_invoice, :cost_invoice, :transaction]]

      argument :resource_id, :uuid, allow_nil?: false
      argument :shares, {:array, :map}, allow_nil?: false

      run fn input, context ->
        scope = build_scope(context)

        transaction(input.arguments.entity_type, input.arguments.resource_id, scope, fn ->
          case list!(
                 %{
                   entity_type: input.arguments.entity_type,
                   resource_ids: [input.arguments.resource_id]
                 },
                 scope: scope
               ) do
            [] ->
              tags =
                Enum.map(input.arguments.shares, fn share ->
                  create_classified!(
                    Map.merge(share, %{
                      entity_type: input.arguments.entity_type,
                      resource_id: input.arguments.resource_id
                    }),
                    scope: scope
                  )
                end)

              {:ok, tags}

            _ ->
              {:ok, []}
          end
        end)
      end
    end

    create :create_classified do
      description "Append a classification share; orchestration locks and verifies the entity is unassigned."
      accept [:kind, :resource_id, :tag_definition_id]

      argument :entity_type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:sales_invoice, :cost_invoice, :transaction]]

      change set_attribute(:assignment_source, :jev)

      change fn changeset, _context ->
        type = Ash.Changeset.get_argument(changeset, :entity_type)
        Ash.Changeset.set_context(changeset, %{data_layer: %{table: table_for_entity_type(type)}})
      end
    end

    read :for_sales_invoices do
      description "Read entity tags from the sales_invoice_entity_tags table."
      prepare set_context(%{data_layer: %{table: "sales_invoice_entity_tags"}})
    end

    read :for_cost_invoices do
      description "Read entity tags from the cost_invoice_entity_tags table."
      prepare set_context(%{data_layer: %{table: "cost_invoice_entity_tags"}})
    end

    read :for_transactions do
      description "Read entity tags from the transaction_entity_tags table."
      prepare set_context(%{data_layer: %{table: "transaction_entity_tags"}})
    end

    create :tag_sales_invoice do
      description "Create an entity tag in the sales_invoice_entity_tags table."
      primary? true
      accept [:kind, :resource_id, :tag_definition_id]
      change set_context(%{data_layer: %{table: "sales_invoice_entity_tags"}})
    end

    create :tag_cost_invoice do
      description "Create an entity tag in the cost_invoice_entity_tags table."
      accept [:kind, :resource_id, :tag_definition_id]
      change set_context(%{data_layer: %{table: "cost_invoice_entity_tags"}})
    end

    create :tag_transaction do
      description "Create an entity tag in the transaction_entity_tags table."
      accept [:kind, :resource_id, :tag_definition_id]
      change set_context(%{data_layer: %{table: "transaction_entity_tags"}})
    end

    action :set_entity_category, {:array, :struct} do
      description """
      Sets a built-in category (:company or :internal) on an entity.
      Clears any existing tags first to maintain mutual exclusivity.
      """

      argument :entity_type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:sales_invoice, :cost_invoice, :transaction]]

      argument :resource_id, :uuid, allow_nil?: false
      argument :kind, :atom, allow_nil?: false, constraints: [one_of: [:company, :internal]]

      run fn input, context ->
        transaction(
          input.arguments.entity_type,
          input.arguments.resource_id,
          build_scope(context),
          fn ->
            table = table_for_entity_type(input.arguments.entity_type)
            scope = build_scope(context)

            clear_tags_for_resource(table, input.arguments.resource_id, scope)

            result =
              __MODULE__
              |> Ash.Changeset.for_create(
                create_action_for_entity_type(input.arguments.entity_type),
                %{kind: input.arguments.kind, resource_id: input.arguments.resource_id},
                scope: scope
              )
              |> Ash.create!()

            {:ok, [result]}
          end
        )
      end
    end

    action :set_entity_project_tags, {:array, :struct} do
      description """
      Sets project tags on an entity, replacing any existing tags.
      Pass an empty list of tag_definition_ids to remove all tags.
      """

      primary? true

      argument :entity_type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:sales_invoice, :cost_invoice, :transaction]]

      argument :resource_id, :uuid, allow_nil?: false
      argument :tag_definition_ids, {:array, :uuid}, allow_nil?: false

      run fn input, context ->
        transaction(
          input.arguments.entity_type,
          input.arguments.resource_id,
          build_scope(context),
          fn ->
            table = table_for_entity_type(input.arguments.entity_type)
            scope = build_scope(context)
            action = create_action_for_entity_type(input.arguments.entity_type)

            clear_tags_for_resource(table, input.arguments.resource_id, scope)

            tags =
              Enum.map(input.arguments.tag_definition_ids, fn tag_def_id ->
                __MODULE__
                |> Ash.Changeset.for_create(
                  action,
                  %{
                    kind: :project,
                    resource_id: input.arguments.resource_id,
                    tag_definition_id: tag_def_id
                  },
                  scope: scope
                )
                |> Ash.create!()
              end)

            {:ok, tags}
          end
        )
      end
    end

    action :clear_entity_tags, :integer do
      description "Removes all tags from an entity. Returns the count of deleted rows."

      argument :entity_type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:sales_invoice, :cost_invoice, :transaction]]

      argument :resource_id, :uuid, allow_nil?: false

      run fn input, context ->
        transaction(
          input.arguments.entity_type,
          input.arguments.resource_id,
          build_scope(context),
          fn ->
            table = table_for_entity_type(input.arguments.entity_type)
            scope = build_scope(context)
            count = clear_tags_for_resource(table, input.arguments.resource_id, scope)
            {:ok, count}
          end
        )
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    bypass {SystemActorRole, roles: [:invoice_matcher]} do
      authorize_if action_type(:read)
    end

    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy [
      action_type([:create, :update, :destroy]),
      {AtLeastRole, role: :accountant}
    ] do
      authorize_if always()
    end

    policy [action_type(:action), {AtLeastRole, role: :accountant}] do
      authorize_if always()
    end
  end

  @entity_type_tables %{
    sales_invoice: "sales_invoice_entity_tags",
    cost_invoice: "cost_invoice_entity_tags",
    transaction: "transaction_entity_tags"
  }

  @entity_type_create_actions %{
    sales_invoice: :tag_sales_invoice,
    cost_invoice: :tag_cost_invoice,
    transaction: :tag_transaction
  }

  @doc false
  def table_for_entity_type(entity_type), do: Map.fetch!(@entity_type_tables, entity_type)

  defp create_action_for_entity_type(entity_type), do: Map.fetch!(@entity_type_create_actions, entity_type)

  defp build_scope(context) do
    %Firmowid.Ash.Scope{
      actor: context.actor,
      tenant: context.tenant
    }
  end

  defp transaction(type, id, scope, fun) do
    resource =
      case type do
        :sales_invoice -> Firmowid.Ash.Invoicing.SalesInvoice
        :cost_invoice -> Firmowid.Ash.Invoicing.CostInvoice
        :transaction -> Firmowid.Ash.Finances.Transaction
      end

    case Ash.DataLayer.transaction(
           resource,
           fn ->
             query = resource |> Ash.Query.new() |> Ash.Query.lock(:for_update)

             case type do
               :sales_invoice ->
                 Invoicing.get_sales_invoice!(id, scope: scope, query: query)

               :cost_invoice ->
                 Invoicing.get_cost_invoice!(id, scope: scope, query: query)

               :transaction ->
                 Firmowid.Ash.Finances.get_transaction!(id, scope: scope, query: query)
             end

             fun.()
           end,
           nil,
           %{type: :custom, metadata: %{}},
           rollback_on_error?: true
         ) do
      {:ok, result} -> result
      {:error, error} -> {:error, error}
    end
  end

  defp clear_tags_for_resource(table, resource_id, scope) do
    query =
      __MODULE__
      |> Ash.Query.set_context(%{data_layer: %{table: table}})
      |> Ash.Query.filter(resource_id == ^resource_id)

    result =
      __MODULE__.destroy(query, %{},
        scope: scope,
        context: %{data_layer: %{table: table}},
        bulk_options: [
          strategy: :stream,
          return_errors?: true,
          return_records?: true,
          stop_on_error?: true
        ]
      )

    case result do
      %Ash.BulkResult{status: :success, records: records} -> length(records || [])
      %Ash.BulkResult{errors: errors} -> raise Ash.Error.to_error_class(errors)
    end
  end
end
