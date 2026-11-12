defmodule FirmowidWeb.Inbox.Hooks.LiveQueue do
  @moduledoc """
  Keeps the inbox and the sidebar's inbox badge current while the page is open.

  Pages of members whose organization has the `inbox` flag subscribe to
  `Firmowid.Core.Notifiers.InboxChanged`. Changes arriving close together, like
  a batch of imported invoices, are gathered into one `:inbox_refresh` shortly
  after the first; the sidebar then reloads its badge, and the inbox page
  receives the message itself to reload its queue.
  """

  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]

  alias Firmowid.Core.Notifiers.InboxChanged
  alias FirmowidWeb.Inbox.Components.SidebarNav
  alias FirmowidWeb.Inbox.Views.Index
  alias Phoenix.LiveView

  # Long enough to gather a burst of changes, short enough to feel immediate.
  @gather_ms 500

  # Overdue invoices and expiring connections change with time alone, without
  # any write to tell about it.
  @tick_ms to_timeout(minute: 5)

  @doc false
  @spec on_mount(:default, map(), map(), LiveView.Socket.t()) :: {:cont, LiveView.Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_user] do
      %{member: %{organization_id: organization_id}} when is_binary(organization_id) ->
        if LiveView.connected?(socket) and flag_enabled?(:inbox, socket.assigns) do
          InboxChanged.subscribe(organization_id)
          Process.send_after(self(), :inbox_tick, @tick_ms)
          {:cont, LiveView.attach_hook(socket, :inbox_live_queue, :handle_info, &handle_info/2)}
        else
          {:cont, socket}
        end

      _no_member ->
        {:cont, socket}
    end
  end

  defp handle_info({:inbox_changed, kind}, socket) do
    pending = socket.private[:inbox_changes] || MapSet.new()
    if pending == MapSet.new(), do: Process.send_after(self(), :inbox_refresh, @gather_ms)
    {:halt, LiveView.put_private(socket, :inbox_changes, MapSet.put(pending, kind))}
  end

  defp handle_info(:inbox_refresh, socket) do
    kinds = socket.private[:inbox_changes] || MapSet.new()

    # The badge counts what needs attention and shows whether the member's own
    # session runs; invoices and contracts do not change it.
    if MapSet.member?(kinds, :attention) or MapSet.member?(kinds, :presence) do
      LiveView.send_update(SidebarNav, id: SidebarNav.id(), refresh: true)
    end

    socket = LiveView.put_private(socket, :inbox_changes, MapSet.new())
    if socket.view == Index, do: {:cont, socket}, else: {:halt, socket}
  end

  defp handle_info(:inbox_tick, socket) do
    Process.send_after(self(), :inbox_tick, @tick_ms)
    LiveView.send_update(SidebarNav, id: SidebarNav.id(), refresh: true)
    if socket.view == Index, do: {:cont, socket}, else: {:halt, socket}
  end

  defp handle_info(_message, socket), do: {:cont, socket}
end
