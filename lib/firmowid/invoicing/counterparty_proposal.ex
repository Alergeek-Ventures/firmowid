defmodule Firmowid.Invoicing.CounterpartyProposal do
  @moduledoc """
  Cleaned-up data proposed for a buyer of issued invoices that has no
  counterparty yet: a display name and tidy name and address fields.

  Generated once by a model and stored, so reviewing the buyers again does not
  repeat the inference. `source_hash` fingerprints the invoice and register data
  the proposal was made from; a different hash means the proposal is outdated.
  """
  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.ActorRole
  alias Firmowid.Resource

  require Resource

  postgres do
    table "counterparty_proposals"
    repo Firmowid.Repo
  end

  actions do
    read :by_group_keys do
      description "Reads the stored proposals of the given buyer groups."
      argument :group_keys, {:array, :string}, allow_nil?: false
      filter expr(group_key in ^arg(:group_keys))
    end

    create :record do
      description "Stores the proposal of a buyer group, replacing an earlier one."

      accept [
        :group_key,
        :source_hash,
        :display_name,
        :full_name,
        :given_name,
        :surname,
        :address
      ]

      upsert? true
      upsert_identity :unique_group_key
      upsert_fields {:replace_all_except, [:id, :inserted_at]}
    end
  end

  policies do
    bypass {ActorRole, role: :admin} do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :group_key, :string, allow_nil?: false, public?: true
    attribute :source_hash, :string, allow_nil?: false, public?: true
    attribute :display_name, :string, public?: true
    attribute :full_name, :string, public?: true
    attribute :given_name, :string, public?: true
    attribute :surname, :string, public?: true
    attribute :address, :string, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_group_key, [:organization_id, :group_key]
  end
end
