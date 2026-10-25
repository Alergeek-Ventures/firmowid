defmodule Firmowid.Ash.Assistant.Notifier do
  @moduledoc "Broadcasts assistant revisions after their database transaction commits."
  use Ash.Notifier

  alias Firmowid.Ash.Assistant

  @impl true
  def notify(%{data: %{id: id}}) do
    Phoenix.PubSub.broadcast(Firmowid.PubSub, Assistant.topic(id), {:assistant_updated, id})
  end
end
