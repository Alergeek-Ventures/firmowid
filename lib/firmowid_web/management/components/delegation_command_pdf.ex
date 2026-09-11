defmodule FirmowidWeb.Management.Components.DelegationCommandPdf do
  @moduledoc "Printable business trip order PDF template."

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Delegations.Utilities.DelegationPresentation

  attr :employee, :map, required: true
  attr :delegation, :map, required: true
  attr :footer_logo_data_uri, :string, required: true

  def command(assigns) do
    ~H"""
    <div class="font-lexend relative mx-auto flex h-[297mm] w-[210mm] flex-col border bg-white p-8 text-[10px]">
      <header class="flex items-start justify-between">
        <div>
          <h1 class="text-[14px] font-medium">
            Polecenie wyjazdu służbowego nr <strong>{@delegation.id}</strong>
          </h1>
          <p class="mt-1">
            z dnia <strong>{DelegationPresentation.format_date(@delegation.inserted_at)}</strong>
          </p>
        </div>
        <div class="bg-grey-200 flex size-[34px] items-center justify-center text-[8px]">
          logo firmy
        </div>
      </header>

      <.section title="DANE PRACOWNIKA">
        <.row label="Imię i nazwisko:"><strong>{@employee.name || @employee.email}</strong></.row>
        <.row label="Stanowisko:">{@employee.position || "—"}</.row>
      </.section>

      <.section title="SZCZEGÓŁY DELEGACJI">
        <.row label="Termin podróży:">
          {DelegationPresentation.format_range(@delegation.start_date, @delegation.end_date)}
        </.row>
        <.row label="Miejsce podróży:">{@delegation.destination}</.row>
        <.row label="Środek lokomocji:">{transport_types(@delegation.transport_types)}</.row>
        <.row label="Cel podróży:">{@delegation.purpose}</.row>
      </.section>

      <.section title="PRZYZNANA ZALICZKA">
        <.row label="Kwota:">
          <strong>{DelegationPresentation.format_money(@delegation.advance_amount)}</strong>
        </.row>
      </.section>

      <div class="mt-[150px] ml-auto w-[200px] text-center text-[8px]">
        <div class="border-grey-200 border-b border-dotted pb-1" />
        <p class="mt-1">Podpis pracodawcy</p>
      </div>

      <footer class="mt-auto flex items-center gap-2 text-[8px]">
        <img src={@footer_logo_data_uri} class="size-6 object-contain" />
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
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section class="border-grey-200 mt-5 border-t pt-3">
      <h2 class="text-grey-600 mb-2 text-[8px] font-bold">{@title}</h2>
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
      &%{railway: "kolej", airplane: "samolot", bus: "autobus", other: "inny"}[&1]
    )
  end
end
