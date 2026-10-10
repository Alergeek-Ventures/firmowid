defmodule FirmowidWeb.Core.PubSubDebounceTest do
  @moduledoc "Tests scheduling and replacement of pending PubSub refetches."
  use ExUnit.Case, async: true

  alias FirmowidWeb.Core.PubSubDebounce
  alias Phoenix.LiveView.Socket

  test "replaces a pending timer and delivers the refetch message" do
    socket = %Socket{assigns: %{__changed__: %{}}}
    socket = PubSubDebounce.debounce_refetch(socket, :invoicing_entries, 60_000)
    pending_timer = socket.assigns.invoicing_entries_debounce_timer

    assert is_integer(Process.read_timer(pending_timer))

    socket = PubSubDebounce.debounce_refetch(socket, :invoicing_entries, 0)

    refute socket.assigns.invoicing_entries_debounce_timer == pending_timer
    refute Process.read_timer(pending_timer)
    assert_receive {:debounced_refetch, :invoicing_entries}
  end
end
