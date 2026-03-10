defmodule FirmowidWeb.AnalysisLive.Dashboard do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Analysis

  @impl true
  def mount(_params, _session, socket) do
    Bodyguard.permit!(Analysis, :read, socket.assigns.current_user)

    active_months =
      Analysis.get_months_with_entries() ++
        [Date.utc_today()]

    socket =
      socket
      |> assign(:active_months, active_months)
      |> assign(:expanded_section, :income)

    {:ok, assign(socket, page_title: "Analiza finansowa")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    month =
      case Map.get(params, "month") do
        nil -> Date.beginning_of_month(Date.utc_today())
        date_string -> Date.from_iso8601!(date_string)
      end

    socket =
      socket
      |> assign(:params, %{month: month})
      |> assign(:expanded_section, :income)
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    {:noreply, push_patch(socket, to: ~p"/analiza?month=#{month}")}
  end

  @impl true
  def handle_event("toggle-section", %{"section" => section}, socket) do
    section = String.to_existing_atom(section)
    current = socket.assigns.expanded_section

    expanded =
      case section do
        ^current -> nil
        other -> other
      end

    {:noreply, assign(socket, :expanded_section, expanded)}
  end

  defp entries_for_section(%{expanded_section: :income} = assigns) do
    assigns.sales_invoices ++
      Enum.filter(assigns.transactions, &Decimal.positive?(&1.transaction_amount))
  end

  defp entries_for_section(%{expanded_section: :expenses} = assigns) do
    assigns.cost_invoices ++
      Enum.filter(assigns.transactions, &Decimal.negative?(&1.transaction_amount))
  end

  defp entries_for_section(_assigns), do: []

  defp load_data(socket) do
    month = socket.assigns.params.month
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    totals = Analysis.get_organization_totals(date_range_from, date_range_to, nil)

    socket
    |> assign(:total_income, totals.total_income)
    |> assign(:total_expenses, totals.total_expenses)
    |> assign(:net_profit, totals.net_profit)
    |> assign(:transactions, totals.transactions)
    |> assign(:sales_invoices, totals.sales_invoices)
    |> assign(:cost_invoices, totals.cost_invoices)
  end
end
