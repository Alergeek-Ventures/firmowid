defmodule Firmowid.Ash.Core.TagDefinition do
  @moduledoc """
  Read-only Ash wrapper for the `tag_definitions` table.

  Attribute multitenancy via `organization_id`. Writes still go through
  `Firmowid.Analysis` context during migration.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "tag_definitions"
    repo(Firmowid.Repo)
    migrate?(false)
  end

  actions do
    defaults [:read]
  end

  policies do
    policy action_type(:read) do
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

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end
end
