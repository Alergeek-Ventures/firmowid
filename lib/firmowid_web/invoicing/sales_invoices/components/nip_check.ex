defmodule FirmowidWeb.Invoicing.SalesInvoices.Components.NipCheck do
  @moduledoc """
  Review panel about a Polish buyer's NIP that belongs to a closed business, or that
  no register we can search by NIP confirms. KSeF delivers the invoice to whoever
  holds the NIP, so a typo sends it to the wrong company. Shows nothing otherwise.

  Asks the registers (`NipRegistration`) once per buyer NIP, in the background,
  so a slow or unavailable register never holds up the review. Only warns about a
  register's explicit answer (struck off or deregistered); an unconfirmed NIP gets
  a neutral note, since a KRS company outside VAT is in no register searchable by
  NIP. The invoice can always be issued.
  """
  use FirmowidWeb, :live_component

  alias Firmowid.Core.Nip
  alias Firmowid.Invoicing.CountryCodes
  alias Firmowid.Invoicing.NipRegistration

  @impl true
  def mount(socket), do: {:ok, assign(socket, checked_nip: nil, registration: nil)}

  @impl true
  def update(%{invoice: invoice} = assigns, socket) do
    checked_nip = socket.assigns.checked_nip
    socket = assign(socket, assigns)

    socket =
      case buyer_nip(invoice) do
        nil ->
          socket |> cancel_async(:registration) |> assign(checked_nip: nil, registration: nil)

        ^checked_nip ->
          socket

        nip ->
          socket
          |> assign(checked_nip: nip, registration: nil)
          |> start_async(:registration, fn -> NipRegistration.check(nip) end)
      end

    {:ok, socket}
  end

  @impl true
  def handle_async(:registration, {:ok, :unavailable}, socket), do: {:noreply, assign(socket, :registration, nil)}

  def handle_async(:registration, {:ok, result}, socket), do: {:noreply, assign(socket, :registration, result)}

  def handle_async(:registration, {:exit, _reason}, socket), do: {:noreply, assign(socket, :registration, nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-title"}>
      <div
        :if={match?({status, _registers} when status in [:closed, :unconfirmed], @registration)}
        class="space-y-2"
      >
        <h3 id={"#{@id}-title"} class="text-sm font-medium text-grey-700">
          {gettext("NIP check")}
        </h3>
        <p
          :if={match?({:closed, _registers}, @registration)}
          id={"#{@id}-closed"}
          class="flex items-start gap-2 rounded-lg bg-rust-200 p-3 text-sm text-rust-700"
        >
          <Lucideicons.alert_triangle class="mbs-0.5 size-4 shrink-0" />
          <span>{text(@registration)}</span>
        </p>
        <p
          :if={match?({:unconfirmed, _registers}, @registration)}
          id={"#{@id}-unconfirmed"}
          class="flex items-start gap-2 rounded-lg bg-grey-50 p-3 text-sm text-grey-700"
        >
          <Lucideicons.info class="mbs-0.5 size-4 shrink-0" />
          <span>{text(@registration)}</span>
        </p>
      </div>
    </section>
    """
  end

  # A NIP that fails its checksum is rejected by the invoice validation already.
  defp buyer_nip(%{buyer_id: nip} = invoice) when is_binary(nip) do
    if CountryCodes.tax_id_type(invoice.buyer_country, invoice.buyer_pesel, invoice.buyer_type) ==
         :nip and
         Nip.valid?(nip),
       do: nip
  end

  defp buyer_nip(_invoice), do: nil

  defp text({:closed, %{krs: :struck_off}}),
    do: gettext("KRS shows this company as struck off. Confirm the details with the buyer before you issue the invoice.")

  defp text({:closed, _registers}),
    do:
      gettext(
        "CEIDG shows this business as deregistered. Confirm the details with the buyer before you issue the invoice."
      )

  defp text({:unconfirmed, _registers}),
    do:
      gettext(
        "Neither the VAT white list nor CEIDG lists this NIP. That is normal for a KRS company outside VAT, since KRS cannot be searched by NIP. KSeF delivers the invoice to whoever holds the NIP, so make sure the number is right."
      )
end
