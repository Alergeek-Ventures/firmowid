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
  end

  resources do
    resource TaxYear do
      define :get_tax_year, action: :read, get_by: [:year]
      define :list_tax_years, action: :list
      define :create_tax_year, action: :create
      define :update_tax_year, action: :update
      define :suggest_tax_settings, action: :suggest_settings, args: [:year]
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
