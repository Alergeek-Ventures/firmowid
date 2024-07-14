defmodule FirmowidWeb.BankAccountLive.Show do
  use FirmowidWeb, :live_view

  alias Firmowid.Finances

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:bank_account, Finances.get_bank_account!(id))}
  end

  defp page_title(:show), do: "Show Bank account"
  defp page_title(:edit), do: "Edit Bank account"
end
