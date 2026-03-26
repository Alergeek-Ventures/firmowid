defmodule Firmowid.Ash.Core.Counterparty do
  @moduledoc """
  Read-only Ash wrapper for the `counterparties` table.

  Attribute multitenancy via `organization_id`. Writes still go through
  `Firmowid.SalesInvoices` context during migration.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table("counterparties")
    repo(Firmowid.Repo)
    migrate?(false)
  end

  multitenancy do
    strategy(:attribute)
    attribute(:organization_id)
  end

  attributes do
    uuid_v7_primary_key(:id)

    attribute(:type, :atom, public?: true, constraints: [one_of: [:individual, :company]], default: :company)
    attribute(:tax_id, :string, public?: true)
    attribute(:full_name, :string, public?: true)
    attribute(:given_name, :string, public?: true)
    attribute(:surname, :string, public?: true)
    attribute(:pesel, :string, public?: true)
    attribute(:display_name, :string, public?: true)
    attribute(:address, :string, public?: true)
    attribute(:country, :string, public?: true)
    attribute(:is_different_mail_address, :boolean, public?: true, default: false)
    attribute(:mail_address, :string, public?: true)
    attribute(:mail_country, :string, public?: true)
    attribute(:email, :string, public?: true)
    attribute(:phone, :string, public?: true)
    attribute(:description, :string, public?: true)

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil?(false)
    end
  end

  actions do
    defaults([:read])
  end
end
