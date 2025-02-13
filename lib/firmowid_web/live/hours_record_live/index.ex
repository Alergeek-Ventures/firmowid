defmodule FirmowidWeb.HoursRecordLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Timetracker

  @impl true
  def mount(_params, _session, socket) do
    selected_date = Date.utc_today()
    active_months = Timetracker.get_months_with_sessions(socket.assigns.current_user.id)

    current_user = socket.assigns.current_user
    can_use_hours_records = current_user.name && current_user.employment_date

    socket =
      socket
      |> assign(:selected_date, selected_date)
      |> assign(:active_months, active_months)
      |> assign(:can_use_hours_records, can_use_hours_records)
      |> allow_upload(:hours_record,
        max_entries: 1,
        accept: ["application/pdf", "image/*"]
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    month =
      case Map.get(params, "month") do
        nil -> Date.utc_today() |> Date.beginning_of_month()
        date_string -> Date.from_iso8601!(date_string)
      end

    {:noreply, socket |> assign(selected_date: month) |> refetch_data()}
  end

  @impl true
  def handle_info({FirmowidWeb.HoursRecordLive.FormComponent, {:saved, hours_record}}, socket) do
    {:noreply, stream_insert(socket, :hours_records, hours_record)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    hours_record = Timetracker.get_hours_record!(id)
    {:ok, _} = Timetracker.delete_hours_record(hours_record)

    {:noreply, stream_delete(socket, :hours_records, hours_record)}
  end

  def handle_event("validate-upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("upload", _params, socket) do
    consume_uploaded_entries(socket, :hours_record, fn %{path: path}, entry ->
      case Timetracker.create_hours_record(
             %{
               user_id: socket.assigns.current_user.id,
               number_of_hours: socket.assigns.total_duration |> div(3600) |> round(),
               month: socket.assigns.selected_date.month,
               year: socket.assigns.selected_date.year
             },
             path,
             entry.client_name
           ) do
        {:error, error} ->
          LiveToast.send_toast(:error, "Wystąpił błąd podczas zapisywania pliku.")
          {:ok, {:error, error}}

        {:ok, hours_record} ->
          LiveToast.send_toast(:info, "Plik został zapisany.")

          {:ok, {:ok, hours_record}}
      end
    end)

    {:noreply, socket |> refetch_data()}
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    month = month |> Date.from_iso8601!()

    socket =
      socket
      |> assign(:selected_date, month)
      |> push_patch(to: ~p"/czasosledz/ewidencja?month=#{month |> Date.to_iso8601()}")

    {:noreply, socket}
  end

  def refetch_data(socket) do
    selected_date = socket.assigns.selected_date

    projects =
      Timetracker.list_user_projects_with_duration(
        socket.assigns.current_user.id,
        selected_date
      )

    current_month_hours_record =
      Timetracker.get_hours_record_by_month(
        socket.assigns.current_user.id,
        selected_date
      )

    socket
    |> assign(:current_hours_record, current_month_hours_record)
    |> assign(:projects, projects)
    |> assign(
      :total_duration,
      Timetracker.get_sessions_duration_in_month(
        socket.assigns.current_user.id,
        selected_date
      )
    )
  end

  def format_duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    [
      if(hours > 0, do: "#{hours} h"),
      "#{minutes} min"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  def format_duration(seconds, :extended) do
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    minutes = div(rem(seconds, 3600), 60)

    [
      if(days > 0, do: "#{days} dni"),
      if(hours > 0, do: "#{hours} h"),
      "#{minutes} min"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
  end

  def error_to_string(:too_large), do: "Image too large"
  def error_to_string(:too_many_files), do: "Too many files"
  def error_to_string(:not_accepted), do: "Unacceptable file type"
end
