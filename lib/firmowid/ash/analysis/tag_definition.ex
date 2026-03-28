defmodule Firmowid.Ash.Analysis.TagDefinition do
  @moduledoc """
  User-created project tag with a name and color.

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
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "tag_definitions"
    repo(Firmowid.Repo)
    migrate?(false)
  end

  code_interface do
    define :create_tag_definition
    define :update_tag_definition
    define :destroy_tag_definition
    define :list_tag_definitions
    define :get_tag_definition, action: :read, get_by: [:id]
    define :create_for_project, args: [:name]
  end

  actions do
    defaults [:read, :destroy]

    read :list_tag_definitions do
      description "Lists all tag definitions for the current organization, ordered by name."
      prepare build(sort: [name: :asc])
    end

    create :create_tag_definition do
      description "Creates a new tag definition with a name and optional color."
      accept [:name, :color]
    end

    create :create_for_project do
      description "Creates a tag definition for a project with an auto-assigned color."
      accept [:name]
      change PickTagColor
    end

    update :update_tag_definition do
      description "Updates name and/or color of a tag definition."
      accept [:name, :color]
      require_atomic? false
    end

    destroy :destroy_tag_definition do
      description "Deletes a tag definition. Associated entity tags are cleaned up via ON DELETE CASCADE."
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

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :color, :string, public?: true, default: "#6B7280"

    Resource.firmowid_timestamps()
  end

  relationships do
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
