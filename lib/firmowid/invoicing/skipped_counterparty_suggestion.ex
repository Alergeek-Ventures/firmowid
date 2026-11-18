defmodule Firmowid.Invoicing.SkippedCounterpartySuggestion do
  @moduledoc """
  A buyer of issued invoices that an admin skipped on the "New counterparties" list.

  Keyed by the buyer group of `CounterpartyDetection`, so the buyer stays skipped as
  further invoices arrive. A skipped buyer no longer counts as waiting, but can still
  be added to the counterparties; adding it removes the record.
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
    table "skipped_counterparty_suggestions"
    repo Firmowid.Repo
  end

  actions do
    defaults [:read]

    create :skip do
      description "Skips a buyer group; skipping it again keeps the first date."
      accept [:group_key]

      change set_attribute(:skipped_on, &Date.utc_today/0)

      upsert? true
      upsert_identity :unique_group_key
      upsert_fields []
    end

    destroy :unskip do
      description "Removes the skip of a buyer group, once it is added to the counterparties."
      primary? true
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
    attribute :skipped_on, :date, allow_nil?: false, public?: true

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
