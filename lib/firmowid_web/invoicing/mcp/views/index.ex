defmodule FirmowidWeb.Invoicing.Mcp.Views.Index do
  @moduledoc "Read-only invoice browsing with capability authorization on every interaction."

  use FirmowidWeb, {:live_view, layout: false, log: false}

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.InvoicingBadges, only: [invoice_source_badge: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Invoicing.InvoiceList
  alias FirmowidWeb.Invoicing.Mcp.Invoices
  alias FirmowidWeb.Mcp.Session

  @filter_keys ~w(type query date_from date_to currency sort limit)
  @defaults %{
    "type" => "all",
    "query" => nil,
    "date_from" => nil,
    "date_to" => nil,
    "currency" => nil,
    "sort" => "newest",
    "limit" => 25,
    "cursor" => nil
  }

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(
        connected?: connected?(socket),
        status: :ready,
        query: @defaults,
        form: to_form(@defaults, as: :filters),
        empty?: true,
        has_more: false,
        next_cursor: nil,
        error: nil
      )
      |> stream_configure(:invoices, dom_id: &"invoice-#{&1.type}-#{&1.id}")
      |> stream(:invoices, [])
      |> put_private(:mcp_session, session["mcp_session"])

    case authorize(socket) do
      {:ok, %{query: query, expires_at: expires_at} = capability} ->
        if connected?(socket) do
          Process.send_after(
            self(),
            :session_expired,
            max(expires_at - System.system_time(:second), 0) * 1_000
          )
        end

        params = if connected?(socket), do: get_connect_params(socket), else: %{}
        query = if is_map(params["query"]), do: params["query"], else: query
        {:ok, load(socket, tool_arguments(query), capability)}

      {:error, _reason} ->
        {:ok, expire(socket)}
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    case authorize(socket) do
      {:ok, capability} -> {:noreply, interact(event, params, socket, capability)}
      {:error, _reason} -> {:noreply, expire(socket)}
    end
  end

  @impl true
  def handle_info(:session_expired, socket), do: {:noreply, expire(socket)}

  defp interact("filter", %{"filters" => params}, socket, capability) when is_map(params) do
    query =
      params
      |> Map.take(@filter_keys)
      |> Map.new(fn
        {key, ""} when key in ~w(query date_from date_to currency) -> {key, nil}
        entry -> entry
      end)
      |> Map.put("cursor", nil)

    load(socket, query, capability)
  end

  defp interact("refresh", _params, socket, capability), do: load(socket, socket.assigns.query, capability)

  defp interact("first", _params, socket, capability) do
    load(socket, Map.put(socket.assigns.query, "cursor", nil), capability)
  end

  defp interact("next", _params, %{assigns: %{has_more: true, next_cursor: cursor}} = socket, capability)
       when is_binary(cursor) do
    load(socket, Map.put(socket.assigns.query, "cursor", cursor), capability)
  end

  defp interact(_event, _params, socket, _capability), do: socket

  defp authorize(%{private: %{mcp_session: token}}) when is_binary(token) do
    Session.authorize(token, Invoices.resource_uri())
  end

  defp authorize(_socket), do: {:error, :unauthorized}

  defp load(socket, query, capability) do
    case InvoiceList.list(query, scope: capability.scope) do
      {:ok, data} ->
        present(socket, data, query, capability.expires_at)

      {:error, _reason} ->
        if System.system_time(:second) >= capability.expires_at do
          expire(socket)
        else
          socket
          |> assign(
            form: to_form(query, as: :filters),
            empty?: true,
            has_more: false,
            next_cursor: nil,
            error: gettext("Unable to load invoices. Check the filters and try again.")
          )
          |> stream(:invoices, [], reset: true)
        end
    end
  end

  defp present(socket, data, requested_query, expires_at) do
    if System.system_time(:second) >= expires_at do
      expire(socket)
    else
      data = Invoices.present_result(data)
      query = data.query |> tool_arguments() |> Map.put("cursor", requested_query["cursor"])

      socket
      |> assign(
        query: query,
        form: to_form(query, as: :filters),
        empty?: data.invoices == [],
        has_more: data.has_more,
        next_cursor: data.next_cursor,
        error: nil
      )
      |> stream(:invoices, data.invoices, reset: true)
      |> push_event("mcp:context", %{structuredContent: data, arguments: %{input: query}})
    end
  end

  defp tool_arguments(query) do
    Map.new(query, fn {key, value} -> {to_string(key), value} end)
  end

  defp expire(socket) do
    socket
    |> put_private(:mcp_session, nil)
    |> assign(
      status: :expired,
      query: @defaults,
      form: to_form(@defaults, as: :filters),
      empty?: true,
      has_more: false,
      next_cursor: nil,
      error: nil
    )
    |> stream(:invoices, [], reset: true)
    |> push_event("mcp:expired", %{})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="mcp-invoices"
      class="flex min-w-0 flex-col gap-5 p-[clamp(1rem,3vw,2rem)]"
      phx-disconnected={JS.set_attribute({"inert", ""})}
      phx-connected={JS.remove_attribute("inert")}
    >
      <header class="flex flex-wrap items-center justify-between gap-3">
        <h1 class="text-grey-900 text-xl font-medium">{gettext("Invoices")}</h1>
        <.button
          :if={@status == :ready}
          variant="outline"
          size="small"
          type="button"
          phx-click="refresh"
          disabled={!@connected?}
        >
          {gettext("Refresh")}
        </.button>
      </header>

      <section :if={@status == :expired} role="status" class="flex flex-col gap-3">
        <p>{gettext("This invoice session has expired. Reconnect to continue.")}</p>
        <.button type="button" variant="primary" data-mcp-remount>
          {gettext("Reconnect")}
        </.button>
      </section>

      <.form :if={@status == :ready} for={@form} id="invoice-filters" phx-submit="filter">
        <fieldset
          disabled={!@connected?}
          class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,12rem),1fr))] gap-3"
        >
          <legend class="sr-only">{gettext("Invoice filters")}</legend>
          <.input
            field={@form[:type]}
            type="select"
            label={gettext("Invoice type")}
            options={[
              {gettext("All invoices"), "all"},
              {gettext("Sales invoices"), "sales"},
              {gettext("Cost invoices"), "cost"}
            ]}
          />
          <.input
            field={@form[:query]}
            type="search"
            label={gettext("Search invoices")}
            maxlength="500"
          />
          <.input field={@form[:date_from]} type="date" label={gettext("Issue date from")} />
          <.input field={@form[:date_to]} type="date" label={gettext("Issue date to")} />
          <.input field={@form[:currency]} label={gettext("Currency")} maxlength="3" />
          <.input
            field={@form[:sort]}
            type="select"
            label={gettext("Order")}
            options={[{gettext("Newest first"), "newest"}, {gettext("Oldest first"), "oldest"}]}
          />
          <.input
            field={@form[:limit]}
            type="number"
            label={gettext("Invoices per page")}
            min="1"
            max="100"
            required
          />
          <.button
            type="submit"
            variant="primary"
            class="self-end"
            phx-disable-with={gettext("Loading…")}
          >
            {gettext("Apply filters")}
          </.button>
        </fieldset>
      </.form>

      <p :if={@error} role="alert">{@error}</p>
      <p :if={@status == :ready && @empty? && is_nil(@error)} role="status">
        {gettext("No invoices match these filters.")}
      </p>

      <ul id="invoice-results" phx-update="stream" class="flex min-w-0 flex-col gap-3">
        <li
          :for={{dom_id, invoice} <- @streams.invoices}
          id={dom_id}
          class="border-grey-200 rounded-lg border p-4"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div class="flex min-w-0 flex-1 items-start gap-3">
              <.invoice_source_badge variant={badge_variant(invoice)} size="small" />
              <div class="flex min-w-0 flex-col gap-1 wrap-anywhere">
                <.link
                  kind="unstyled"
                  external={invoice.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="font-medium underline underline-offset-4 focus-visible:outline-2 active:opacity-75"
                >
                  {invoice.number || gettext("Unnumbered invoice")}
                </.link>
                <p>{invoice.counterparty}</p>
                <p class="text-grey-700 text-sm">{invoice_type(invoice.type)}</p>
              </div>
            </div>
            <p class="text-grey-900 font-medium tabular-nums">
              {invoice.amount.value} {invoice.amount.currency}
            </p>
          </div>
          <dl class="text-grey-700 mbs-3 flex flex-wrap gap-x-5 gap-y-2 text-sm">
            <div class="flex flex-wrap gap-1">
              <dt>{gettext("Issue date")}:</dt>
              <dd>{invoice.issue_date || gettext("Not provided")}</dd>
            </div>
            <div class="flex flex-wrap gap-1">
              <dt>{gettext("Due date")}:</dt>
              <dd>{invoice.due_date || gettext("Not provided")}</dd>
            </div>
            <div :if={invoice.ksef_number} class="flex min-w-0 flex-wrap gap-1 wrap-anywhere">
              <dt>{gettext("KSeF number")}:</dt>
              <dd>{invoice.ksef_number}</dd>
            </div>
          </dl>
        </li>
      </ul>

      <nav
        :if={@status == :ready}
        aria-label={gettext("Invoice pages")}
        class="flex flex-wrap justify-between gap-3"
      >
        <.button
          type="button"
          variant="outline"
          size="small"
          phx-click="first"
          disabled={!@connected? || is_nil(@query["cursor"])}
        >
          {gettext("First page")}
        </.button>
        <.button
          type="button"
          variant="outline"
          size="small"
          phx-click="next"
          disabled={!@connected? || !@has_more}
        >
          {gettext("Next page")}
        </.button>
      </nav>
    </main>
    """
  end

  defp invoice_type("sales"), do: gettext("Sales invoice")
  defp invoice_type("cost"), do: gettext("Cost invoice")

  defp badge_variant(%{type: "cost", ksef_number: nil}), do: "cost_external"
  defp badge_variant(%{type: "cost"}), do: "cost_ksef"

  defp badge_variant(%{type: "sales", ksef_number: number}) when is_binary(number), do: "sales_ksef"

  defp badge_variant(%{type: "sales", number: nil}), do: "sales_draft"
  defp badge_variant(%{type: "sales"}), do: "sales"
end
