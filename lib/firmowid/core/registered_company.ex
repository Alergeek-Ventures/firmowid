defmodule Firmowid.Core.RegisteredCompany do
  @moduledoc """
  Public register data of a company, shared by all organizations.

  Caches what the public registers know about a NIP, so each NIP is looked up
  once. A NIP the register does not know is stored without a `pkd`, so it is
  never asked for again. `pkd` is the predominant activity, e.g. `"69.20.Z"`.
  """
  use Ash.Resource,
    otp_app: :firmowid,
    domain: Firmowid.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Checks.SystemActorRole
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
    # Public register data: members who read the analysis see their counterparties' activity.
    policy action(:by_nips) do
      authorize_if {SystemActorRole, roles: [:analysis_classifier]}
      authorize_if {AtLeastRole, role: :invoicing}
    end

    policy action(:register) do
      authorize_if {SystemActorRole, roles: [:analysis_classifier]}
    end
  end

  @doc "Describes the company's predominant activity by its PKD code and name, nil when unknown."
  @spec activity(%__MODULE__{}) :: String.t() | nil
  def activity(%__MODULE__{pkd: pkd, pkd_name: name}) when is_binary(pkd), do: "#{pkd} #{name}"
  def activity(%__MODULE__{}), do: nil

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
