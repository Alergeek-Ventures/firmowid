defmodule FirmowidWeb.AnalysisLive.Dashboard do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Analysis
  alias Firmowid.Invoicing

  @impl true
  def mount(_params, _session, socket) do
    active_months =
      Invoicing.get_all_months_with_invoicing_entries() ++
        [Date.utc_today()]

    socket = assign(socket, :active_months, active_months)

    {:ok, assign(socket, page_title: "Analiza finansowa")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    month =
      case Map.get(params, "month") do
        nil -> Date.beginning_of_month(Date.utc_today())
        date_string -> Date.from_iso8601!(date_string)
      end

    tag_id = Map.get(params, "tag_id", :all)

    socket =
      socket
      |> assign(:params, %{month: month, tag_id: tag_id})
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    {:noreply, update_param(socket, :month, month)}
  end

  @impl true
  def handle_event("change-tag", %{"tag_id" => tag_id}, socket) do
    {:noreply, update_param(socket, :tag_id, tag_id)}
  end

  defp update_param(socket, key, value) do
    params = socket.assigns.params |> Map.put(key, value) |> dbg()

    url_params = %{
      month: params.month,
      tag_id: params.tag_id
    }

    socket = push_patch(socket, to: ~p"/analiza?month=#{url_params.month}&tag_id=#{url_params.tag_id}")

    socket
  end

  defp load_data(socket) do
    month = socket.assigns.params.month
    tag_id = socket.assigns.params.tag_id
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    totals = Analysis.get_organization_totals(date_range_from, date_range_to, tag_id)

    socket
    |> assign(:total_income, totals.total_income)
    |> assign(:total_expenses, totals.total_expenses)
    |> assign(:net_profit, totals.net_profit)
    |> assign(:transactions, totals.transactions)
    |> assign(:sales_invoices, totals.sales_invoices)
    |> assign(:cost_invoices, totals.cost_invoices)
    |> assign(:tags, Analysis.list_tags())
  end
end
