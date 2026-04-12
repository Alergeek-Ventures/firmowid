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
    public_fields [:id, :record_id, :resource, :action, :occurred_at]
  end

  actions do
    defaults [:read]
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
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
end
