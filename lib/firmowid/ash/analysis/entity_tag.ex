defmodule Firmowid.Ash.Analysis.EntityTag do
  @moduledoc """
  Polymorphic join between tag definitions and taggable entities
  (transactions, sales invoices, cost invoices).

  Uses AshPostgres `polymorphic? true` — one resource definition backed by
  3 separate tables:

    * `sales_invoice_entity_tags` (FK → sales_invoices.id)
    * `cost_invoice_entity_tags`  (FK → cost_invoices.id)
    * `transaction_entity_tags`   (FK → transactions.id)

  Each entity tag has a `kind`:

    * `:project` — references a user-created `TagDefinition` (requires `tag_definition_id`)
    * `:company` — built-in "firma" category (no `tag_definition_id`)
    * `:internal` — built-in category that excludes entity from calculations

  Categories are mutually exclusive per entity: an entity is either tagged with
  one or more project tags, OR marked as company, OR marked as internal.
  This is enforced by per-table database triggers.

  ## Table resolution

  Table context is set per-action via `set_context`. For reads from parent
  Ecto schemas (while they're still Ecto), use the `{source, schema}` tuple
  in `has_many`:

      has_many :entity_tags, {"sales_invoice_entity_tags", Firmowid.Ash.Analysis.EntityTag},
        foreign_key: :resource_id
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Analysis,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Analysis.Validations.KindTagDefinitionConsistency
  alias Firmowid.Ash.Resource

  require Ash.Query
  require Resource

  postgres do
    polymorphic?(true)
    repo(Firmowid.Repo)
    migrate?(false)
  end

  code_interface do
    define :for_sales_invoices
    define :for_cost_invoices
    define :for_transactions
    define :set_entity_category
    define :set_entity_project_tags
    define :clear_entity_tags
  end

  actions do
    defaults [:read, :destroy]

    # ── Table-specific read actions ─────────────────────────────────────

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

    # ── Table-specific create actions ───────────────────────────────────

    create :tag_sales_invoice do
      description "Create an entity tag in the sales_invoice_entity_tags table."
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

    # ── Generic dispatch actions ────────────────────────────────────────
    # These resolve entity_type → table at runtime, matching how the LiveView
    # sends entity_type as a string param from UI events.

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
    end

    action :set_entity_project_tags, {:array, :struct} do
      description """
      Sets project tags on an entity, replacing any existing tags.
      Pass an empty list of tag_definition_ids to remove all tags.
      """

      argument :entity_type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:sales_invoice, :cost_invoice, :transaction]]

      argument :resource_id, :uuid, allow_nil?: false
      argument :tag_definition_ids, {:array, :uuid}, allow_nil?: false

      run fn input, context ->
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
    end

    action :clear_entity_tags, :integer do
      description "Removes all tags from an entity. Returns the count of deleted rows."

      argument :entity_type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:sales_invoice, :cost_invoice, :transaction]]

      argument :resource_id, :uuid, allow_nil?: false

      run fn input, context ->
        table = table_for_entity_type(input.arguments.entity_type)
        scope = build_scope(context)
        count = clear_tags_for_resource(table, input.arguments.resource_id, scope)
        {:ok, count}
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :employee)
    end
  end

  validations do
    validate KindTagDefinitionConsistency, on: [:create]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :kind, :atom,
      public?: true,
      allow_nil?: false,
      default: :project,
      constraints: [one_of: [:project, :company, :internal]]

    attribute :resource_id, :uuid, public?: true, allow_nil?: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :tag_definition, TagDefinition do
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────

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
      current_user: context.actor,
      current_tenant: context.tenant
    }
  end

  defp clear_tags_for_resource(table, resource_id, scope) do
    __MODULE__
    |> Ash.Query.set_context(%{data_layer: %{table: table}})
    |> Ash.Query.filter(resource_id == ^resource_id)
    |> Ash.read!(scope: scope)
    |> Enum.each(fn tag ->
      tag
      |> Ash.Changeset.for_destroy(:destroy, %{}, scope: scope)
      |> Ash.Changeset.set_context(%{data_layer: %{table: table}})
      |> Ash.destroy!()
    end)
  end
end
