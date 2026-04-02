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
    extensions: [AshEvents.EventLog]

  postgres do
    table "ash_events"
    repo Firmowid.Repo
    migrate? false
  end

  event_log do
    primary_key_type Ash.Type.UUIDv7
    record_id_type :uuid
    public_fields [:id, :record_id, :resource, :action, :occurred_at]
  end

  actions do
    defaults [:read]
  end
end
