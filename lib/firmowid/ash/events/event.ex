# credo:disable-for-this-file AshCredo.Check.Design.MissingTimestamps
# AshEvents.EventLog injects the `:id` primary key via extension transformer.
defmodule Firmowid.Ash.Events.Event do
  @moduledoc """
  Centralized event log resource for AshEvents.

  Stores action events for resources that opt into event tracking.
  Currently used by BankAccount to derive sync status (broken?, has_successful_sync?)
  without querying Oban jobs directly.

  This resource uses AshEvents for derivation only — not for replay.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Events,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshEvents.EventLog]

  postgres do
    table "ash_events"
    repo Firmowid.Repo
  end

  event_log do
    primary_key_type Ash.Type.UUIDv7
    record_id_type :uuid
    public_fields [:id, :record_id, :resource, :action, :occurred_at, :metadata]
  end

  actions do
    defaults [:read]

    read :latest_successful_sync do
      description "Read successful sync events for event-log lookups."

      argument :organization_id, :uuid, allow_nil?: false
      argument :record_id, :uuid, allow_nil?: false
      argument :resource, :atom, allow_nil?: false

      filter expr(
               action == :sync_from_gocardless and
                 resource == ^arg(:resource) and
                 record_id == ^arg(:record_id) and
                 organization_id == ^arg(:organization_id)
             )

      prepare build(sort: [occurred_at: :desc], limit: 1)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    bypass {Firmowid.Ash.Checks.SystemActorRole, roles: [:bank_sync]} do
      authorize_if action(:latest_successful_sync)
    end

    # AshEvents writes events internally — they need bypass too
    # System actors: no read access (internal event log)
    policy Firmowid.Ash.Checks.IsSystemActor do
      forbid_if always()
    end

    # Only admins can read events
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    attribute :organization_id, :uuid, allow_nil?: false
  end
end
