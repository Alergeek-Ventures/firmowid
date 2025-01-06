defmodule FirmowidWeb.BankSyncLive.Index do
  alias Firmowid.Finances
  use FirmowidWeb, :live_view

  alias Firmowid.BankData

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        :bank_accounts,
        Finances.list_bank_accounts()
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    socket =
      socket
      |> assign(:page_title, "Synchronizacja konta bankowego z Firmowidem")

    {:noreply, socket}
  end

  @impl true
  def handle_event("sync", %{"bank-account-id" => bank_account_id}, socket) do
    BankData.sync_bank_account(bank_account_id)
    LiveToast.send_toast(:info, "Zsynchronizowano konto bankowe.")

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"bank-account-id" => bank_account_id}, socket) do
    Finances.delete_bank_account(bank_account_id)

    socket =
      socket
      |> assign(
        :bank_accounts,
        Finances.list_bank_accounts()
      )

    {:noreply, socket}
  end
end
