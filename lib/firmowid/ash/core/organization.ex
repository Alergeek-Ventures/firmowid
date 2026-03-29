defmodule Firmowid.Ash.Core.Organization do
  @moduledoc """
  Read-only Ash wrapper for the `organizations` table.

  No multitenancy — organizations are the identity layer.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "organizations"
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

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :nip, :string, public?: true, allow_nil?: false
    attribute :address, :string, public?: true
    attribute :phone_number, :string, public?: true
    attribute :organization_type, :string, public?: true
    attribute :correspondence_name, :string, public?: true
    attribute :correspondence_address, :string, public?: true
    attribute :is_vat_payer, :boolean, public?: true, default: true
    attribute :allowed_sender_emails, {:array, :string}, public?: true, default: []
    attribute :inbound_email_nickname, :string, public?: true, allow_nil?: false

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :owner, User do
      allow_nil? false
      attribute_writable? true
    end

    has_many :users, User
  end
end
