defmodule Firmowid.Taxes do
  @moduledoc """
  Ash domain for how the company is taxed: per tax year, the VAT period, CIT
  settings, the ZUS accident insurance rate and the owners who pay their own
  income tax and ZUS on its profit.
  """
  use Ash.Domain, extensions: [AshAi]

  alias Firmowid.Taxes.TaxYear

  tools do
    tool :list_tax_years, TaxYear, :list do
      annotations title: "List tax settings",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "List how the company is taxed in each saved year: legal_form, the organization's current " <>
                    "legal form (sole_proprietorship, " <>
                    "civil_partnership or limited_company), vat_period (nil outside VAT), the CIT rate and advances " <>
                    "of a limited company, the accident insurance rate in percent, and the partners who pay their " <>
                    "own income tax and ZUS: member_id, profit_share in percent, income_tax, lump_sum_rate, " <>
                    "pit_advances, social_insurance and voluntary_sickness. An empty list means nothing is set yet. " <>
                    "The settings are entered and confirmed by the accountant in the company settings. Changes nothing."

      load [:legal_form, :partners]
    end

    tool :suggest_tax_settings, TaxYear, :suggest_settings do
      annotations title: "Suggest tax settings",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "Suggest a year's vat_period, cit_advances, income_tax and pit_advances from the transfers to " <>
                    "the company's tax micro-account: the period (month or quarter) and form symbol in their titles. " <>
                    "Each suggestion has the year whose transfers it comes from (the year before when the year has " <>
                    "none) and how many transfers it counts. Income tax suggestions only fit a sole proprietorship, " <>
                    "whose owner pays from the company account. Not binding: say they are based on the transactions; " <>
                    "an admin confirms them by saving the year in the company settings. Changes nothing."
    end

    tool :forecast_taxes, TaxYear, :forecast do
      annotations title: "Forecast taxes and ZUS",
                  read_only_hint: true,
                  destructive_hint: false,
                  open_world_hint: false

      description "Forecast a year's tax and ZUS payments from the saved tax settings and the invoices and bank " <>
                    "transactions Firmowid has. An estimate to plan cash, not a tax return: say so. One item per " <>
                    "period: kind, period, period_start, period_end, amount in PLN, due_date, description, " <>
                    "member_id and details, the figures the amount comes from; use details to explain an amount. " <>
                    "The period that is still running includes the typical rest of the period, taken from the " <>
                    "previous three months, so its amount is for the whole period and not only for the " <>
                    "documents dated so far; details projected_output_vat and projected_input_vat (vat) and " <>
                    "projected_revenue and projected_costs (cit, pit) say how much of the figure is that " <>
                    "expectation (zero for a period without any). " <>
                    "vat: for a VAT payer with a saved vat_period; details output_vat, input_vat, carried_over, " <>
                    "refunded. carried_over is the surplus input VAT from earlier periods, deducted first, " <>
                    "already lowered by refunded: the VAT refunds from a tax office (incoming transfers from " <>
                    "Urząd Skarbowy titled with VAT) booked in the period. A period with more input than " <>
                    "output VAT pays 0 and carries the surplus forward. " <>
                    "cit: advances of a limited company with a saved CIT rate and advance form (none for " <>
                    "simplified advances); cumulative from 1 January: details revenue, costs, income, tax " <>
                    "(on the whole income so far), advances_before, rate in percent. " <>
                    "pit and zus: per partner of a sole proprietorship or civil partnership, member_id is the " <>
                    "partner (see list_tax_years); pit details revenue, costs, income (the partner's share, " <>
                    "cumulative), social_deducted, health_deducted, tax_base, tax, advances_before, income_tax, " <>
                    "rate (nil on the tax scale), rates_year; zus is monthly, details pension, disability, " <>
                    "accident, sickness, labour_fund, health, social_base, health_base, rates_year. " <>
                    "vat and cit details also have cost_invoices_without_vat, the cost invoices up to the period " <>
                    "without a VAT amount: they bring no input VAT and count at their gross amount in CIT costs. " <>
                    "Simplifications: sales outside invoices are not counted; costs are cost invoices net of VAT, " <>
                    "salary transfers and skipped outgoing transfers that the analysis put into a cost " <>
                    "category (not taxes, ZUS of owners or transfers between own accounts; unclassified " <>
                    "transfers are not costs); no depreciation, reliefs or losses of earlier years; " <>
                    "contributions use the rates_year figures and count in the month they are for; VAT " <>
                    "surplus is carried forward and lowered by refunds, not refunded itself. Changes nothing."
    end
  end

  resources do
    resource TaxYear do
      define :get_tax_year, action: :read, get_by: [:year]
      define :list_tax_years, action: :list
      define :create_tax_year, action: :create
      define :update_tax_year, action: :update
      define :suggest_tax_settings, action: :suggest_settings, args: [:year]
      define :forecast_taxes, action: :forecast, args: [:year]
      define :save_tax_forecasts, action: :save_forecasts
    end

    resource Firmowid.Taxes.Partner
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  @doc """
  Returns the suggestions from `suggest_tax_settings/2` that wait for an admin's
  confirmation: those for settings the year does not have yet, and those that
  contradict the saved year with transfers synced after it was last saved. Saving
  the year confirms them, so a contradiction comes back only with new transfers.
  Only the settings of the legal form and VAT status count; `tax_year` needs its
  partners loaded.
  """
  @spec pending_suggestions([map()], TaxYear.t() | nil, Firmowid.Core.Organization.t()) :: [map()]
  def pending_suggestions(suggestions, tax_year, organization) do
    Enum.filter(suggestions, &(applies?(&1.setting, organization) and pending?(&1, tax_year)))
  end

  defp applies?(:vat_period, organization), do: organization.is_vat_payer
  defp applies?(:cit_advances, organization), do: organization.legal_form == :limited_company

  # The owner of a sole proprietorship pays income tax from the company account; partners of a
  # civil partnership usually pay their own from private ones, so their transfers say nothing.
  defp applies?(_income_tax, organization), do: organization.legal_form == :sole_proprietorship

  defp pending?(_suggestion, nil), do: true

  defp pending?(suggestion, tax_year) do
    case saved_value(tax_year, suggestion.setting) do
      nil ->
        true

      value ->
        value != suggestion.value and
          DateTime.after?(suggestion.latest_transfer_at, tax_year.updated_at)
    end
  end

  defp saved_value(tax_year, setting) when setting in [:vat_period, :cit_advances], do: Map.fetch!(tax_year, setting)

  # A year saved under another legal form has no owner yet.
  defp saved_value(%TaxYear{partners: [owner]}, setting), do: Map.fetch!(owner, setting)
  defp saved_value(%TaxYear{partners: _partners}, _setting), do: nil
end
