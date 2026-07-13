defmodule FirmowidWeb.Management.Views.Counterparty do
  @moduledoc """
  Management LiveView for displaying a counterparty and basic invoicing stats.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CountryCodes
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.CounterpartyInvoiceSuggestions
  alias FirmowidWeb.Invoicing.Utilities.Navigation, as: InvoicingNavigation
  alias FirmowidWeb.Management.Utilities.CounterpartyHelpers
  alias FirmowidWeb.Management.Utilities.Navigation

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :params, %{})}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    scope = socket.assigns.ash_scope
    params = Navigation.counterparty_params(params)
    return_path = Navigation.counterparty_return_path(params)

    case Invoicing.get_counterparty(id,
           load: [:display_label],
           scope: scope,
           not_found_error?: false
         ) do
      {:ok, nil} ->
        {:noreply, push_navigate(socket, to: return_path)}

      {:ok, counterparty} ->
        invoice_filter = parse_invoice_filter(params["filtr_faktur"])

        {:noreply,
         socket
         |> assign(:params, params)
         |> assign_counterparty_page(counterparty, invoice_filter)}

      {:error, _error} ->
        {:noreply,
         socket
         |> put_flash(:error, "Nie udało się wczytać kontrahenta")
         |> push_navigate(to: return_path)}
    end
  end

  @impl true
  def handle_event("archive_counterparty", _params, socket) do
    scope = socket.assigns.ash_scope

    case Invoicing.archive_counterparty(socket.assigns.counterparty, %{}, scope: scope) do
      {:ok, counterparty} ->
        {:noreply, assign_counterparty_page(socket, counterparty)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się zarchiwizować kontrahenta")}
    end
  end

  def handle_event("unarchive_counterparty", _params, socket) do
    scope = socket.assigns.ash_scope

    case Invoicing.unarchive_counterparty(socket.assigns.counterparty, %{}, scope: scope) do
      {:ok, counterparty} ->
        {:noreply, assign_counterparty_page(socket, counterparty)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się przywrócić kontrahenta")}
    end
  end

  def handle_event("copy_identifier", %{"value" => value}, socket) do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: value})
     |> LiveToast.put_toast(:success, "Skopiowano identyfikator")}
  end

  def handle_event("connect_suggested_invoice", %{"invoice_id" => invoice_id}, socket) do
    scope = socket.assigns.ash_scope
    counterparty = socket.assigns.counterparty

    with {:ok, invoice} when not is_nil(invoice) <-
           Invoicing.get_sales_invoice(invoice_id, scope: scope),
         {:ok, _updated_invoice} <-
           Invoicing.attach_suggested_sales_invoice_counterparty(invoice, counterparty.id, scope: scope) do
      {:noreply,
       socket
       |> assign_counterparty_page(counterparty)
       |> LiveToast.put_toast(:success, "Połączono fakturę z kontrahentem")}
    else
      {:ok, nil} ->
        {:noreply, put_flash(socket, :error, "Nie znaleziono faktury")}

      {:error, %Ash.Error.Invalid{errors: [%{message: message} | _rest]}} ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się połączyć faktury z kontrahentem")}
    end
  end

  def handle_event("increase_invoice_limit", _params, socket) do
    new_limit = socket.assigns.invoice_limit + invoice_limit()
    {:noreply, assign(socket, :invoice_limit, new_limit)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto my-4 grid w-full max-w-screen-2xl grid-cols-[96px_minmax(0,1fr)_96px] grid-rows-[repeat(5,max-content)] gap-x-10 gap-y-5">
      <.link
        kind="unstyled"
        navigate={Navigation.counterparty_return_path(@params)}
        class="col-start-1 row-start-1 flex items-center gap-2 self-center text-sm"
      >
        <Lucideicons.circle_chevron_left /> Wróć
      </.link>

      <.page_header counterparty={@counterparty} params={@params} class="col-start-2 row-start-1" />

      <.archive_notice
        :if={@counterparty.archived_at}
        counterparty={@counterparty}
        class="col-start-2 row-start-2 mt-3"
      />

      <.details_and_stats
        counterparty={@counterparty}
        stats={@stats}
        class={[
          "col-start-2",
          if(@counterparty.archived_at, do: "mt-5", else: "mt-3")
        ]}
      />

      <.suggested_invoices_section
        :if={@suggested_invoices != []}
        counterparty={@counterparty}
        suggested_invoices={@suggested_invoices}
        params={@params}
        class="col-start-2"
      />

      <.invoices_section
        counterparty={@counterparty}
        params={@params}
        invoice_filter={@invoice_filter}
        invoices={@invoices}
        limit={@invoice_limit}
        class="col-start-2"
      />
    </div>
    """
  end

  attr :counterparty, :map, required: true
  attr :params, :map, default: %{}
  attr :class, :any, default: nil

  defp page_header(assigns) do
    ~H"""
    <div class={["flex min-h-12 items-center justify-between gap-4", @class]}>
      <p class="flex items-center gap-4 text-2xl/tight font-medium">
        {@counterparty.display_label}
        <span
          :if={@counterparty.archived_at}
          class="bg-grey-200 text-grey-700 inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm/snug font-normal"
        >
          <Lucideicons.archive class="size-4" /> zarchiwizowany
        </span>
      </p>

      <div class="flex gap-4">
        <%= if !@counterparty.archived_at do %>
          <.button variant="outline" type="button" phx-click="archive_counterparty">
            <.icon name="hero-archive-box-mini" class="size-5" /> Archiwizuj
          </.button>
        <% end %>

        <.link
          navigate={Navigation.counterparty_edit_path(@counterparty.id, @params)}
          kind="button"
          variant="outline"
        >
          <Lucideicons.square_pen /> Edytuj
        </.link>
      </div>
    </div>
    """
  end

  attr :counterparty, :map, required: true
  attr :class, :any, default: nil

  defp archive_notice(assigns) do
    ~H"""
    <div
      :if={@counterparty.archived_at}
      class={[
        "bg-grey-200 text-grey-700 flex items-center gap-4 rounded-lg p-4 shadow-[0px_1px_6px_0px_rgba(0,0,0,0.1)]",
        @class
      ]}
    >
      <Lucideicons.info class="size-4" />
      <p class="text-sm/snug text-balance">
        Kontrahent został zarchiwizowany {Firmowid.Cldr.Date.to_string!(@counterparty.archived_at,
          format: :long
        )}.
        Dane pozostają dostępne historycznie, ale kontrahent nie pojawi się w nowych wyborach.
      </p>

      <.button
        variant="tertiary"
        size="small"
        type="button"
        phx-click="unarchive_counterparty"
        class="ml-auto"
      >
        Przywróć kontrahenta
      </.button>
    </div>
    """
  end

  attr :counterparty, :map, required: true
  attr :stats, :map, required: true
  attr :class, :any, default: nil

  defp details_and_stats(assigns) do
    ~H"""
    <div class={["grid grid-cols-[1.5fr_0.95fr] gap-5", @class]}>
      <div class="space-y-5">
        <section class="rounded-lg bg-white p-6 shadow-[0px_1px_6px_0px_rgba(0,0,0,0.1)]">
          <div class="grid grid-cols-[minmax(0,265px)_minmax(0,322px)] gap-x-12 gap-y-6">
            <div class="space-y-6">
              <div class="space-y-1">
                <p class="text-grey-700 text-sm/snug">
                  {if @counterparty.type == :individual, do: "PESEL", else: "NIP / ID"}
                </p>
                <div class="flex items-center gap-2 text-base/snug text-black">
                  <p>{CounterpartyHelpers.identifier(@counterparty)}</p>
                  <.button
                    :if={CounterpartyHelpers.identifier(@counterparty) != "—"}
                    type="button"
                    variant="icon"
                    phx-click="copy_identifier"
                    phx-value-value={CounterpartyHelpers.identifier(@counterparty)}
                    class="h-6 w-7 duration-300"
                  >
                    <.icon name="hero-document-duplicate" class="size-5" />
                  </.button>
                </div>
              </div>

              <div class="space-y-1">
                <p class="text-grey-700 text-sm/snug">Adres</p>
                <p class="text-base/snug whitespace-pre-line text-black" phx-no-format>{formatted_multiline(@counterparty.address)}</p>
              </div>

              <div class="space-y-1">
                <p class="text-grey-700 text-sm/snug">Kraj</p>
                <p class="text-base/snug text-black">{country_label(@counterparty.country)}</p>
              </div>
            </div>

            <div class="space-y-6">
              <div class="space-y-1">
                <p class="text-grey-700 text-sm/snug">Pełna nazwa</p>
                <p class="text-base/snug text-black">
                  {CounterpartyHelpers.full_name(@counterparty)}
                </p>
              </div>

              <div class="space-y-2">
                <p class="text-grey-700 text-sm/snug">Kontakt</p>
                <div class="space-y-2 text-base/snug text-black">
                  <div class="flex items-center gap-2">
                    <.icon name="hero-envelope" class="text-grey-700 size-4 shrink-0" />
                    <span>{@counterparty.email || "—"}</span>
                  </div>
                  <div class="flex items-center gap-2">
                    <.icon name="hero-phone" class="text-grey-700 size-4 shrink-0" />
                    <span>{@counterparty.phone || "—"}</span>
                  </div>
                </div>
              </div>

              <div :if={@counterparty.is_different_mail_address} class="space-y-1">
                <p class="text-grey-700 text-sm/snug">Adres korespondencyjny</p>
                <p class="text-base/snug whitespace-pre-line text-black" phx-no-format>{formatted_multiline(@counterparty.mail_address)}</p>
              </div>
            </div>
          </div>
        </section>

        <section class="rounded-lg bg-white p-6 shadow-[0px_1px_6px_0px_rgba(0,0,0,0.1)]">
          <p class="text-grey-700 mb-2 text-sm/snug">Notatki</p>
          <p class="text-base/snug whitespace-pre-line text-black" phx-no-format>{@counterparty.description || "—"}</p>
        </section>
      </div>

      <section class="flex min-h-[318px] flex-col justify-between rounded-lg bg-white p-6 shadow-[0px_1px_6px_0px_rgba(0,0,0,0.1)]">
        <div class="space-y-6">
          <h3 class="text-grey-900 text-base/tight font-medium">Statystyki</h3>

          <div class="space-y-1">
            <p class="text-grey-700 text-sm/snug">Wartość współpracy</p>
            <p class="text-[23px]/tight font-medium text-[#455e5e]">
              {money_to_string(@stats.cooperation_value, @stats.currency)}
            </p>
          </div>

          <div class="grid grid-cols-2 gap-5">
            <div class="space-y-1">
              <p class="text-grey-700 text-sm/snug">Liczba faktur</p>
              <p class="text-base/snug text-black">{@stats.invoices_count}</p>
            </div>

            <div class="space-y-1">
              <p class="text-grey-700 text-sm/snug">Średnia kwota faktury</p>
              <p class="text-base/snug text-black">
                {money_to_string(@stats.average_value, @stats.currency)}
              </p>
            </div>
          </div>
        </div>

        <div class="border-grey-200 mt-6 border-t pt-4">
          <div class="bg-grey-50 flex items-center justify-between rounded-lg px-3 py-2">
            <div class="space-y-1">
              <p class="text-grey-700 text-sm/snug">Ostatnia faktura</p>
              <p class="text-base/snug text-black">{format_date(@stats.last_invoice_date)}</p>
            </div>

            <.icon name="hero-document-text-solid" class="text-grey-700 size-6" />
          </div>
        </div>
      </section>
    </div>
    """
  end

  attr :counterparty, :map, required: true
  attr :params, :map, default: %{}
  attr :invoice_filter, :atom, required: true
  attr :invoices, :list, required: true
  attr :class, :any, default: nil
  attr :limit, :integer

  defp invoices_section(assigns) do
    ~H"""
    <section class={[
      "flex flex-col rounded-lg bg-white p-6 shadow-[0px_1px_6px_0px_rgba(0,0,0,0.1)]",
      @class
    ]}>
      <div class="mb-4 flex items-center justify-between gap-4">
        <h3 class="text-grey-700 text-lg font-medium">Faktury</h3>

        <div class="flex gap-2">
          <.link
            :for={
              {value, label} <- [{:all, "Wszystkie"}, {:unpaid, "Nieopłacone"}, {:paid, "Opłacone"}]
            }
            patch={
              Navigation.counterparty_path(@counterparty.id, %{
                filtr_faktur: encode_invoice_filter(value),
                powrot_do: @params["powrot_do"]
              })
            }
            kind="button"
            variant="outline"
            size="small"
            class={[
              "bg-grey-100 rounded-2xl! px-4",
              if(@invoice_filter == value, do: invoice_filter_class_names(value))
            ]}
          >
            {label}
          </.link>
        </div>
      </div>

      <%= if @invoices == [] do %>
        <div class="text-grey-700 py-6 text-center text-sm/snug">
          Brak faktur dla wybranego filtra.
        </div>
      <% else %>
        <div class="grid grid-cols-[220px_1fr_140px_123px_min-content] gap-x-6 gap-y-2">
          <div class="text-grey-500 col-span-full grid grid-cols-subgrid px-2 py-1 text-sm/snug">
            <p>Numer faktury</p>
            <p class="text-left">Data wystawienia</p>
            <p class="text-right">Kwota</p>
            <p class="text-center">Status</p>
          </div>

          <div class="col-span-full grid grid-cols-subgrid gap-y-2">
            <div
              :for={invoice <- Enum.take(@invoices, @limit)}
              :key={invoice.id}
              class="bg-grey-50 col-span-full grid grid-cols-subgrid items-center rounded-sm px-2 py-3"
            >
              <.link
                kind="unstyled"
                navigate={
                  InvoicingNavigation.sales_invoice_show_path(
                    invoice.id,
                    Navigation.counterparty_path(@counterparty.id, @params)
                  )
                }
                class="hover:underline"
              >
                {invoice.invoice_number}
              </.link>
              <p class="text-left">{format_date(invoice.issue_date)}</p>
              <p class="text-right">{money_to_string(invoice.gross_value, invoice.currency)}</p>
              <div class="flex justify-center"><.invoice_status_badge invoice={invoice} /></div>
              <.link
                kind="unstyled"
                navigate={
                  InvoicingNavigation.sales_invoice_show_path(
                    invoice.id,
                    Navigation.counterparty_path(@counterparty.id, @params)
                  )
                }
                class="hover:text-grey-700 text-grey-500"
              >
                <Lucideicons.chevron_right class="size-4" />
              </.link>
            </div>
          </div>
        </div>
        <.button
          :if={length(@invoices) > @limit}
          variant="ghost"
          size="small"
          phx-click="increase_invoice_limit"
          class="mt-4 self-center"
        >
          Załaduj więcej faktur
        </.button>
      <% end %>
    </section>
    """
  end

  attr :counterparty, :map, required: true
  attr :suggested_invoices, :list, required: true
  attr :params, :map, default: %{}
  attr :class, :any, default: nil

  defp suggested_invoices_section(assigns) do
    ~H"""
    <section class={["rounded-lg bg-white p-6 shadow-[0px_1px_6px_0px_rgba(0,0,0,0.1)]", @class]}>
      <div class="mb-4 flex items-start justify-between gap-4">
        <div class="space-y-1">
          <h3 class="text-grey-700 text-lg font-medium">Sugerowane faktury do połączenia</h3>
          <p class="text-grey-700 text-sm/snug">
            Wyszukane po NIP / VAT-ID:
            <span class="font-medium text-black">{@counterparty.tax_id}</span>
          </p>
        </div>
      </div>

      <div class="grid grid-cols-[1fr_180px_140px_140px_min-content] gap-x-6 gap-y-2">
        <div class="text-grey-500 col-span-full grid grid-cols-subgrid px-2 py-1 text-sm/snug">
          <p>Numer faktury</p>
          <p>Identyfikator nabywcy</p>
          <p class="text-right">Data wystawienia</p>
          <p class="text-right">Kwota</p>
        </div>

        <div class="col-span-full grid grid-cols-subgrid gap-y-2">
          <div
            :for={invoice <- @suggested_invoices}
            :key={invoice.id}
            class="bg-grey-50 col-span-full grid grid-cols-subgrid items-center rounded-sm px-2 py-3"
          >
            <.link
              kind="unstyled"
              navigate={
                InvoicingNavigation.sales_invoice_show_path(
                  invoice.id,
                  Navigation.counterparty_path(@counterparty.id, @params)
                )
              }
              class="hover:underline"
            >
              {invoice_label(invoice)}
            </.link>
            <p class="truncate">{invoice.buyer_id || "—"}</p>
            <p class="text-right">{format_date(invoice.issue_date)}</p>
            <p class="text-right">{money_to_string(invoice.gross_value, invoice.currency)}</p>
            <.button
              type="button"
              variant="outline"
              size="small"
              phx-click="connect_suggested_invoice"
              phx-value-invoice_id={invoice.id}
            >
              Połącz
            </.button>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp assign_counterparty_page(socket, counterparty, invoice_filter \\ nil) do
    scope = socket.assigns.ash_scope
    invoice_filter = invoice_filter || socket.assigns[:invoice_filter] || :all
    invoice_limit = socket.assigns[:invoice_limit] || invoice_limit()
    counterparty = Ash.load!(counterparty, [:display_label, :cooperation_value], scope: scope)
    stats_invoices = list_counterparty_invoices(counterparty.id, :all, scope)
    visible_invoices = list_counterparty_invoices(counterparty.id, invoice_filter, scope)
    suggested_invoices = CounterpartyInvoiceSuggestions.list_for_counterparty(counterparty, scope)

    socket
    |> assign(:counterparty, counterparty)
    |> assign(:invoice_filter, invoice_filter)
    |> assign(:suggested_invoices, suggested_invoices)
    |> assign(:stats, build_stats(counterparty, stats_invoices))
    |> assign(:invoices, visible_invoices)
    |> assign(:page_title, counterparty.display_label)
    |> assign(:invoice_limit, invoice_limit)
  end

  defp list_counterparty_invoices(counterparty_id, invoice_filter, scope) do
    args = maybe_put_reconciliation(%{submission: :confirmed}, invoice_filter)

    SalesInvoice
    |> Ash.Query.for_read(:read, args, scope: scope)
    |> Ash.Query.filter(counterparty_id == ^counterparty_id)
    |> Ash.Query.load([:gross_value, :reconciliation_status])
    |> Ash.read!(scope: scope)
  end

  defp maybe_put_reconciliation(args, :unpaid), do: Map.put(args, :reconciliation, :pending)
  defp maybe_put_reconciliation(args, :paid), do: Map.put(args, :reconciliation, :matched)
  defp maybe_put_reconciliation(args, :all), do: args

  defp parse_invoice_filter(filter), do: Navigation.parse_counterparty_invoice_filter(filter) || :all

  defp encode_invoice_filter(filter), do: Navigation.encode_counterparty_invoice_filter(filter)

  defp build_stats(counterparty, invoices) do
    paid_invoices = Enum.filter(invoices, &(&1.reconciliation_status == :matched))

    count = length(paid_invoices)

    {total, currency} =
      case counterparty.cooperation_value do
        %{total: total, currency: currency} -> {total, currency}
        _ -> {nil, nil}
      end

    average_value =
      case total do
        total when not is_nil(total) and count > 0 ->
          Decimal.div(total, Decimal.new(count))

        _ ->
          nil
      end

    %{
      cooperation_value: total,
      currency: currency,
      invoices_count: count,
      average_value: average_value,
      last_invoice_date: paid_invoices |> Enum.map(& &1.issue_date) |> Enum.max(Date, fn -> nil end)
    }
  end

  defp invoice_label(%{invoice_number: invoice_number}) when invoice_number not in [nil, ""], do: invoice_number

  defp invoice_label(_invoice), do: "Szkic bez numeru"

  defp invoice_status(:pending), do: {"nieopłacona", "bg-orange-100 text-orange-700"}
  defp invoice_status(:skipped), do: {"pominięta", "bg-grey-200 text-grey-700"}
  defp invoice_status(:matched), do: {"opłacona", "bg-turquoise-100 text-turquoise-700"}
  defp invoice_status(_), do: {"opłacona", "bg-turquoise-100 text-turquoise-700"}

  defp invoice_filter_class_names(:all), do: "bg-grey-200 text-grey-700 border-transparent"

  defp invoice_filter_class_names(:unpaid), do: "bg-orange-200 text-orange-700 border-transparent hover:bg-orange-200"

  defp invoice_filter_class_names(:paid),
    do: "bg-turquoise-200 text-turquoise-700 border-transparent hover:bg-turquoise-200"

  defp money_to_string(nil, _currency), do: "—"

  defp money_to_string(amount, currency) when not is_nil(currency) do
    currency
    |> Money.new(amount)
    |> Money.to_string!()
  end

  defp money_to_string(_amount, _currency), do: "—"

  defp format_date(nil), do: "—"
  defp format_date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  defp maybe_country(""), do: "—"
  defp maybe_country(code), do: CountryCodes.country_name(code)

  defp country_flag(nil), do: "🏳️"
  defp country_flag(""), do: "🏳️"
  defp country_flag("EL"), do: country_flag("GR")
  defp country_flag("XI"), do: "🇬🇧"

  defp country_flag(code) when is_binary(code) do
    code
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.map(&(&1 + 127_397))
    |> List.to_string()
  rescue
    _error -> "🏳️"
  end

  defp country_label(nil), do: "—"
  defp country_label(""), do: "—"

  defp country_label(code) do
    "#{country_flag(code)} #{maybe_country(code)}"
  end

  defp formatted_multiline(nil), do: "—"
  defp formatted_multiline(""), do: "—"

  defp formatted_multiline(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    |> case do
      "" -> "—"
      formatted -> formatted
    end
  end

  defp invoice_limit, do: 6

  attr :invoice, :map, required: true

  def invoice_status_badge(assigns) do
    {label, class_name} = invoice_status(assigns.invoice.reconciliation_status)
    assigns = assign(assigns, :label, label)
    assigns = assign(assigns, :class_name, class_name)

    ~H"""
    <span class={[
      "inline-flex min-w-[123px] items-center justify-center rounded-full px-4 py-1 text-sm/snug",
      @class_name
    ]}>
      {@label}
    </span>
    """
  end
end
