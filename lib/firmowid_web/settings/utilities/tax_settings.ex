defmodule FirmowidWeb.Settings.Utilities.TaxSettings do
  @moduledoc """
  The labels of the tax settings and of their values, as the taxes card of the
  company settings offers them, and how the settings that the payments suggest
  differ from the saved year, for that card and the inbox item that sends the
  admin to it.
  """

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Cldr.Number
  alias Firmowid.Taxes
  alias Firmowid.Taxes.Partner
  alias Firmowid.Taxes.TaxYear

  @typedoc "A suggested setting next to the value the year has saved for it."
  @type difference :: %{setting: atom(), indicated: term(), saved: term()}

  @doc """
  The pending suggestions (`Firmowid.Taxes.pending_suggestions/3`) that
  contradict a value the year has saved. A setting the year does not have yet is
  no difference: its suggestion is a plain prefill. `tax_year` needs its
  partners loaded.
  """
  @spec differences([map()], TaxYear.t() | nil) :: [difference()]
  def differences(_pending, nil), do: []

  def differences(pending, tax_year) do
    Enum.flat_map(pending, fn %{setting: setting, value: value} ->
      # A saved `false` (sickness insurance) is a value too.
      case Taxes.saved_value(tax_year, setting) do
        nil -> []
        saved -> [%{setting: setting, indicated: value, saved: saved}]
      end
    end)
  end

  @doc "How the inbox sentence about the differences begins."
  @spec inbox_lead() :: String.t()
  def inbox_lead, do: gettext("According to the transfers –")

  @doc """
  The inbox sentence as plain text, for the inbox search: every difference as
  `Setting: saved → indicated`. Nil when nothing differs. The inbox shows it with
  `FirmowidWeb.Settings.Components.TaxDifferences`.
  """
  @spec summary([difference()]) :: String.t() | nil
  def summary([]), do: nil

  def summary(differences) do
    items =
      Enum.map_join(differences, "; ", fn difference ->
        "#{setting_label(difference.setting)}: #{value_label(difference.setting, difference.saved)} → " <>
          value_label(difference.setting, difference.indicated)
      end)

    inbox_lead() <> " " <> items
  end

  @doc "The name of a setting."
  @spec setting_label(atom()) :: String.t()
  def setting_label(:vat_period), do: gettext("VAT settlement")
  def setting_label(:cit_advances), do: "CIT"
  def setting_label(:income_tax), do: gettext("Income tax")
  def setting_label(:pit_advances), do: gettext("Income tax advances")
  def setting_label(:social_insurance), do: "ZUS"
  def setting_label(:voluntary_sickness), do: gettext("Sickness insurance")
  def setting_label(:lump_sum_rate), do: gettext("Lump sum rate")

  @doc "The label of a setting's value, as its field in the card shows it."
  @spec value_label(atom(), term()) :: String.t()
  def value_label(:vat_period, value), do: Keyword.fetch!(period_options(), value)
  def value_label(:pit_advances, value), do: Keyword.fetch!(period_options(), value)
  def value_label(:cit_advances, value), do: Keyword.fetch!(cit_advances_options(), value)
  def value_label(:income_tax, value), do: Keyword.fetch!(income_tax_options(), value)
  def value_label(:social_insurance, value), do: Keyword.fetch!(social_insurance_options(), value)
  def value_label(:voluntary_sickness, true), do: pgettext("sickness insurance", "On")
  def value_label(:voluntary_sickness, false), do: pgettext("sickness insurance", "Off")
  def value_label(:lump_sum_rate, value), do: percent(value)

  @doc "The options of a monthly or quarterly choice, as `value: label`."
  @spec period_options() :: keyword(String.t())
  def period_options, do: [monthly: pgettext("tax period", "Monthly"), quarterly: pgettext("tax period", "Quarterly")]

  @doc "The options of the CIT advances, as `value: label`."
  @spec cit_advances_options() :: keyword(String.t())
  def cit_advances_options do
    [
      monthly: pgettext("CIT advances", "Monthly advances"),
      quarterly: pgettext("tax period", "Quarterly"),
      simplified: pgettext("CIT advances", "Simplified")
    ]
  end

  @doc "The options of the owner's income tax, as `value: label`."
  @spec income_tax_options() :: keyword(String.t())
  def income_tax_options do
    [
      tax_scale: pgettext("income tax", "Tax scale"),
      flat_tax: gettext("Flat tax 19%"),
      lump_sum: pgettext("income tax", "Lump sum")
    ]
  end

  @doc "The options of the owner's ZUS, as `value: label`."
  @spec social_insurance_options() :: keyword(String.t())
  def social_insurance_options do
    [
      start_relief: gettext("Start relief"),
      preferential: pgettext("ZUS", "Preferential"),
      small_plus: "Mały ZUS Plus",
      full: pgettext("ZUS", "Full"),
      none: gettext("No social contributions")
    ]
  end

  @doc "The lump sum rates, as `{label, value}` for a select."
  @spec lump_sum_rate_options() :: [{String.t(), String.t()}]
  def lump_sum_rate_options, do: Enum.map(Partner.lump_sum_rates(), &{percent(&1), Decimal.to_string(&1)})

  defp percent(value), do: value |> Decimal.normalize() |> Number.to_string!() |> Kernel.<>("%")
end
