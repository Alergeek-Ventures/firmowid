defmodule FirmowidWeb.Core.PubSubDebounce do
  @moduledoc """
  Debounces PubSub-triggered refetches in LiveViews.

  When a resource publishes many notifications in a short window (e.g. bulk
  bank sync), the LiveView only needs to refetch once after the storm settles.

  ## Usage

      import FirmowidWeb.Core.PubSubDebounce

      # In handle_info for incoming notifications:
      def handle_info(%Ash.Notifier.Notification{resource: Transaction}, socket) do
        {:noreply, debounce_refetch(socket, :transactions)}
      end

      # Handle the debounced refetch:
      def handle_info({:debounced_refetch, :transactions}, socket) do
        {:noreply, refetch_transactions(socket)}
      end

  The default delay is 300ms. Successive notifications reset the timer,
  so the refetch fires once 300ms after the *last* notification.
  """
  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView.Socket

  @default_delay_ms 300

  @doc """
  Schedules a debounced refetch for the given `key`.

  If a timer is already pending for this key, it is cancelled and a new one
  is started. When the timer fires, it sends `{:debounced_refetch, key}` to
  the LiveView process.
  """
  # sobelow_skip ["DOS.BinToAtom"]
  # key is always a compile-time atom from our own code (e.g. :transactions),
  # never user input. The atom set is bounded by the number of PubSub topics.
  @spec debounce_refetch(Socket.t(), atom(), non_neg_integer()) ::
          Socket.t()
  def debounce_refetch(socket, key, delay \\ @default_delay_ms) do
    timer_key = :"#{key}_debounce_timer"

    if timer = socket.assigns[timer_key] do
      Process.cancel_timer(timer)
    end

    timer = Process.send_after(self(), {:debounced_refetch, key}, delay)
    assign(socket, timer_key, timer)
  end
end
