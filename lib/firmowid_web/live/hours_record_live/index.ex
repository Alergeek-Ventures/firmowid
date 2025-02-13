defmodule FirmowidWeb.HoursRecordLive.Index do
  use FirmowidWeb, :live_view

  alias Firmowid.Timetracker

  @impl true
  def mount(_params, _session, socket) do
    selected_date = Date.utc_today()
    active_months = Timetracker.get_months_with_sessions(socket.assigns.current_user.id)

    socket =
      socket
      |> assign(:selected_date, selected_date)
      |> assign(:active_months, active_months)
      |> assign(:is_downloaded, false)
      |> assign(:uploaded_files, [])
      |> allow_upload(:file,
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

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    month = month |> Date.from_iso8601!()

    socket =
      socket
      |> assign(:selected_date, month)
      |> push_patch(to: ~p"/czasosledz/ewidencja?month=#{month |> Date.to_iso8601()}")

    {:noreply, socket}
  end

  def handle_event("download", _unsigned_params, socket) do
    {:noreply, assign(socket, is_downloaded: true)}
  end

  def refetch_data(socket) do
    selected_date = socket.assigns.selected_date

    projects =
      Timetracker.list_user_projects_with_duration(
        socket.assigns.current_user.id,
        selected_date
      )

    socket
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
