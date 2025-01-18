defmodule FirmowidWeb.BankSyncLive.Create do
  use FirmowidWeb, :live_view
  require Logger

  alias Firmowid.BankData

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        :available_institutions,
        BankData.get_available_institutions_for_country("pl")
      )
      |> assign(:requisition_link, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, url, socket) do
    # extract domain for redirecting when submitting an account
    # (makes it work for both localhost and production)
    socket = socket |> assign(:redirect_url, url |> String.split("?") |> List.first())

    requisition_id = params["ref"]

    if not is_nil(requisition_id) do
      error = params["error"]

      if not is_nil(error) do
        details = params["details"]

        Sentry.capture_message("Failed to connect to bank. Error: #{error} #{details}")

        Logger.info("Failed to connect to bank. Error: #{error} #{details}")

        LiveToast.send_toast(
          :error,
          "Połączenie z bankiem nie zostało utworzone. Spróbuj ponownie wkrótce."
        )

        socket =
          socket
          |> push_patch(to: ~p"/")

        {:noreply, socket}
      else
        current_user = socket.assigns.current_user
        organization_id = current_user.organization_id

        # check and confirm requisition passed by query param
        with {:ok, _} <-
               BankData.confirm_requisition(
                 requisition_id,
                 organization_id
               ) do
          {:noreply, redirect(socket, to: ~p"/")}
        else
          _ ->
            {:noreply, push_patch(socket, to: ~p"/settings/bank-sync/create")}
        end
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

    {:noreply, socket}
  end
end
