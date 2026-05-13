defmodule FirmowidWeb.Billing.Utilities.Worksheet do
  @moduledoc """
  Shapes billing facts into a worksheet-oriented structure for billing views.
  """

  alias Firmowid.Ash.Billing.PlanCatalog

  @type usage_source :: %{
          required(:billing_plan) => PlanCatalog.plan(),
          required(:manual_external_invoices_count) => non_neg_integer(),
          required(:synced_bank_accounts_count) => non_neg_integer(),
          required(:active_non_owner_users_count) => non_neg_integer(),
          optional(atom()) => term()
        }

  @type usage_row_key ::
          :synced_bank_accounts | :active_non_owner_users | :manual_external_invoices

  @doc """
  Builds worksheet sections for a selected month.
  """
  @spec build(usage_source()) :: map()
  def build(source) do
    plan = source.billing_plan
    rules = PlanCatalog.plan!(plan)

    bank_row =
      usage_row(
        :synced_bank_accounts,
        "Konta bankowe",
        source.synced_bank_accounts_count,
        rules.synced_bank_accounts
      )

    employee_row =
      usage_row(
        :active_non_owner_users,
        "Pracownicy",
        source.active_non_owner_users_count,
        rules.active_non_owner_users
      )

    invoice_row =
      usage_row(
        :manual_external_invoices,
        "Faktury kosztowe spoza KSeF",
        source.manual_external_invoices_count,
        rules.manual_external_invoices
      )

    %{
      selected_plan: plan,
      selected_plan_label: plan_label(plan),
      base_fee_line: base_fee_line(rules),
      usage_rows: [bank_row, employee_row, invoice_row],
      suggestion_rows: suggestion_rows(source, rules),
      no_plan_note: no_plan_note(plan)
    }
  end

  @doc """
  Returns the human label for a plan.
  """
  @spec plan_label(PlanCatalog.plan()) :: String.t()
  def plan_label(:no_plan), do: "Brak planu"
  def plan_label(:start), do: "Start"
  def plan_label(:przedsiebiorca), do: "Przedsiębiorca"
  def plan_label(:firma), do: "Firma"

  defp usage_row(key, label, count, %{included_units: included_units}) do
    over_limit = max(count - included_units, 0)

    %{
      key: key,
      label: label,
      count: count,
      included_units: included_units,
      over_limit: over_limit,
      total_text: usage_total_text(count, included_units),
      usage_text: usage_text(count, included_units, over_limit),
      bar_width: usage_bar_width(count, included_units)
    }
  end

  defp suggestion_rows(%{billing_plan: :no_plan}, _rules), do: []

  defp suggestion_rows(source, rules) do
    Enum.reject(
      [
        bank_accounts_suggestion(source.synced_bank_accounts_count, rules.synced_bank_accounts),
        employees_suggestion(source.active_non_owner_users_count, rules.active_non_owner_users),
        external_invoices_suggestion(
          source.manual_external_invoices_count,
          rules.manual_external_invoices
        )
      ],
      &is_nil/1
    )
  end

  defp bank_accounts_suggestion(count, %{included_units: included, billing: %{unit_price_pln: unit_price}}) do
    over_limit = count - included

    if over_limit > 0 do
      total = Decimal.mult(unit_price, Decimal.new(over_limit))

      %{
        label: "Dodatkowe konta bankowe",
        detail: "#{over_limit} ponad limit × #{money_to_string(unit_price)} / mies.",
        amount: money_to_string(total)
      }
    end
  end

  defp bank_accounts_suggestion(_count, _rule), do: nil

  defp employees_suggestion(count, %{included_units: included, billing: %{unit_price_pln: unit_price}}) do
    over_limit = count - included

    if over_limit > 0 do
      total = Decimal.mult(unit_price, Decimal.new(over_limit))

      %{
        label: "Dodatkowi pracownicy",
        detail: "#{over_limit} ponad limit × #{money_to_string(unit_price)} / mies.",
        amount: money_to_string(total)
      }
    end
  end

  defp employees_suggestion(_count, _rule), do: nil

  defp external_invoices_suggestion(count, %{
         included_units: included,
         billing: %{pack_size: pack_size, pack_price_pln: pack_price}
       }) do
    over_limit = count - included

    if over_limit > 0 do
      packs = div(over_limit + pack_size - 1, pack_size)
      total = Decimal.mult(pack_price, Decimal.new(packs))

      %{
        label: "Nadwyżka faktur kosztowych spoza KSeF",
        detail:
          "#{over_limit} ponad limit. Pakiety rozliczeniowe: #{packs} × #{pack_size} za #{money_to_string(pack_price)}.",
        amount: money_to_string(total)
      }
    end
  end

  defp external_invoices_suggestion(_count, _rule), do: nil

  defp base_fee_line(%{plan: :no_plan}), do: nil

  defp base_fee_line(%{monthly_price_pln: monthly_price_pln}) do
    %{
      label: "Miesięczna opłata bazowa",
      amount: money_to_string(monthly_price_pln)
    }
  end

  defp no_plan_note(:no_plan),
    do: "Brak planu — pokazujemy wyłącznie surowe dane użycia bez automatycznych sugestii rozliczeniowych."

  defp no_plan_note(_plan), do: nil

  defp usage_total_text(count, included_units) when included_units > 0, do: "#{count} / #{included_units}"

  defp usage_total_text(count, _included_units), do: "#{count} użyte"

  defp usage_text(_count, included_units, over_limit) when included_units > 0 and over_limit > 0, do: "Limit przekroczony"

  defp usage_text(count, included_units, _over_limit) when included_units > 0,
    do: "#{max(included_units - count, 0)} pozostało"

  defp usage_text(count, _included_units, _over_limit) when count > 0, do: "Poza planem"
  defp usage_text(_count, _included_units, _over_limit), do: "Brak użycia"

  defp usage_bar_width(count, included_units) when included_units <= 0 and count <= 0, do: 0
  defp usage_bar_width(count, included_units) when included_units <= 0 and count > 0, do: 100

  defp usage_bar_width(count, included_units) do
    min(trunc(count / included_units * 100), 100)
  end

  defp money_to_string(amount) do
    :PLN
    |> Money.new(amount)
    |> Money.to_string!(no_fraction_if_integer: true)
  end
end
