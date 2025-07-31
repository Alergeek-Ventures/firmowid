defmodule FirmowidWeb.AnalysisLive.Dashboard do
  use FirmowidWeb, :live_view

  alias Firmowid.Analysis
  alias Firmowid.Invoicing

  @impl true
  def mount(_params, _session, socket) do
    active_months =
      Invoicing.get_all_months_with_invoicing_entries() ++
        [Date.utc_today()]

    socket =
      socket
      |> assign(:active_months, active_months)

    {:ok, assign(socket, page_title: "Analiza finansowa")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    month =
      case Map.get(params, "month") do
        nil -> Date.utc_today() |> Date.beginning_of_month()
        date_string -> Date.from_iso8601!(date_string)
      end

    # Get the default "całość" tag (show all data)
    calosci_tag = Analysis.get_calosci_tag()

    tag_id =
      case Map.get(params, "tag_id") do
        nil -> calosci_tag.id
        tag_id_string -> tag_id_string
      end

    socket =
      socket
      |> assign(:params, %{month: month, tag_id: tag_id})
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    month = month |> Date.from_iso8601!()

    {:noreply, update_param(socket, :month, month)}
  end

  @impl true
  def handle_event("change-tag", %{"tag_id" => tag_id}, socket) do
    {:noreply, update_param(socket, :tag_id, tag_id)}
  end

  defp update_param(socket, key, value) do
    params =
      socket.assigns.params
      |> Map.put(key, value)

    url_params = %{
      month: params.month |> Date.beginning_of_month() |> Date.to_iso8601(),
      tag_id: params.tag_id
    }

    socket =
      socket
      |> push_patch(to: ~p"/analiza?month=#{url_params.month}&tag_id=#{url_params.tag_id}")

    socket
  end

  defp load_data(socket) do
    # Ensure "całość" tag exists
    Analysis.ensure_calosci_tag()

    month = socket.assigns.params.month
    tag_id = socket.assigns.params.tag_id
    date_range_from = Date.beginning_of_month(month)
    date_range_to = Date.end_of_month(month)

    # Get organization totals for the selected month and tag
    totals = Analysis.get_organization_totals(date_range_from, date_range_to, tag_id)

    socket
    |> assign(:total_income, format_money(totals.total_income))
    |> assign(:total_expenses, format_money(totals.total_expenses))
    |> assign(:net_profit, format_money(totals.net_profit))
    |> assign(:net_profit_decimal, totals.net_profit)
    |> assign(:tags, Analysis.list_tags())
  end

  defp format_money(amount) do
    case Money.to_string(Money.new("PLN", amount)) do
      {:ok, formatted} -> formatted
      _ -> "0,00 zł"
    end
  end
end
