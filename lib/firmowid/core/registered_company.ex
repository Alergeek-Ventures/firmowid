defmodule Firmowid.Core.RegisteredCompany do
  @moduledoc """
  Public register data of a company, shared by all organizations.

  Caches what the GUS register knows about a NIP, so each NIP is looked up
  once. A NIP the register does not know is stored without a `pkd`, so it is
  never asked for again. `pkd` is the predominant activity, e.g. `"69.20.Z"`.
  """
  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Resource

  require Resource

  postgres do
    table "registered_companies"
    repo Firmowid.Repo
  end

  actions do
    read :by_nips do
      description "Reads the cached register data of the given NIPs."
      argument :nips, {:array, :string}, allow_nil?: false
      filter expr(nip in ^arg(:nips))
    end

    create :register do
      description "Stores the register data of a NIP, replacing an earlier lookup."
      accept [:nip, :regon, :name, :pkd, :pkd_name]
      upsert? true
      upsert_identity :unique_nip
      upsert_fields {:replace_all_except, [:id, :inserted_at]}
    end
  end

  policies do
    policy {Firmowid.Checks.SystemActorRole, roles: [:analysis_classifier]} do
      authorize_if action([:by_nips, :register])
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :nip, :string, allow_nil?: false, public?: true
    attribute :regon, :string, public?: true
    attribute :name, :string, public?: true
    attribute :pkd, :string, public?: true
    attribute :pkd_name, :string, public?: true

    Resource.firmowid_timestamps()
  end

  identities do
    identity :unique_nip, [:nip]
  end
end
