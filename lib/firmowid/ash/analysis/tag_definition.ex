defmodule Firmowid.Ash.Analysis.TagDefinition do
  @moduledoc """
  Custom category or project tag with a name and color.

  Full CRUD Ash resource backed by the `tag_definitions` table. Replaces
  both the legacy Ecto schema (`Firmowid.Analysis.TagDefinition`) and the
  read-only Core wrapper (`Firmowid.Ash.Core.TagDefinition`).

  Attribute multitenancy via `organization_id`. Names are unique per
  organization (enforced by `tags_organization_id_name_index`).
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Analysis,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Analysis.Changes.PickTagColor
  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Checks.ActorRole
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Resource
  alias Firmowid.Ash.Scope

  require Resource

  postgres do
    table "tag_definitions"
    repo Firmowid.Repo

    custom_statements do
      statement :analysis_taxes_category do
        up "ALTER TYPE entity_tag_kind ADD VALUE IF NOT EXISTS 'taxes';"
        # PostgreSQL cannot remove an enum value; older code simply cannot assign it.
        down "SELECT 1;"
      end
    end
  end

  code_interface do
    define :read, action: :read
    define :destroy, action: :destroy
    define :create_tag_definition
    define :update_tag_definition
    define :set_overhead, args: [:overhead]
    define :list_tag_definitions
    define :get_tag_definition, action: :read, get_by: [:id]
    define :create_for_project, args: [:name]
    define :create_for_entry
  end

  actions do
    defaults [:read, :destroy]

    read :list_tag_definitions do
      description "List organization tag definitions by name with optional ID and search filters."
      argument :ids, {:array, :uuid}
      argument :search, :string

      prepare build(filter: expr(id in ^arg(:ids))) do
        where present(:ids)
      end

      prepare build(filter: expr(contains(name, ^arg(:search)))) do
        where present(:search)
      end

      prepare build(sort: [name: :asc])
    end

    create :create_tag_definition do
      description "Creates a new tag definition with a name and optional color."
      primary? true
      accept [:name, :color]
    end

    create :create_for_project do
      description "Creates a tag definition for a project with an auto-assigned color."
      accept [:name]
      change PickTagColor
    end

    create :create_for_entry do
      description "Creates a custom category and assigns it to an entry in one transaction."
      accept [:name]
      touches_resources [EntityTag]

      argument :entity_type, :atom,
        allow_nil?: false,
        constraints: [one_of: [:sales_invoice, :cost_invoice, :transaction]]

      argument :resource_id, :uuid, allow_nil?: false

      change fn changeset, context ->
        Ash.Changeset.after_action(changeset, fn changeset, category ->
          scope = %Scope{actor: context.actor, tenant: context.tenant}
          type = Ash.Changeset.get_argument(changeset, :entity_type)
          id = Ash.Changeset.get_argument(changeset, :resource_id)

          current_ids =
            %{entity_type: type, resource_ids: [id]}
            |> EntityTag.list!(scope: scope)
            |> Enum.filter(&(&1.kind == :project))
            |> Enum.map(& &1.tag_definition_id)

          with {:ok, _tags} <-
                 EntityTag.set_entity_project_tags(
                   %{
                     entity_type: type,
                     resource_id: id,
                     tag_definition_ids: current_ids ++ [category.id]
                   },
                   scope: scope
                 ) do
            {:ok, category}
          end
        end)
      end
    end

    update :update_tag_definition do
      description "Updates name and/or color of a tag definition."
      primary? true
      accept [:name, :color]
      require_atomic? false
    end

    update :set_overhead do
      description "Marks a tag definition as a company function counted in overhead, or back as a project."
      accept [:overhead]
      require_atomic? false
    end
  end

  policies do
    bypass [
      {SystemActorRole, roles: [:organization_cleanup]},
      action([:read, :list_tag_definitions, :destroy])
    ] do
      authorize_if expr(not is_nil(^actor(:org_id)) and organization_id == ^actor(:org_id))
    end

    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end

    bypass {SystemActorRole, roles: [:project_tag_manager]} do
      authorize_if action([
                     :create_for_project,
                     :read,
                     :update_tag_definition,
                     :destroy
                   ])
    end

    bypass {SystemActorRole, roles: [:invoice_matcher, :analysis_classifier]} do
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
      {Firmowid.Ash.Checks.AtLeastRole, role: :accountant}
    ] do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :color, :string, public?: true, default: "#6B7280"

    attribute :overhead, :boolean,
      public?: true,
      allow_nil?: false,
      default: false,
      description: "A company function such as marketing or HR: its shares count as overhead, not as a project."

    Resource.firmowid_timestamps()
  end

  relationships do
    has_many :projects, Firmowid.Ash.Timetracker.Project do
      destination_attribute :tag_definition_id
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_name_per_org, [:name, :organization_id],
      pre_check?: true,
      message: "has already been taken"
  end
end
