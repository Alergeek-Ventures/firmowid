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
    table "users"
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

    # ── Public attributes (used via Ash relationships) ───────────────
    attribute :name, :string, public?: true
    attribute :email, :string, public?: true, allow_nil?: false

    attribute :role, :atom,
      public?: true,
      constraints: [one_of: [:employee, :admin]],
      default: :employee

    attribute :avatar_blob_id, :uuid, public?: true

    # ── Private attributes (exist in table, not exposed via Ash reads) ─
    # These are only accessed through the legacy Firmowid.Accounts.User
    # Ecto schema. They remain defined here so the Ecto schema backing
    # this resource stays in sync with the database, but are not exposed
    # through Ash relationship loads.
    attribute :system_role, :atom,
      constraints: [one_of: [:user, :superuser]],
      default: :user

    attribute :employment_date, :date
    attribute :confirmed_at, :utc_datetime

    attribute :provider, :string, default: "password", allow_nil?: false
    attribute :provider_id, :string
    attribute :google_provider_id, :string

    attribute :phone, :string
    attribute :slack_url, :string
    attribute :slack_id, :string
    attribute :bank_account_number, :string
    attribute :birthday, :date
    attribute :position, :string
    attribute :student_status_until, :date
    attribute :marketing_consent, :boolean, default: false, allow_nil?: false

    attribute :employment_contract_type, :atom,
      constraints: [one_of: [:umowa_o_prace, :umowa_zlecenie, :umowa_o_dzielo, :b2b]]

    attribute :correspondence_street, :string
    attribute :correspondence_city, :string
    attribute :correspondence_code, :string
    attribute :residence_street, :string
    attribute :residence_city, :string
    attribute :residence_code, :string

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? true
      attribute_writable? true
    end
  end
end
