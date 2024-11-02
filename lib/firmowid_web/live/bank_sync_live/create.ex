defmodule FirmowidWeb.BankSyncLive.Create do
  use FirmowidWeb, :live_view

  alias Firmowid.BankData

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        :available_institutions,
        BankData.get_available_accounts_for_country("pl")
      )
      |> assign(:requisition_link, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, url, socket) do
    # save URL for BankData redirection
    socket = socket |> assign(:redirect_url, url |> String.split("?") |> List.first())

    current_user = socket.assigns.current_user
    organization_id = current_user.organization_id

    requisition_id = params["ref"]

    if not is_nil(requisition_id) do
      # check and confirm requisition passed by query param
      with {:ok, _} <-
             BankData.confirm_requisition(
               requisition_id,
               organization_id
             ),
           BankData.sync_requisition(requisition_id, organization_id) do
        {:noreply, redirect(socket, to: ~p"/")}
      else
        _ ->
          {:noreply, push_patch(socket, to: ~p"/settings/bank-sync/create")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "institution_selected",
        %{
          "institution-id" => institution_id,
          "institution-transaction-total-days" => transaction_total_days
        },
        socket
      ) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    # it comes as as string
    transaction_total_days = String.to_integer(transaction_total_days)

    {:ok, link} =
      BankData.create_requisition(
        institution_id,
        transaction_total_days,
        organization_id,
        socket.assigns.redirect_url
      )

    socket = assign(socket, :requisition_link, link)

    LiveToast.send_toast(
      :info,
      "Utworzono połączenie z bankiem. Potwierdz je, kilkając wyświetlony link."
    )

    {:noreply, socket}
  end
end
