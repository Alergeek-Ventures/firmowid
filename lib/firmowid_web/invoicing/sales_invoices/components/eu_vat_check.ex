defmodule FirmowidWeb.Invoicing.SalesInvoices.Components.EuVatCheck do
  @moduledoc """
  Review panel listing problems with an EU buyer's VAT number: structure, VIES
  registration and rates. Shows nothing when the number passes every check.

  Asks VIES once per buyer number, in the background, so a slow or unavailable
  registry never holds up the review.
  """
  use FirmowidWeb, :live_component

  alias Firmowid.Invoicing.CountryCodes
  alias Firmowid.Invoicing.EuVatNumber
  alias Firmowid.Invoicing.EuVatReview

  @impl true
  def update(%{invoice: invoice} = assigns, socket) do
    %{buyer_country: country, buyer_id: number} = invoice
    key = {country, number}

    socket =
      socket
      |> assign(assigns)
      |> assign(:applies?, EuVatReview.applies?(invoice))

    socket =
      cond do
        socket.assigns[:checked_key] == key or not socket.assigns.applies? ->
          socket

        # Like the periodic check, VIES is asked only about numbers that pass their country's rules.
        EuVatReview.number_rejected?(invoice) ->
          socket
          |> cancel_async(:registration)
          |> assign(checked_key: key, registration: nil)

        true ->
          socket
          |> assign(:checked_key, key)
          |> assign(:registration, :pending)
          |> start_async(:registration, fn -> EuVatReview.check_registration(country, number) end)
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:registration, {:ok, status}, socket), do: {:noreply, assign(socket, :registration, status)}

  def handle_async(:registration, {:exit, _reason}, socket), do: {:noreply, assign(socket, :registration, :unavailable)}

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :findings,
        if(assigns.applies?,
          do: EuVatReview.findings(assigns.invoice, assigns.registration),
          else: []
        )
      )

    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-title"}>
      <div :if={@findings != []} class="space-y-2">
        <h3 id={"#{@id}-title"} class="text-sm font-medium text-grey-700">
          {gettext("EU VAT check")}
        </h3>
        <ul class="space-y-2">
          <li
            :for={finding <- @findings}
            id={"#{@id}-#{finding.topic}-#{finding.code}"}
            class={[
              "flex items-start gap-2 rounded-lg p-3 text-sm",
              finding.level == :warning && "bg-rust-200 text-rust-700",
              finding.level == :error && "bg-brick-100 text-brick-700"
            ]}
          >
            <.level_icon level={finding.level} />
            <span>{text(finding, @invoice)}</span>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  attr :level, :atom, required: true

  defp level_icon(%{level: :warning} = assigns), do: ~H|<Lucideicons.alert_triangle class="mbs-0.5 size-4 shrink-0" />|

  defp level_icon(%{level: :error} = assigns), do: ~H|<Lucideicons.circle_x class="mbs-0.5 size-4 shrink-0" />|

  defp text(%{topic: :number, code: :format}, invoice),
    do:
      gettext(
        "The number does not match the %{country} format (%{pattern}). The invoice cannot be issued.",
        vars(invoice)
      )

  defp text(%{topic: :number, code: :checksum}, invoice),
    do: gettext("The number has an invalid %{country} check digit. The invoice cannot be issued.", vars(invoice))

  defp text(%{topic: :registration, code: :inactive}, _invoice),
    do: gettext("VIES does not confirm this number. Check it with the buyer before you rely on it.")

  defp text(%{topic: :rate, code: :domestic_rate}, _invoice),
    do:
      gettext(
        "Items use a Polish rate although the buyer has an EU VAT number. Check whether the buyer should account for VAT instead."
      )

  defp text(%{topic: :rate, code: :buyer_settles_unconfirmed}, _invoice),
    do:
      gettext(
        "With this rate the buyer accounts for VAT, which assumes a VAT-registered business. VIES does not confirm that. Keep other proof or reconsider the rate."
      )

  defp vars(invoice) do
    country = CountryCodes.normalize(invoice.buyer_country)
    [country: CountryCodes.country_name(country), pattern: EuVatNumber.pattern(country)]
  end
end
