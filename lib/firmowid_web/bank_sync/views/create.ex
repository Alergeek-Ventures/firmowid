defmodule FirmowidWeb.BankSync.Views.Create do
  @moduledoc """
  LiveView for creating GoCardless bank connections.

  Uses Ash native code interfaces from Firmowid.Ash.Finances domain.
  The AshOban trigger on Requisition auto-schedules status polling.
  """
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Finances

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    # Use Ash native code interface for institutions
    available_institutions =
      case Finances.list_institutions("pl", actor: socket.assigns.current_user) do
        {:ok, institutions} -> institutions
        {:error, _} -> []
      end

    socket =
      socket
      |> assign(:available_institutions, available_institutions)
      |> assign(:requisition_link, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, url, socket) do
    # extract domain for redirecting when submitting an account
    # (makes it work for both localhost and production)
    socket = assign(socket, :redirect_url, url |> String.split("?") |> List.first())

    requisition_id = params["ref"]

    if is_nil(requisition_id) do
      {:noreply, socket}
    else
      # AshOban trigger auto-schedules status check when requisition is pending.
      # No manual worker insertion needed.
      error = params["error"]

      if is_nil(error) do
        {:noreply,
         socket
         |> LiveToast.put_toast(
           :success,
           "Konto bankowe zostało poprawnie połączone.",
           title: "Gotowe"
         )
         |> push_navigate(to: ~p"/ustawienia/konta-bankowe")}
      else
        details = params["details"]

        Logger.warning("Failed to connect to bank. Error: #{error} #{details}")

        {:noreply,
         socket
         |> LiveToast.put_toast(
           :error,
           "Będziemy kontynuować próby połączenia w Twoim imieniu.",
           title: "Połączenie z bankiem nie zostało utworzone w tym momencie."
         )
         |> push_patch(to: ~p"/fakturowanie")}
      end
    end
  end

  @impl true
  def handle_event(
        "institution_selected",
        %{"institution-id" => institution_id, "institution-transaction-total-days" => transaction_total_days},
        socket
      ) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    # it comes as as string
    transaction_total_days = String.to_integer(transaction_total_days)

    # Use Ash native code interface with authorization
    # The AshOban trigger auto-schedules status polling on create
    {:ok, link} =
      Finances.create_requisition(
        institution_id,
        transaction_total_days,
        socket.assigns.redirect_url,
        tenant: organization_id,
        actor: user,
        authorize?: true
      )

    {:noreply, assign(socket, :requisition_link, link)}
  end
end
