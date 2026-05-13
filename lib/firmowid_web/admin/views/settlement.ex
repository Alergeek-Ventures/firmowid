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
  alias FirmowidWeb.Billing.Utilities.MonthContext

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Rozliczenie")
     |> assign(:organizations, [])
     |> assign(:organization_options, [])
     |> assign(:selected_org, nil)
     |> assign(:selected_month, nil)
     |> assign(:selected_snapshot, nil)
     |> assign(:available_months, [])
     |> assign(:month_options, [])
     |> assign(:worksheet, nil)
     |> assign(:status, nil)
     |> assign(:pending_billing_plan, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    organizations = list_organizations(socket.assigns.current_user)

    case load_page(socket, organizations, params) do
      {:patch, to} ->
        {:noreply, push_patch(socket, to: to)}

      {:ok, socket} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("change-organization", %{"org_id" => org_id}, socket) do
    organizations = socket.assigns.organizations
    current_month = current_month()
    selected_org = find_selected_org(organizations, org_id) || List.first(organizations)

    target_month =
      case selected_org do
        nil ->
          current_month

        org ->
          resolve_month_for_org(socket, org.id, socket.assigns.selected_month || current_month)
      end

    {:noreply, push_patch(socket, to: build_path(selected_org && selected_org.id, target_month))}
  end

  def handle_event("change-month", %{"month" => month}, socket) do
    {:noreply,
     push_patch(
       socket,
       to:
         build_path(
           socket.assigns.selected_org && socket.assigns.selected_org.id,
           parse_month(month) || current_month()
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

      organizations = list_organizations(socket.assigns.current_user)

      {:ok, reloaded_socket} =
        load_page(socket, organizations, %{
          "org_id" => selected_org.id,
          "month" => Date.to_iso8601(socket.assigns.selected_month)
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
    <div class="mx-auto flex w-full max-w-5xl flex-col gap-8 px-6 py-8 lg:px-8">
      <SettlementComponents.page_header selected_org={@selected_org} status={@status} />

      <%= if @selected_org do %>
        <SettlementComponents.organization_panel
          selected_org={@selected_org}
          selected_month={@selected_month}
          organization_options={@organization_options}
          month_options={@month_options}
          pending_billing_plan={@pending_billing_plan}
        />

        <SettlementComponents.worksheet_panel
          selected_month={@selected_month}
          status={@status}
          worksheet={@worksheet}
        />
      <% else %>
        <SettlementComponents.empty_state />
      <% end %>
    </div>
    """
  end

  defp load_page(socket, organizations, params) do
    current_month = current_month()

    case organizations do
      [] ->
        {:ok,
         socket
         |> assign(:organizations, [])
         |> assign(:organization_options, [])
         |> assign(:selected_org, nil)
         |> assign(:selected_month, nil)
         |> assign(:selected_snapshot, nil)
         |> assign(:available_months, [])
         |> assign(:month_options, [])
         |> assign(:worksheet, nil)
         |> assign(:status, nil)
         |> assign(:pending_billing_plan, nil)}

      _organizations ->
        selected_org =
          find_selected_org(organizations, params["org_id"]) || List.first(organizations)

        snapshots = MonthContext.list_snapshots(selected_org.id, socket.assigns.current_user)
        available_months = available_months(snapshots, current_month)
        selected_month = resolve_selected_month(params["month"], available_months, current_month)

        canonical_path = build_path(selected_org.id, selected_month)

        if params["org_id"] != selected_org.id or
             params["month"] != Date.to_iso8601(selected_month) do
          {:patch, canonical_path}
        else
          billing_context =
            MonthContext.load(selected_org, selected_month, socket.assigns.current_user,
              current_month: current_month,
              snapshots: snapshots
            )

          {:ok,
           socket
           |> assign(:organizations, organizations)
           |> assign(:organization_options, organization_options(organizations))
           |> assign(:selected_org, selected_org)
           |> assign(:selected_month, billing_context.selected_month)
           |> assign(:selected_snapshot, billing_context.selected_snapshot)
           |> assign(:available_months, available_months)
           |> assign(:month_options, month_options(available_months))
           |> assign(:worksheet, billing_context.worksheet)
           |> assign(:status, billing_context.status)
           |> assign(:pending_billing_plan, Atom.to_string(selected_org.billing_plan))}
        end
    end
  end

  defp list_organizations(current_user) do
    Organization
    |> Ash.Query.sort(name: :asc)
    |> Ash.Query.load(owner: [])
    |> Ash.read!(actor: current_user)
  end

  defp available_months(snapshots, current_month) do
    snapshots
    |> Enum.map(& &1.month)
    |> Kernel.++([current_month])
    |> Enum.uniq()
    |> Enum.sort(&Date.after?(&1, &2))
  end

  defp organization_options(organizations) do
    Enum.map(organizations, fn organization ->
      {"#{organization.name} — #{organization.nip}", organization.id}
    end)
  end

  defp month_options(months) do
    Enum.map(months, fn month ->
      {Calendar.strftime(month, "%m.%Y"), Date.to_iso8601(month)}
    end)
  end

  defp find_selected_org(organizations, org_id) when is_binary(org_id) do
    Enum.find(organizations, &(&1.id == org_id))
  end

  defp find_selected_org(_organizations, _org_id), do: nil

  defp resolve_selected_month(month_param, available_months, current_month) do
    parsed_month = parse_month(month_param) || current_month

    if Enum.any?(available_months, &(Date.compare(&1, parsed_month) == :eq)) do
      parsed_month
    else
      current_month
    end
  end

  defp resolve_month_for_org(socket, org_id, fallback_month) do
    snapshots = MonthContext.list_snapshots(org_id, socket.assigns.current_user)
    available_months = available_months(snapshots, current_month())

    if Enum.any?(available_months, &(Date.compare(&1, fallback_month) == :eq)) do
      fallback_month
    else
      current_month()
    end
  end

  defp build_path(nil, _month), do: ~p"/admin/rozliczenie"

  defp build_path(org_id, month) do
    ~p"/admin/rozliczenie?#{%{org_id: org_id, month: Date.to_iso8601(month)}}"
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
