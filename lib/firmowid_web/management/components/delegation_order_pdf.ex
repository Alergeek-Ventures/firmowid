defmodule FirmowidWeb.Management.Components.DelegationOrderPdf do
  @moduledoc "Printable business trip order PDF template."

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Delegations.Utilities.DelegationPresentation

  attr :employee, :map, required: true
  attr :employment_contract, :map, required: true
  attr :delegation, :map, required: true
  attr :footer_logo_data_uri, :string, required: true

  def order(assigns) do
    ~H"""
    <div class="font-lexend relative mx-auto box-content h-248 w-182.5 bg-white p-8 text-[10px]">
      <header class="flex items-start justify-between">
        <div>
          <h1 class="text-sm font-medium">
            Polecenie wyjazdu służbowego nr <strong>{@delegation.reference}</strong>
          </h1>
          <p class="mt-1">
            z dnia <strong>{DelegationPresentation.format_date(@delegation.inserted_at)}</strong>
          </p>
        </div>
      </header>

      <.section title="Dane pracownika" separated={false}>
        <.row label="Imię i nazwisko:"><strong>{@employee.name || @employee.email}</strong></.row>
        <.row label="Stanowisko:">
          {(@employment_contract && @employment_contract.position) || "—"}
        </.row>
      </.section>

      <.section title="Szczegóły delegacji">
        <.row label="Termin podróży:">
          {DelegationPresentation.format_range(@delegation.start_date, @delegation.end_date)}
        </.row>
        <.row label="Miejsce podróży:">{@delegation.destination}</.row>
        <.row label="Środek lokomocji:">{transport_types(@delegation.transport_types)}</.row>
        <.row label="Cel podróży:">{@delegation.purpose}</.row>
      </.section>

      <.section title="Przyznana zaliczka">
        <.row label="Kwota:">
          <strong>{DelegationPresentation.format_money(@delegation.advance_amount)}</strong>
        </.row>
      </.section>

      <div class="mt-37.5 ml-auto w-50 text-center text-[8px]">
        <div class="border-grey-200 border-b border-dotted pb-1" />
        <p class="mt-1">Podpis pracodawcy</p>
      </div>

      <footer class="absolute bottom-8 left-8 flex items-end gap-2 text-[8px]/2.5">
        <div class="h-13.5 w-8.25 overflow-hidden">
          <img
            src={@footer_logo_data_uri}
            class="h-14.5 w-auto max-w-none object-contain object-top"
          />
        </div>
        <div>
          <p>Dokument 1/<span class="text-grey-400">2</span></p>
          <p>
            Dokument wygenerowany za pomocą
            <.link kind="unstyled" external="https://firmowid.pl" class="font-bold">
              Firmowid.pl
            </.link>
          </p>
        </div>
      </footer>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :separated, :boolean, default: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section class={["mt-5 pt-3", @separated && "border-grey-200 border-t"]}>
      <h2 class="text-grey-600 mb-2 text-[8px] font-bold uppercase">{@title}</h2>
      <div class="space-y-1">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp row(assigns) do
    ~H"""
    <div class="grid grid-cols-[150px_1fr]">
      <span>{@label}</span>
      <span class="text-[10px]">{render_slot(@inner_block)}</span>
    </div>
    """
  end

  defp transport_types(types) do
    Enum.map_join(
      types,
      ", ",
      &%{
        railway: "kolej",
        airplane: "samolot",
        bus: "autobus",
        public_transport: "komunikacja publiczna",
        other: "inny"
      }[&1]
    )
  end
end
