defmodule FirmowidWeb.Management.Views.Counterparties do
  @moduledoc """
  Management LiveView for listing active and archived counterparties.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.DesignSystem.Components.EmptyState
  import FirmowidWeb.Management.Components.ListToolbar
  import FirmowidWeb.Management.Components.SidePanel
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.Services.CounterpartyDetection
  alias FirmowidWeb.Management.Utilities.CounterpartyHelpers
  alias FirmowidWeb.Management.Utilities.Navigation

  on_mount {FirmowidWeb.Infrastructure.Hooks.RequireAdmin, :default}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Counterparty management"))
     # The page spaces itself, as in the design (see `counterparties.html.heex`).
     |> assign(:no_padding, true)
     |> assign(:suggestions, CounterpartyDetection.waiting_count(socket.assigns.ash_scope))
     |> assign(:view, :standard)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = Navigation.counterparties_params(params)

    socket =
      socket
      |> assign(:params, params)
      |> assign(:search, params["szukaj"] || "")
      |> assign(:type_filter, Navigation.parse_counterparty_type(params["typ"]))
      |> assign_counterparties()
      |> assign_form()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"szukaj" => search}, socket) do
    {:noreply, refresh_page(socket, Map.put(socket.assigns.params, "szukaj", String.trim(search)))}
  end

  def handle_event("toggle_type", %{"typ" => type}, socket) do
    next_type =
      case {socket.assigns.type_filter, Navigation.parse_counterparty_type(type)} do
        {current, current} -> nil
        {_current, parsed} -> parsed
      end

    params =
      case next_type do
        nil ->
          Map.delete(socket.assigns.params, "typ")

        value ->
          Map.put(socket.assigns.params, "typ", Navigation.encode_counterparty_type(value))
      end

    {:noreply, refresh_page(socket, params)}
  end

  def handle_event("unarchive_counterparty", %{"id" => id}, socket) do
    scope = socket.assigns.ash_scope

    with {:ok, counterparty} when not is_nil(counterparty) <-
           Invoicing.get_counterparty(id, scope: scope, not_found_error?: false),
         {:ok, _counterparty} <- Invoicing.unarchive_counterparty(counterparty, %{}, scope: scope) do
      {:noreply, assign_counterparties(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not restore the counterparty"))}
    end
  end

  def handle_event("toggle_cooperation_value_view", _params, socket) do
    {:noreply,
     socket
     |> assign(
       :view,
       if(socket.assigns.view == :standard, do: :cooperation_value, else: :standard)
     )
     |> assign_form()}
  end

  defp assign_counterparties(socket) do
    scope = socket.assigns.ash_scope

    status = if socket.assigns.live_action == :archive, do: :archived, else: :active

    filters =
      %{
        status: status,
        search: blank_to_nil(socket.assigns.search),
        type: socket.assigns.type_filter
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    counterparties =
      Invoicing.list_counterparties!(filters,
        load: [:display_label, :cooperation_value],
        scope: scope
      )

    assign(socket, :counterparties, counterparties)
  end

  defp assign_form(socket) do
    assign(
      socket,
      :form,
      to_form(%{"view_cooperation_value" => socket.assigns.view != :standard})
    )
  end

  defp refresh_page(socket, params) do
    params =
      Map.reject(params, fn
        {_k, ""} -> true
        {_k, nil} -> true
        _other -> false
      end)

    push_patch(socket, to: Navigation.counterparties_path(socket.assigns.live_action, params))
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp grid_columns(:index, :standard), do: "grid-cols-[minmax(0,1fr)_12.5rem_min-content]"

  defp grid_columns(:index, :cooperation_value), do: "grid-cols-[minmax(0,1fr)_12.5rem_12.5rem_min-content]"

  defp grid_columns(:archive, :standard), do: "grid-cols-[minmax(0,1fr)_12.5rem_7.5rem_max-content_min-content]"

  defp grid_columns(:archive, :cooperation_value),
    do: "grid-cols-[minmax(0,1fr)_12.5rem_12.5rem_7.5rem_max-content_min-content]"

  # A missing identifier ("—") is lighter than one in place (Figma "Wiersz kontrahenta").
  defp identifier_color(counterparty, live_action) do
    cond do
      CounterpartyHelpers.identifier(counterparty) == "—" -> "text-grey-400"
      live_action == :archive -> "text-grey-500"
      true -> "text-grey-700"
    end
  end

  defp counterparty_path(counterparty, live_action, params) do
    Navigation.counterparty_path(counterparty.id, %{
      powrot_do: Navigation.counterparties_path(live_action, params)
    })
  end

  attr :counterparties, :list, required: true

  # Figma "Kontrahenci": the active list in numbers.
  defp active_summary(assigns) do
    assigns =
      assign(assigns,
        rows: [
          {pgettext("counterparties summary", "Active"), length(assigns.counterparties)}
          | type_rows(assigns.counterparties)
        ]
      )

    ~H"""
    <.summary_card title={pgettext("management navigation", "Counterparties")} rows={@rows} />
    """
  end

  attr :counterparties, :list, required: true

  # Figma "Archiwum": the archive in numbers.
  defp archive_summary(assigns) do
    last_archived_on = assigns.counterparties |> Enum.map(& &1.archived_at) |> Enum.max(Date)

    assigns =
      assign(assigns,
        rows:
          [
            {pgettext("counterparties archive", "Archived counterparties"), length(assigns.counterparties)}
          ] ++
            type_rows(assigns.counterparties) ++
            [
              {pgettext("counterparties archive", "Last archived"), Calendar.strftime(last_archived_on, "%d.%m.%Y")}
            ]
      )

    ~H"""
    <.summary_card title={pgettext("counterparties archive", "Archive")} rows={@rows} />
    """
  end

  defp type_rows(counterparties) do
    companies = Enum.count(counterparties, &(&1.type == :company))

    [
      {pgettext("counterparties summary", "Companies"), companies},
      {gettext("Individuals"), length(counterparties) - companies}
    ]
  end

  attr :counterparties, :list, required: true
  attr :live_action, :atom, required: true
  attr :params, :map, required: true

  # Figma "Bez identyfikatora": the companies to complete, so their invoices carry a tax
  # identifier. Hidden when every company has one.
  defp companies_without_identifier(assigns) do
    assigns =
      assign(
        assigns,
        :missing,
        Enum.filter(
          assigns.counterparties,
          &(&1.type == :company and CounterpartyHelpers.identifier(&1) == "—")
        )
      )

    ~H"""
    <.panel_card
      :if={@missing != []}
      title={pgettext("counterparties summary", "Companies without an identifier")}
      count={length(@missing)}
    >
      <ul class="flex flex-col gap-3">
        <li :for={counterparty <- @missing} class="min-w-0">
          <.link
            kind="unstyled"
            navigate={counterparty_path(counterparty, @live_action, @params)}
            class="block truncate text-sm/[1.35] font-medium text-grey-900 hover:underline"
          >
            {counterparty.display_label}
          </.link>
        </li>
      </ul>
      <p class="text-sm/[1.35] text-grey-500">
        {gettext("Fill in the identifier in the counterparty's profile.")}
      </p>
    </.panel_card>
    """
  end

  attr :counterparty, :map, required: true
  attr :archived, :boolean, required: true

  # Figma "Icons" Company / User: Lucide building-2 and user, black, grey once archived.
  # The website icon fades in over the type icon once loaded; one that fails stays
  # hidden (the `data-progressive` script in the root layout). Its white background
  # covers the type icon behind a transparent logo, on the white row. Only companies
  # get a website domain (`CounterpartyWebsiteWorker`).
  defp counterparty_icon(assigns) do
    ~H"""
    <span class="relative flex size-6 shrink-0">
      <Lucideicons.render!
        name={if(@counterparty.type == :company, do: "building-2", else: "user")}
        class={["size-6", if(@archived, do: "text-grey-500", else: "text-black")]}
        aria-hidden="true"
      />
      <img
        :if={@counterparty.website_domain}
        data-progressive
        src={~p"/logotypy/#{@counterparty.website_domain}"}
        alt=""
        loading="lazy"
        decoding="async"
        class="absolute inset-0 size-full bg-white object-contain"
      />
    </span>
    """
  end

  defp cooperation_value_cell(nil), do: "—"

  defp cooperation_value_cell(%{total: total, currency: currency}) do
    total
    |> Money.new(currency)
    |> Money.to_string!(fractional_digits: 2)
  end
end
