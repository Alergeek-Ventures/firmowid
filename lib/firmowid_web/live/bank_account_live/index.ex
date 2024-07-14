defmodule FirmowidWeb.BankAccountLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Finances
  alias Firmowid.Finances.BankAccount

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :bank_accounts, Finances.list_bank_accounts())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Bank account")
    |> assign(:bank_account, Finances.get_bank_account!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Bank account")
    |> assign(:bank_account, %BankAccount{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Bank accounts")
    |> assign(:bank_account, nil)
  end

  @impl true
  def handle_info({FirmowidWeb.BankAccountLive.FormComponent, {:saved, bank_account}}, socket) do
    {:noreply, stream_insert(socket, :bank_accounts, bank_account)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    bank_account = Finances.get_bank_account!(id)
    {:ok, _} = Finances.delete_bank_account(bank_account)

    {:noreply, stream_delete(socket, :bank_accounts, bank_account)}
  end
end
