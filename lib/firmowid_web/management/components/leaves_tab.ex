defmodule FirmowidWeb.Management.Components.LeavesTab do
  @moduledoc "Admin leave requests tab for a single employee."
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.DesignSystem.Components.YearPicker
  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [attach_access_hook: 2]
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Timetracker
  alias FirmowidWeb.Timetracker.Utilities.LeavePresentation

  @impl true
  def mount(socket), do: {:ok, attach_access_hook(socket, :scope)}

  @impl true
  def update(assigns, socket) do
    year = Map.get(assigns, :year) || socket.assigns[:year] || Date.utc_today().year

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:search, fn -> "" end)
      |> assign(:year, year)
      |> assign_new(:selected_request, fn -> nil end)
      |> assign_leave_requests()

    {:ok, socket}
  end

  defp assign_leave_requests(socket) do
    scope = socket.assigns.scope
    year = socket.assigns.year

    active_years = Timetracker.years_with_leave_requests(socket.assigns.employee.member.id, scope)

    requests =
      Timetracker.list_leave_requests_for_member!(
        socket.assigns.employee.member.id,
        %{start_date: Date.new!(year, 1, 1), end_date: Date.new!(year, 12, 31)},
        scope: scope
      )

    {pending, others} = Enum.split_with(requests, &(&1.status == :pending))

    others = LeavePresentation.filter_by_search(others, socket.assigns.search)

    leave_days =
      socket.assigns.employee.member
      |> Ash.load!([accepted_leave_days_for_year: %{year: year}], scope: scope)
      |> Map.get(:accepted_leave_days_for_year, 0)

    socket
    |> assign(:pending_requests, pending)
    |> assign(:other_requests, others)
    |> assign(:active_years, active_years)
    |> assign(:leave_days, leave_days)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex h-full min-h-0 flex-col gap-6">
      <.card
        class="flex max-h-48 shrink-0 flex-col overflow-hidden"
        dimmed={@employee.member.archived_at}
      >
        <div class="shrink-0">
          <.card_header>{gettext("Requests awaiting approval")}</.card_header>
        </div>
        <div class="scrollbar-card min-h-0 overflow-y-auto pr-2">
          <ul :if={@pending_requests != []} class="space-y-1">
            <.leave_row
              :for={request <- @pending_requests}
              request={request}
              show_pending_dot?={true}
              myself={@myself}
              clickable?={true}
            />
          </ul>
          <p :if={@pending_requests == []} class="text-sm text-grey-500">
            {gettext("No requests awaiting approval.")}
          </p>
        </div>
      </.card>

      <.card class="relative z-10 flex min-h-0 flex-1 flex-col" dimmed={@employee.member.archived_at}>
        <div class="flex items-center justify-between gap-3">
          <.card_header>{gettext("Other requests")}</.card_header>

          <div class="flex items-center gap-2">
            <form class="flex gap-4" phx-submit="search" phx-target={@myself}>
              <div
                id="leaves-search-container"
                data-expanded={to_string(@search != "")}
                class="group flex items-center justify-center rounded-lg transition-shadow data-[expanded=true]:bg-grey-200 data-[expanded=true]:focus-within:ring-2"
              >
                <.input
                  type="text"
                  name="szukaj"
                  value={@search}
                  placeholder={gettext("Search requests")}
                  phx-change="search"
                  phx-debounce="300"
                  phx-target={@myself}
                  input_class="py-0 px-1 bg-transparent! border-none"
                  class="w-0 border-transparent px-0 opacity-0 transition-[width,opacity,padding] duration-200 ease-in-out group-data-[expanded=true]:w-64 group-data-[expanded=true]:px-2 group-data-[expanded=true]:opacity-100 focus:border-none focus:ring-0 focus:outline-hidden"
                />
                <.button
                  type="button"
                  size="small"
                  variant="outline"
                  class="py-1.5"
                  phx-click={
                    JS.toggle_attribute({"data-expanded", "true", "false"},
                      to: "#leaves-search-container"
                    )
                    |> JS.focus(to: "#leaves-search-container input")
                  }
                >
                  <Lucideicons.search />
                </.button>
              </div>
            </form>
            <.year_picker
              id="leaves-year-picker"
              phx-target={@myself}
              selected_year={@year}
              size="small"
              variant="outline"
              active_years={@active_years}
              data-position="bottom right"
            />
          </div>
        </div>

        <div class="flex gap-3">
          <span class="rounded bg-grey-50 px-3 py-1 text-sm text-grey-500">
            {pgettext("leave days summary", "Used this year:")}
            <span class="pl-1 font-medium text-grey-700">
              {ngettext("%{count} day", "%{count} days", @leave_days)}
            </span>
          </span>
        </div>

        <div class="relative min-h-0 w-full flex-1">
          <div class="absolute inset-0 scrollbar-card space-y-1 overflow-y-auto pr-2">
            <ul :if={@other_requests != []} class="space-y-1">
              <.leave_row
                :for={request <- @other_requests}
                request={request}
                clickable?={true}
                myself={@myself}
              />
            </ul>
            <div
              :if={Enum.empty?(@other_requests)}
              class="flex size-full items-center justify-center rounded-lg bg-grey-50 text-sm text-grey-700"
            >
              <p>
                {gettext("No other requests.")}
              </p>
            </div>
          </div>
        </div>
      </.card>

      <.modal
        id="leave-request-review-modal"
        on_cancel={JS.push("clear_selected_leave_request", target: @myself)}
      >
        <div :if={@selected_request} id={"leave-review-#{@selected_request.id}"} class="space-y-8">
          <div class="flex items-center gap-3">
            <span class="flex size-6.5 shrink-0 items-center justify-center rounded bg-grey-100 text-grey-700">
              <.reason_icon reason={@selected_request.reason} />
            </span>

            <div class="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1">
              <h2 class="font-medium">
                {LeavePresentation.reason_label(@selected_request.reason)}
              </h2>
              <span class="inline text-grey-500">|</span>
              <span class="text-base font-medium text-grey-600 tabular-nums">
                {LeavePresentation.format_range(
                  @selected_request.starts_on,
                  @selected_request.ends_on
                )}
              </span>
            </div>
          </div>

          <div class="text-base whitespace-pre-line text-black" phx-no-format>{(@selected_request.note != "" && @selected_request.note) || gettext("The request has no content.")}</div>

          <div class="flex items-center justify-between">
            <.link
              :if={attachment_url(@selected_request)}
              kind="unstyled"
              external={attachment_url(@selected_request)}
              target="_blank"
              rel="noopener noreferrer"
              download={attachment_filename(@selected_request)}
              class="inline-flex items-center gap-2 text-sm font-medium text-grey-700 underline hover:text-grey-900"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" />
              {attachment_filename(@selected_request)}
            </.link>
            <div :if={@selected_request.status == :pending} class="ml-auto flex justify-end gap-4">
              <.button
                :if={@selected_request.category == :leave}
                type="button"
                variant="secondary"
                size="small"
                phx-click="decline_leave_request"
                phx-target={@myself}
                phx-disable-with={gettext("Rejecting...")}
              >
                {gettext("Reject")}
              </.button>

              <.button
                type="button"
                variant="primary"
                accent="teal"
                size="small"
                phx-click="accept_leave_request"
                phx-target={@myself}
                phx-disable-with={gettext("Approving...")}
              >
                {gettext("Approve")}
              </.button>
            </div>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  attr :reason, :atom, required: true
  attr :class, :string, default: "size-4"

  defp reason_icon(assigns) do
    ~H"""
    <%= cond do %>
      <% @reason in [:sick, :indisposition] -> %>
        <Lucideicons.cross class={@class} />
      <% @reason in [:rest, :vacation] -> %>
        <Lucideicons.sun class={@class} />
      <% @reason in [:unpaid, :other] -> %>
        <Lucideicons.slash class={@class} />
    <% end %>
    """
  end

  @impl true
  def handle_event("open_leave_request", %{"id" => id}, socket) do
    case Timetracker.get_leave_request(id,
           scope: socket.assigns.scope,
           load: [blob: [:url]],
           not_found_error?: false
         ) do
      {:ok, nil} ->
        LiveToast.send_toast(:error, gettext("Request not found."))
        {:noreply, socket}

      {:ok, request} ->
        {:noreply,
         socket
         |> assign(:selected_request, request)
         |> push_event("js-exec", %{
           to: "#leave-request-review-modal",
           attr: "phx-show"
         })}

      {:error, _} ->
        LiveToast.send_toast(:error, gettext("Could not open the request."))
        {:noreply, socket}
    end
  end

  def handle_event("accept_leave_request", _params, socket) do
    scope = socket.assigns.scope
    id = socket.assigns.selected_request.id

    case Timetracker.accept_leave_request(id, scope: scope) do
      {:ok, _} ->
        LiveToast.send_toast(:info, gettext("The request has been approved."))

        {:noreply,
         socket
         |> assign(:selected_request, nil)
         |> assign_leave_requests()
         |> push_event("js-exec", %{to: "#leave-request-review-modal", attr: "data-cancel"})}

      {:error, _} ->
        LiveToast.send_toast(:error, gettext("Could not approve the request."))
        {:noreply, socket}
    end
  end

  def handle_event("decline_leave_request", _params, socket) do
    scope = socket.assigns.scope
    id = socket.assigns.selected_request.id

    case Timetracker.decline_leave_request(id, scope: scope) do
      {:ok, _} ->
        LiveToast.send_toast(:info, gettext("The request has been rejected."))

        {:noreply,
         socket
         |> assign(:selected_request, nil)
         |> assign_leave_requests()
         |> push_event("js-exec", %{to: "#leave-request-review-modal", attr: "data-cancel"})}

      {:error, _} ->
        LiveToast.send_toast(:error, gettext("Could not reject the request."))
        {:noreply, socket}
    end
  end

  def handle_event("clear_selected_leave_request", _params, socket) do
    {:noreply, assign(socket, :selected_request, nil)}
  end

  def handle_event("search", %{"szukaj" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign_leave_requests()}
  end

  def handle_event("change-year", %{"year" => year}, socket) do
    {:noreply,
     socket
     |> assign(:year, String.to_integer(year))
     |> assign_leave_requests()}
  end

  attr :request, :map, required: true
  attr :show_pending_dot?, :boolean, default: false
  attr :clickable?, :boolean, default: false
  attr :myself, :any, default: nil

  defp leave_row(assigns) do
    ~H"""
    <li
      class={[
        "flex items-center gap-3 rounded px-1 py-2 transition",
        @clickable? && "cursor-pointer hover:bg-grey-50"
      ]}
      phx-click={
        @clickable? &&
          JS.push("open_leave_request", value: %{id: @request.id}, target: @myself)
      }
    >
      <span class="flex size-6.5 shrink-0 items-center justify-center rounded bg-grey-100 text-grey-700">
        <.reason_icon reason={@request.reason} />
      </span>

      <span class="flex min-w-0 flex-1 items-start gap-2 truncate">
        {LeavePresentation.reason_label(@request.reason)}
        <span
          :if={@show_pending_dot?}
          class="size-3 shrink-0 rounded-full bg-teal-500"
        />
      </span>

      <span
        :if={@request.blob_id}
        class="flex shrink-0 items-center text-grey-400"
        title={gettext("Attachment")}
      >
        <.icon name="hero-paper-clip" class="size-4" />
      </span>

      <span class="shrink-0 text-sm tabular-nums">
        {LeavePresentation.format_range(@request.starts_on, @request.ends_on)}
      </span>

      <span class={leave_status_badge_styles(@request.status)}>
        {LeavePresentation.status_label(@request.status)}
      </span>
    </li>
    """
  end

  defp leave_status_badge_styles(status) do
    [
      "w-31 shrink-0 rounded-2xl px-4 py-1 text-center text-sm",
      LeavePresentation.status_badge_styles(status)
    ]
  end

  defp attachment_url(%{blob: %{url: url}}) when is_binary(url), do: url
  defp attachment_url(_), do: nil

  defp attachment_filename(%{blob: %{original_filename: name}}), do: name
end
