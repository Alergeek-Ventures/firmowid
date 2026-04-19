defmodule Firmowid.Ash.Events.TypedEvent do
  @moduledoc """
  Typed embedded representation of a persisted Ash event.

  It keeps the event row identifiers and timestamps, while exposing a typed
  payload union for downstream pattern matching.
  """

  use Ash.Resource,
    data_layer: :embedded,
    embed_nil_values?: false

  alias Firmowid.Ash.Events.EventPayload

  actions do
    defaults create: [:event_id, :record_id, :occurred_at, :resource, :action, :payload]
  end

  attributes do
    attribute :event_id, :uuid, allow_nil?: false, public?: true
    attribute :record_id, :uuid, allow_nil?: false, public?: true
    attribute :occurred_at, :utc_datetime_usec, allow_nil?: false, public?: true

    attribute :resource, :atom, allow_nil?: false, public?: true
    attribute :action, :atom, allow_nil?: false, public?: true
    attribute :payload, EventPayload, allow_nil?: false, public?: true
  end
end
