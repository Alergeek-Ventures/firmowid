defmodule FirmowidWeb.Admin.Views.Organizations do
  @moduledoc """
  Superuser billing organizations list with live usage preview.
  """

  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Billing.Month
  alias Firmowid.Ash.Billing.PlanCatalog
  alias Firmowid.Ash.Billing.SnapshotCalculator
  alias Firmowid.Ash.Core
  alias FirmowidWeb.Admin.Components.SettlementComponents
  alias FirmowidWeb.Admin.Utilities.Navigation
  alias FirmowidWeb.Billing.Utilities.Worksheet

  @page_limit 25

  @legal_form_abbreviations [
    {"spółka komandytowo-akcyjna", "S.K.A."},
    {"spółka z ograniczoną odpowiedzialnością", "sp. z o.o."},
    {"spółka komandytowa", "sp. k."},
    {"spółka partnerska", "sp. p."},
    {"spółka jawna", "sp. j."},
    {"spółka akcyjna", "S.A."},
    {"spółka cywilna", "s.c."}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Rozliczenia")
     |> assign(:params, %{})
     |> assign(:search, "")
     |> assign(:plan_filter, nil)
     |> assign(:only_over_limit?, false)
     |> assign(:rows, [])
     |> assign(:keyset, nil)
     |> assign(:more?, false)
     |> assign(:current_month, Month.current())
     |> assign(:form, to_form(%{"tylko_nadwyzki" => false}))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    parsed = Navigation.list_params(params)
    search = Navigation.parse_search(parsed)
    plan_filter = Navigation.parse_plan(parsed)
    only_over_limit? = Navigation.parse_only_over_limit?(parsed)
    current_month = Month.current()

    page =
      list_organizations_page(socket.assigns.current_user,
        search: search,
        plan_filter: plan_filter
      )

    rows = build_rows(page.results, current_month, only_over_limit?)

    socket =
      socket
      |> assign(:params, parsed)
      |> assign(:search, search)
      |> assign(:plan_filter, plan_filter)
      |> assign(:only_over_limit?, only_over_limit?)
      |> assign(:current_month, current_month)
      |> assign(:form, to_form(%{"tylko_nadwyzki" => only_over_limit?}))
      |> assign(:rows, rows)
      |> assign(:keyset, next_keyset(page))
      |> assign(:more?, page.more?)

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"szukaj" => search}, socket) do
    params = Map.put(socket.assigns.params, "szukaj", String.trim(search))

    {:noreply, push_patch(socket, to: Navigation.settlements_path(params))}
  end

  def handle_event("filter_plan", %{"plan" => plan}, socket) do
    next_filter =
      case {socket.assigns.plan_filter, Navigation.parse_plan(%{"plan" => plan})} do
        {current, current} -> nil
        {_current, parsed} -> parsed
      end

    params =
      case next_filter do
        nil -> Map.delete(socket.assigns.params, "plan")
        value -> Map.put(socket.assigns.params, "plan", Atom.to_string(value))
      end

    {:noreply, push_patch(socket, to: Navigation.settlements_path(params))}
  end

  def handle_event("toggle_over_limit", _params, socket) do
    params =
      if socket.assigns.only_over_limit? do
        Map.delete(socket.assigns.params, "tylko_nadwyzki")
      else
        Map.put(socket.assigns.params, "tylko_nadwyzki", "1")
      end

    {:noreply, push_patch(socket, to: Navigation.settlements_path(params))}
  end

  def handle_event("show_more", _params, socket) do
    page =
      list_organizations_page(
        socket.assigns.current_user,
        search: socket.assigns.search,
        plan_filter: socket.assigns.plan_filter,
        keyset: socket.assigns.keyset
      )

    rows = build_rows(page.results, socket.assigns.current_month, socket.assigns.only_over_limit?)

    {:noreply,
     socket
     |> assign(:rows, socket.assigns.rows ++ rows)
     |> assign(:keyset, next_keyset(page))
     |> assign(:more?, page.more?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex w-full max-w-7xl flex-col gap-3 pb-4">
      <div class="bg-lightGreyBg top-navbar sticky z-10 flex flex-col gap-6 py-4">
        <div class="flex items-center justify-between gap-4">
          <form class="flex gap-4" phx-submit="search">
            <div class="bg-lightGreyBg border-greyButtonBg flex h-11 w-90 items-center gap-2 rounded-lg border p-1 focus-within:ring-2">
              <Lucideicons.search class="text-grey-500 size-6 shrink-0" />
              <.input
                type="text"
                name="szukaj"
                value={@search}
                placeholder="Szukaj organizacji"
                phx-change="search"
                phx-debounce="300"
                input_class="h-full bg-transparent border-none py-0 px-1 text-sm"
                class="w-full border-transparent focus:border-none focus:ring-0 focus:outline-hidden"
              />
            </div>
          </form>
        </div>

        <div class="flex flex-wrap items-center justify-between gap-4">
          <div class="flex flex-wrap items-center gap-6">
            <div class="flex items-center gap-3">
              <span class="text-darkGrey/70 text-sm font-normal">Filtry:</span>

              <div class="flex flex-wrap items-center gap-2">
                <.button
                  :for={plan <- PlanCatalog.plans()}
                  type="button"
                  variant="filter"
                  data-active={@plan_filter == plan}
                  phx-click="filter_plan"
                  phx-value-plan={Atom.to_string(plan)}
                >
                  {Worksheet.plan_label(plan)}
                </.button>
              </div>
            </div>
          </div>
          <.switch
            class="ml-auto flex-row-reverse gap-4 select-none"
            label="Tylko ponad limit"
            field={@form[:tylko_nadwyzki]}
            phx-click="toggle_over_limit"
          />
        </div>
      </div>

      <%= if Enum.empty?(@rows) do %>
        <p class="text-grey-700 text-sm/snug">
          <%= if @search != "" or not is_nil(@plan_filter) or @only_over_limit? do %>
            Nie znaleziono organizacji dla wybranych filtrów.
          <% else %>
            Brak organizacji do wyświetlenia.
          <% end %>
        </p>
      <% else %>
        <div class="text-grey-700 hidden gap-x-6 px-4 text-sm/snug lg:grid lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)_minmax(0,1.4fr)_auto]">
          <p>Organizacja</p>
          <p>Plan</p>
          <p>Od kiedy</p>
          <p>Użycie</p>
          <span />
        </div>

        <div id="organizations-list" class="grid gap-2">
          <div
            :for={row <- @rows}
            :key={row.org.id}
            class="grid items-center gap-x-6 gap-y-2 rounded-sm bg-white p-4 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_minmax(0,1fr)_minmax(0,1.4fr)_auto]"
          >
            <div class="min-w-0 space-y-1">
              <div class="flex flex-row flex-wrap items-center gap-2">
                <.link
                  kind="unstyled"
                  navigate={Navigation.settlement_path(row.org.id, %{"miesiac" => @current_month})}
                  class="text-base/snug font-medium hover:underline"
                >{short_org_name(row.org.name)}</.link>
                <SettlementComponents.billing_status_badge :if={row.org.on_trial?} status={:trial} />
              </div>
              <p class="text-grey-500 text-sm/snug">NIP: {row.org.nip}</p>
            </div>

            <div class="space-y-1 text-sm/snug">
              <p class="font-medium">{row.worksheet.selected_plan_label}</p>
              <p class="text-grey-700">
                <%= if row.worksheet.base_fee_line do %>
                  {row.worksheet.base_fee_line.amount} / mies.
                <% else %>
                  Brak opłaty bazowej
                <% end %>
              </p>
            </div>

            <div class="space-y-1 text-sm/snug">
              <p>{format_date(row.started_on)}</p>
              <p class="text-grey-700">{row.age_days} dni</p>
            </div>

            <div class="space-y-1 text-sm/snug">
              <div
                :for={usage <- row.worksheet.usage_rows}
                class="flex items-center justify-between gap-4"
              >
                <span class="text-grey-700">{usage.label}</span>
                <span class={usage_value_styles(usage)}>
                  {over_limit_prefix(usage)}{usage.total_text}
                </span>
              </div>
              <p class="text-grey-700">
                <%= if row.worksheet.suggestion_rows == [] do %>
                  Brak nadwyżek
                <% else %>
                  Nadwyżki: {length(row.worksheet.suggestion_rows)}
                <% end %>
              </p>
            </div>

            <.link
              kind="unstyled"
              navigate={Navigation.settlement_path(row.org.id, %{"miesiac" => @current_month})}
              class="hover:text-grey-700 text-grey-500 justify-self-end"
            >
              <Lucideicons.chevron_right class="size-4" />
            </.link>
          </div>
        </div>

        <.button
          :if={@more?}
          variant="ghost"
          size="small"
          phx-click="show_more"
          class="mt-4 w-full self-center"
        >
          Pokaż więcej
        </.button>
      <% end %>
    </div>
    """
  end

  defp list_organizations_page(current_user, opts) do
    search = Keyword.get(opts, :search, "")
    plan_filter = opts[:plan_filter]
    keyset = opts[:keyset]

    page_opts =
      Enum.reject([limit: @page_limit, after: keyset], fn {_key, val} -> is_nil(val) end)

    %{search: search, billing_plan: plan_filter}
    |> Core.query_to_list_organizations()
    |> Ash.Query.load([:on_trial?])
    |> sort_organizations(search)
    |> Ash.read!(actor: current_user, page: page_opts)
  end

  defp sort_organizations(query, search) when search in [nil, ""] do
    Ash.Query.sort(query, name: :asc, id: :asc)
  end

  defp sort_organizations(query, _search), do: query

  defp filter_over_limit(rows, false), do: rows
  defp filter_over_limit(rows, true), do: Enum.filter(rows, & &1.over_limit?)

  defp build_rows(organizations, current_month, only_over_limit?) do
    organizations
    |> Enum.map(&build_row(&1, current_month))
    |> filter_over_limit(only_over_limit?)
  end

  defp build_row(org, current_month) do
    usage_source = SnapshotCalculator.build_snapshot_attrs!(org, current_month)
    worksheet = Worksheet.build(usage_source)
    started_on = to_date(org.inserted_at)

    %{
      org: org,
      worksheet: worksheet,
      started_on: started_on,
      age_days: max(Date.diff(Date.utc_today(), started_on), 0),
      trial?: org.on_trial?,
      over_limit?: Enum.any?(worksheet.usage_rows, &(&1.over_limit > 0))
    }
  end

  defp to_date(%Date{} = date), do: date
  defp to_date(%DateTime{} = datetime), do: DateTime.to_date(datetime)
  defp to_date(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_date(datetime)

  defp usage_value_styles(%{over_limit: over_limit}) when over_limit > 0, do: "font-medium text-orange-700"

  defp usage_value_styles(_usage), do: "font-medium"

  defp over_limit_prefix(%{over_limit: over_limit}) when over_limit > 0, do: "(+#{over_limit}) "
  defp over_limit_prefix(_usage), do: ""

  defp short_org_name(name) when is_binary(name) do
    Enum.reduce(@legal_form_abbreviations, name, fn {full, short}, acc ->
      String.replace(acc, Regex.compile!(full, "iu"), short)
    end)
  end

  defp short_org_name(name), do: to_string(name)

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")

  defp next_keyset(%{results: []}), do: nil

  defp next_keyset(%{results: results}) do
    results |> List.last() |> Map.get(:__metadata__) |> Map.get(:keyset)
  end
end
