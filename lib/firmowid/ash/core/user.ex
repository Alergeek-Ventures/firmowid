defmodule Firmowid.Ash.Core.User do
  @moduledoc """
  Read-only Ash wrapper for the `users` table.

  No multitenancy — users are the identity layer that sits above tenancy.
  `organization_id` is nullable (onboarding state).
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table("users")
    repo(Firmowid.Repo)
    migrate?(false)
  end

  attributes do
    uuid_v7_primary_key(:id)

    attribute(:name, :string, public?: true)
    attribute(:email, :string, public?: true, allow_nil?: false)
    attribute(:role, :atom, public?: true, constraints: [one_of: [:employee, :admin]], default: :employee)
    attribute(:system_role, :atom, public?: true, constraints: [one_of: [:user, :superuser]], default: :user)
    attribute(:employment_date, :date, public?: true)
    attribute(:confirmed_at, :utc_datetime, public?: true)

    attribute(:provider, :string, public?: true, default: "password", allow_nil?: false)
    attribute(:provider_id, :string, public?: true)
    attribute(:google_provider_id, :string, public?: true)

    attribute(:phone, :string, public?: true)
    attribute(:slack_url, :string, public?: true)
    attribute(:slack_id, :string, public?: true)
    attribute(:bank_account_number, :string, public?: true)
    attribute(:birthday, :date, public?: true)
    attribute(:position, :string, public?: true)
    attribute(:student_status_until, :date, public?: true)
    attribute(:marketing_consent, :boolean, public?: true, default: false, allow_nil?: false)

    attribute(:employment_contract_type, :atom,
      public?: true,
      constraints: [one_of: [:umowa_o_prace, :umowa_zlecenie, :umowa_o_dzielo, :b2b]]
    )

    attribute(:correspondence_street, :string, public?: true)
    attribute(:correspondence_city, :string, public?: true)
    attribute(:correspondence_code, :string, public?: true)
    attribute(:residence_street, :string, public?: true)
    attribute(:residence_city, :string, public?: true)
    attribute(:residence_code, :string, public?: true)

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil?(true)
      attribute_writable?(true)
    end
  end

  actions do
    defaults([:read])
  end
end
