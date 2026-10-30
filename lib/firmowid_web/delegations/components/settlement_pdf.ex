defmodule FirmowidWeb.Delegations.Components.SettlementPdf do
  @moduledoc "Canonical printable two-page delegation settlement document."

  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Delegations.Utilities.DelegationPresentation
  alias FirmowidWeb.Delegations.Utilities.SettlementPresentation

  attr :document, :map, required: true
  attr :footer_logo_data_uri, :string, required: true

  @doc "Renders the settlement as exactly two A4 pages."
  @spec document(map()) :: Phoenix.LiveView.Rendered.t()
  def document(assigns) do
    ~H"""
    <div class="font-lexend bg-grey-100 text-[9px] text-black print:bg-white">
      <.page page={1} footer_logo_data_uri={@footer_logo_data_uri}>
        <.pdf_header document={@document} />
        <.employee_details document={@document} />
        <.trip_details document={@document} />
        <.expense_table title="Transport" expenses={@document.transport_expenses} />
        <.expense_table title="Noclegi" expenses={@document.accommodation_expenses} />
      </.page>
      <.page page={2} footer_logo_data_uri={@footer_logo_data_uri}>
        <.expense_table title="Inne wydatki" expenses={@document.other_expenses} />
        <.per_diem :if={@document.per_diem} document={@document} />
        <.totals document={@document} />
        <section class="mt-7">
          <h2 class="font-bold text-grey-600 uppercase">
            Załączniki ({length(@document.attachments)})
          </h2>
          <ol class="mt-3 grid list-decimal grid-cols-2 gap-x-8 gap-y-1 pl-4">
            <li :for={attachment <- @document.attachments}>
              {attachment.original_filename}
            </li>
          </ol>
        </section>
        <div class="mt-20 grid grid-cols-2 gap-14 text-center">
          <.signature label="Podpis pracownika składającego rozliczenie" />
          <.signature label="Podpis osoby zatwierdzającej do wypłaty" />
        </div>
      </.page>
    </div>
    """
  end

  attr :page, :integer, required: true
  attr :footer_logo_data_uri, :string, required: true
  slot :inner_block, required: true

  defp page(assigns) do
    ~H"""
    <article class="relative mx-auto box-border h-[297mm] w-[210mm] break-after-page bg-white p-[12mm] last:break-after-auto">
      {render_slot(@inner_block)}
      <footer class="absolute inset-x-[12mm] bottom-[10mm] flex items-end justify-between text-[8px]">
        <div class="flex items-end gap-2">
          <img src={@footer_logo_data_uri} class="h-10 w-auto" />
          <p>
            Dokument wygenerowany za pomocą
            <.link kind="unstyled" external="https://firmowid.pl" class="font-bold">Firmowid.pl</.link>
          </p>
        </div>
        <p>strona {@page}/2</p>
      </footer>
    </article>
    """
  end

  attr :document, :map, required: true

  defp pdf_header(assigns) do
    ~H"""
    <header class="flex items-start justify-between">
      <div>
        <h1 class="text-sm">
          Rozliczenie delegacji nr
          <strong>{@document.delegation.settlement_sequence}/{@document.delegation.settlement_year}</strong>
        </h1>
        <p class="mt-1">
          z dnia <strong>{format_datetime_date(@document.delegation.settlement_prepared_at)}</strong>
          <span class="mx-2 text-grey-300">|</span>
          miesiąc rozliczeniowy: {billing_month(@document.delegation.billing_month)}
        </p>
      </div>
      <div class="flex items-center gap-3 text-right">
        <div>
          <p class="font-semibold">{@document.organization.name}</p>
          <p class="max-w-48 text-grey-600">{@document.organization.address || "—"}</p>
        </div>
        <div class="flex size-12 items-center justify-center bg-grey-100">
          <img
            :if={@document.organization_logo_data_uri}
            src={@document.organization_logo_data_uri}
            class="max-h-12 max-w-12"
          />
          <span :if={!@document.organization_logo_data_uri} class="text-grey-500">logo firmy</span>
        </div>
      </div>
    </header>
    """
  end

  attr :document, :map, required: true

  defp employee_details(assigns) do
    ~H"""
    <.section title="Dane pracownika">
      <div class="grid grid-cols-2 gap-8">
        <.data_row
          label="Imię i nazwisko"
          value={@document.employee.name || to_string(@document.employee.user.email)}
        />
        <.data_row label="Stanowisko" value={position(@document.employment_contract)} />
        <.data_row label="Adres" value={@document.employee.residence_address || "—"} />
      </div>
    </.section>
    """
  end

  attr :document, :map, required: true

  defp trip_details(assigns) do
    ~H"""
    <.section title="Przebieg delegacji">
      <div class="grid grid-cols-2 gap-x-8 gap-y-2">
        <.data_row label="Miejsce" value={@document.delegation.destination} />
        <.data_row
          label="Termin"
          value={
            DelegationPresentation.format_range(
              @document.delegation.start_date,
              @document.delegation.end_date
            )
          }
        />
        <.data_row label="Cel podróży" value={@document.delegation.purpose} />
        <.data_row label="Pobrana zaliczka" value={money(@document.delegation.advance_amount)} />
      </div>
      <p :if={@document.delegation.date_change_reason} class="mt-3 rounded bg-grey-100 p-2">
        <strong>Zmiana terminu:</strong> {@document.delegation.date_change_reason}
      </p>
    </.section>
    """
  end

  attr :document, :map, required: true

  defp per_diem(assigns) do
    ~H"""
    <.section title={gettext("Per diem and lump sums")}>
      <div class="grid grid-cols-2 gap-x-8 gap-y-2">
        <.data_row
          label={gettext("Trip")}
          value={time_range(@document.delegation.trip_started_at, @document.delegation.trip_ended_at)}
        />
        <.data_row
          :if={@document.delegation.destination_country != "PL"}
          label={gettext("Time abroad")}
          value={
            time_range(@document.delegation.abroad_started_at, @document.delegation.abroad_ended_at)
          }
        />
        <.data_row
          label={gettext("Meals provided")}
          value={
            gettext("breakfasts: %{breakfasts}, lunches: %{lunches}, dinners: %{dinners}",
              breakfasts: @document.delegation.provided_breakfasts,
              lunches: @document.delegation.provided_lunches,
              dinners: @document.delegation.provided_dinners
            )
          }
        />
      </div>
      <div class="mt-4 space-y-2 border-t border-grey-200 pt-3">
        <div :for={line <- @document.per_diem.lines} class="flex justify-between gap-4">
          <span>{DelegationPresentation.per_diem_line_label(line, @document.delegation)}</span>
          <span class="font-semibold whitespace-nowrap">{money(line.amount)}</span>
        </div>
      </div>
    </.section>
    """
  end

  defp time_range(started_at, ended_at),
    do: "#{Calendar.strftime(started_at, "%d.%m.%Y %H:%M")} – #{Calendar.strftime(ended_at, "%d.%m.%Y %H:%M")}"

  attr :title, :string, required: true
  attr :expenses, :list, required: true

  defp expense_table(assigns) do
    ~H"""
    <.section title={@title}>
      <table class="w-full table-fixed border-collapse text-left">
        <thead class="text-[7px] text-grey-500 uppercase">
          <tr class="border-b border-grey-200">
            <th class="w-8 py-2">Lp.</th><th class="py-2">Opis / trasa</th><th class="w-32 py-2">
              Dokument
            </th><th class="w-24 py-2 text-right">Kwota</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={{expense, index} <- Enum.with_index(@expenses, 1)}
            class="border-b border-grey-100 align-top"
          >
            <td class="py-2">{index}.</td>
            <td class="py-2 pr-3">{expense_description(expense)}</td>
            <td class="py-2 pr-3">{expense.document_number}</td>
            <td class="py-2 text-right font-semibold">
              {money(SettlementPresentation.settlement_amount(expense))}
            </td>
          </tr>
          <tr :if={@expenses == []}>
            <td colspan="4" class="py-3 text-grey-500">Brak wydatków.</td>
          </tr>
        </tbody>
      </table>
    </.section>
    """
  end

  attr :document, :map, required: true

  defp totals(assigns) do
    ~H"""
    <section class="mt-8 ml-auto w-80 space-y-2">
      <.total_row label="Transport" value={@document.transport_total} />
      <.total_row label="Noclegi" value={@document.accommodation_total} />
      <.total_row label="Inne wydatki" value={@document.other_total} />
      <.total_row
        :if={@document.per_diem}
        label={gettext("Per diem")}
        value={@document.per_diem.per_diem}
      />
      <.total_row
        :if={@document.per_diem && !Money.zero?(@document.per_diem.lump_sums)}
        label={gettext("Lump sums")}
        value={@document.per_diem.lump_sums}
      />
      <div class="border-y border-grey-200 py-3">
        <.total_row label="Razem koszty delegacji" value={@document.total} strong />
        <.total_row label="Pobrana zaliczka" value={@document.delegation.advance_amount} />
      </div>
      <.total_row label={@document.balance_label} value={@document.balance} strong />
    </section>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <section class="mt-7">
      <h2 class="mb-3 font-bold text-grey-600 uppercase">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp data_row(assigns) do
    ~H"""
    <div><span class="text-grey-500">{@label}:</span> <strong>{@value}</strong></div>
    """
  end

  attr :label, :string, required: true
  attr :value, Money, required: true
  attr :strong, :boolean, default: false

  defp total_row(assigns) do
    ~H"""
    <div class={["flex justify-between gap-4", @strong && "font-bold"]}>
      <span>{@label}</span><span>{money(@value)}</span>
    </div>
    """
  end

  attr :label, :string, required: true

  defp signature(assigns) do
    ~H"""
    <div>
      <div class="h-16 border-b border-dotted border-grey-400" /><p class="mt-2">{@label}</p>
    </div>
    """
  end

  defp money(value), do: DelegationPresentation.format_money(value)
  defp position(nil), do: "—"
  defp position(contract), do: contract.position || "—"
  defp format_datetime_date(nil), do: "—"

  defp format_datetime_date(datetime), do: datetime |> DateTime.to_date() |> DelegationPresentation.format_date()

  defp billing_month(date) do
    month =
      Enum.at(
        ~w(styczeń luty marzec kwiecień maj czerwiec lipiec sierpień wrzesień październik listopad grudzień),
        date.month - 1
      )

    "#{month} #{date.year}"
  end

  defp expense_description(%{kind: :transport, details: %{trips: trips}}) do
    trips
    |> Enum.map_join(", ", fn trip -> "#{trip.departure_city} → #{trip.arrival_city}" end)
    |> empty_fallback("Transport")
  end

  defp expense_description(%{kind: :accommodation, details: details}),
    do: details.description || details.locality || "Nocleg"

  defp expense_description(%{kind: :other, details: details}), do: details.description || "Inny wydatek"

  defp expense_description(_expense), do: "—"
  defp empty_fallback("", fallback), do: fallback
  defp empty_fallback(value, _fallback), do: value
end
