defmodule FirmowidWeb.BankSync.Views.Create do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.Billing.Components.Billing

  alias Firmowid.Analytics
  alias Firmowid.Ash.Billing.Limits, as: AshLimits
  alias Firmowid.BankData
  alias Firmowid.BankData.Worker, as: BankDataWorker

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(BankData, :create_requisition, socket.assigns.current_user)

    # Check billing limits for bank connections
    bank_connections_limit_check =
      AshLimits.check!(socket.assigns.current_org.id, :bank_connections, scope: socket.assigns.ash_scope)

    available_institutions =
      case BankData.get_available_institutions_for_country("pl") do
        {:ok, institutions} -> institutions
        {:error, _} -> []
      end

    socket =
      socket
      |> assign(:available_institutions, available_institutions)
      |> assign(:requisition_link, nil)
      |> assign(:bank_connections_limit_check, bank_connections_limit_check)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, url, socket) do
    Bodyguard.permit!(BankData, :create_requisition, socket.assigns.current_user)
    # extract domain for redirecting when submitting an account
    # (makes it work for both localhost and production)
    socket = assign(socket, :redirect_url, url |> String.split("?") |> List.first())

    requisition_id = params["ref"]

    if is_nil(requisition_id) do
      {:noreply, socket}

      # Always schedule asynchronous requisition resolution in the background
    else
      current_user = socket.assigns.current_user
      organization_id = current_user.organization_id

      %{
        name: "check_requisition_status",
        requisition_id: requisition_id,
        organization_id: organization_id
      }
      |> BankDataWorker.new()
      |> Firmowid.Oban.insert!()

      error = params["error"]

      if is_nil(error) do
        {:noreply, push_navigate(socket, to: ~p"/fakturowanie")}
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
    Bodyguard.permit!(BankData, :create_requisition, user)

    # it comes as as string
    transaction_total_days = String.to_integer(transaction_total_days)

    {:ok, link} =
      BankData.create_requisition(
        institution_id,
        transaction_total_days,
        organization_id,
        socket.assigns.redirect_url
      )

    Analytics.track_event("bank_institution_select", user, %{
      institution_id: institution_id
    })

    {:noreply, assign(socket, :requisition_link, link)}
  end
end
