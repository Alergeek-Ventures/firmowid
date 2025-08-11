defmodule FirmowidWeb.BankSyncLive.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.BankData
  alias Firmowid.Finances

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Finances, :read_bank_accounts, socket.assigns.current_user)

    {:ok, assign(socket, :bank_accounts, Finances.list_bank_accounts())}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, :page_title, "Synchronizacja konta bankowego z Firmowidem")}
  end

  @impl true
  def handle_event("sync", %{"bank-account-id" => bank_account_id}, socket) do
    bank_account = Finances.get_bank_account!(bank_account_id)
    Bodyguard.permit!(Finances, :read_bank_account, socket.assigns.current_user, bank_account)

    BankData.sync_bank_account(bank_account_id)
    LiveToast.send_toast(:info, "Zsynchronizowano konto bankowe.")

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"bank-account-id" => bank_account_id}, socket) do
    bank_account = Finances.get_bank_account!(bank_account_id)
    Bodyguard.permit!(Finances, :delete_bank_account, socket.assigns.current_user, bank_account)
    Finances.delete_bank_account(bank_account_id)

    {:noreply, assign(socket, :bank_accounts, Finances.list_bank_accounts())}
  end
end
