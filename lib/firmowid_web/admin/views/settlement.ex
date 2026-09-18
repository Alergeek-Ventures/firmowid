defmodule FirmowidWeb.Admin.Views.Settlement do
  @moduledoc """
  Superuser billing worksheet for one organization and one month.
  """

  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Billing.Month
  alias Firmowid.Ash.Billing.PlanCatalog
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.Organization
  alias FirmowidWeb.Admin.Components.SettlementComponents
  alias FirmowidWeb.Admin.Utilities.Navigation
  alias FirmowidWeb.Billing.Utilities.MonthContext

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Rozliczenie")
     |> assign(:selected_org, nil)
     |> assign(:selected_month, nil)
     |> assign(:selected_snapshot, nil)
     |> assign(:available_months, [])
     |> assign(:worksheet, nil)
     |> assign(:status, nil)
     |> assign(:pending_billing_plan, nil)}
  end

  @impl true
  def handle_params(%{"org_id" => org_id} = params, _uri, socket) do
    case Core.get_organization(org_id,
           actor: socket.assigns.current_user,
           load: [:on_trial?, owner: []]
         ) do
      {:ok, selected_org} ->
        case load_page(socket, selected_org, params) do
          {:patch, to} ->
            {:noreply, push_patch(socket, to: to)}

          {:ok, socket} ->
            {:noreply, socket}
        end

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Nie znaleziono organizacji.")
         |> push_navigate(to: Navigation.settlements_path())}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, push_navigate(socket, to: Navigation.settlements_path())}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    {:noreply,
     push_patch(
       socket,
       to:
         Navigation.settlement_path(
           socket.assigns.selected_org.id,
           %{"miesiac" => parse_month(month) || current_month()}
         )
     )}
  end

  def handle_event("change-current-plan", %{"plan" => %{"billing_plan" => billing_plan}}, socket) do
    {:noreply, assign(socket, :pending_billing_plan, billing_plan)}
  end

  def handle_event("save-current-plan", %{"plan" => %{"billing_plan" => billing_plan}}, socket) do
    with {:ok, plan} <- cast_plan(billing_plan),
         %Organization{} = selected_org <- socket.assigns.selected_org,
         {:ok, _updated} <-
           Core.update_organization_billing_plan(
             selected_org,
             %{billing_plan: plan},
             actor: socket.assigns.current_user
           ) do
      LiveToast.send_toast(:success, "Plan organizacji został zapisany.")

      reloaded_org =
        Core.get_organization!(selected_org.id,
          actor: socket.assigns.current_user,
          load: [:on_trial?, owner: []]
        )

      {:ok, reloaded_socket} =
        load_page(socket, reloaded_org, %{
          "miesiac" => Date.to_iso8601(socket.assigns.selected_month)
        })

      {:noreply, reloaded_socket}
    else
      :error ->
        LiveToast.send_toast(:error, "Nieprawidłowy plan.")
        {:noreply, socket}

      {:error, error} ->
        LiveToast.send_toast(:error, Exception.message(error))
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex w-full max-w-7xl flex-col gap-8 py-8">
      <SettlementComponents.page_header
        selected_month={@selected_month}
        active_months={@available_months}
      />

      <%= if @selected_org do %>
        <SettlementComponents.organization_panel
          selected_org={@selected_org}
          status={@status}
          pending_billing_plan={@pending_billing_plan}
        />

        <SettlementComponents.worksheet_panel
          selected_month={@selected_month}
          status={@status}
          worksheet={@worksheet}
          selected_org={@selected_org}
        />
      <% else %>
        <SettlementComponents.empty_state />
      <% end %>
    </div>
    """
  end

  defp load_page(socket, selected_org, params) do
    current_month = current_month()

    snapshots = MonthContext.list_snapshots(selected_org.id, socket.assigns.current_user)
    available_months = available_months(snapshots, current_month)
    selected_month = resolve_selected_month(params["miesiac"], available_months, current_month)

    canonical_path = Navigation.settlement_path(selected_org.id, %{"miesiac" => selected_month})

    if params["miesiac"] == Date.to_iso8601(selected_month) do
      billing_context =
        MonthContext.load(selected_org, selected_month, socket.assigns.current_user,
          current_month: current_month,
          snapshots: snapshots
        )

      {:ok,
       socket
       |> assign(:selected_org, selected_org)
       |> assign(:selected_month, billing_context.selected_month)
       |> assign(:selected_snapshot, billing_context.selected_snapshot)
       |> assign(:available_months, available_months)
       |> assign(:worksheet, billing_context.worksheet)
       |> assign(:status, billing_context.status)
       |> assign(:pending_billing_plan, Atom.to_string(selected_org.billing_plan))}
    else
      {:patch, canonical_path}
    end
  end

  defp available_months(snapshots, current_month) do
    snapshots
    |> Enum.map(& &1.month)
    |> Kernel.++([current_month])
    |> Enum.uniq()
    |> Enum.sort(&Date.after?(&1, &2))
  end

  defp resolve_selected_month(month_param, available_months, current_month) do
    parsed_month = parse_month(month_param) || current_month

    if Enum.any?(available_months, &(Date.compare(&1, parsed_month) == :eq)) do
      parsed_month
    else
      current_month
    end
  end

  defp parse_month(nil), do: nil

  defp parse_month(month) do
    case Date.from_iso8601(month) do
      {:ok, parsed_month} -> Date.beginning_of_month(parsed_month)
      _ -> nil
    end
  end

  defp cast_plan(plan_param) when is_binary(plan_param) do
    case Enum.find(PlanCatalog.plans(), &(Atom.to_string(&1) == plan_param)) do
      nil -> :error
      plan -> {:ok, plan}
    end
  end

  defp cast_plan(_plan), do: :error

  defp current_month, do: Month.current()
end
