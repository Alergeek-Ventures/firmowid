defmodule Firmowid.Core.RegisteredCompany do
  @moduledoc """
  Public register data of a company, shared by all organizations.

  Caches what the public registers know about a NIP. A NIP the registers do not
  know is stored without a `pkd` and looked up again after 30 days, any other
  after a year. `pkd` is the predominant activity, e.g. `"69.20.Z"`.
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

    action :look_up, :map do
      description """
      Looks up a company by NIP for someone creating an organization: name, address
      and VAT status from the VAT white list, and the predominant activity (PKD) with
      the industry it suggests. Returns nil when the white list does not know the NIP.
      """

      allow_nil? true

      argument :nip, :string, allow_nil?: false
      run Firmowid.Core.RegisteredCompany.Actions.LookUp
    end
  end

  policies do
    # Public register data: members who read the analysis see their counterparties' activity.
    policy action(:by_nips) do
      authorize_if {SystemActorRole, roles: [:analysis_classifier, :company_lookup]}
      authorize_if {AtLeastRole, role: :invoicing}
    end

    policy action(:register) do
      authorize_if {SystemActorRole, roles: [:analysis_classifier, :company_lookup]}
    end

    # Anyone signed in may look up the company they are about to create.
    policy action(:look_up) do
      authorize_if actor_present()
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
