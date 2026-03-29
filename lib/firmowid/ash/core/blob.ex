defmodule Firmowid.Ash.Core.Blob do
  @moduledoc """
  Read-only Ash wrapper for the `blobs` table.

  Attribute multitenancy via `organization_id`. Writes still go through
  `Firmowid.Blobs` context during migration.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "blobs"
    repo Firmowid.Repo
    migrate? false
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

    attribute :blob_path, :string, public?: true, allow_nil?: false
    attribute :blob_checksum, :string, public?: true, allow_nil?: false
    attribute :original_filename, :string, public?: true, allow_nil?: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end
end
