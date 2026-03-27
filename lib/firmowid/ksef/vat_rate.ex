defmodule Firmowid.Ksef.VatRate do
  @moduledoc """
  VAT rate codes per KSeF FA(3) TStawkaPodatku specification.

  This module is the single source of truth for VAT rate validation,
  conversion, and display across the application.

  ## KSeF Valid Rates

  - Numeric: `23`, `22`, `8`, `7`, `5`, `4`, `3`
  - Zero rates: `0 KR` (domestic), `0 WDT` (EU goods), `0 EX` (export)
  - Special: `zw` (exempt), `oo` (reverse charge)
  - Not subject: `np I` (outside Poland), `np II` (EU B2B services)

  ## Context-Aware Selection

  The `available_rates/2` function returns appropriate rates based on
  buyer country and ID type:

  - Polish buyers: dropdown with `23`, `8`, `5`, `zw`
  - EU B2B (has EU VAT ID): fixed `np II`
  - Non-EU: fixed `np I`
  - Reverse charge: handled separately (auto `oo`)
  """
  alias Firmowid.SalesInvoices.CountryCodes

  # All valid KSeF codes per FA(3) XSD TStawkaPodatku
  @all_valid_rates [
    "23",
    "22",
    "8",
    "7",
    "5",
    "4",
    "3",
    "0 KR",
    "0 WDT",
    "0 EX",
    "zw",
    "oo",
    "np I",
    "np II"
  ]

  # Rates selectable in UI for Polish buyers (ordered by commonality, zw last)
  @domestic_rates ["23", "8", "5", "zw"]

  @doc """
  Returns list of all valid KSeF VAT rate codes.
  """
  @spec valid_rates() :: [String.t()]
  def valid_rates, do: @all_valid_rates

  @doc """
  Checks if the given rate is a valid KSeF VAT rate code.

  ## Examples

      iex> VatRate.valid?("23")
      true

      iex> VatRate.valid?("np II")
      true

      iex> VatRate.valid?("25")
      false
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(rate), do: rate in @all_valid_rates

  @doc """
  Returns available VAT rates based on buyer context.

  Returns:
  - `{:select, rates, default}` - show dropdown with rates, pre-select default
  - `{:fixed, rate}` - auto-select this rate, show as read-only

  Note: Reverse charge (`oo`) is handled separately via `is_reverse_charge` flag,
  not through this function.

  ## Examples

      iex> VatRate.available_rates("PL", :nip)
      {:select, ["23", "8", "5", "zw"], "23"}

      iex> VatRate.available_rates("DE", :eu_vat)
      {:fixed, "np II"}

      iex> VatRate.available_rates("US", :other)
      {:fixed, "np I"}
  """
  @spec available_rates(String.t(), atom()) :: {:select, [String.t()], String.t()} | {:fixed, String.t()}
  def available_rates("PL", _id_type), do: {:select, @domestic_rates, "23"}

  def available_rates(country, :eu_vat) do
    if CountryCodes.eu_country?(country) do
      {:fixed, "np II"}
    else
      available_rates_non_eu(country)
    end
  end

  def available_rates(country, _id_type) do
    if CountryCodes.eu_country?(country) do
      # EU consumer without VAT ID - Polish VAT applies
      {:select, @domestic_rates, "23"}
    else
      available_rates_non_eu(country)
    end
  end

  defp available_rates_non_eu(_country) do
    # Non-EU country
    {:fixed, "np I"}
  end

  @doc """
  Returns the numeric value of a VAT rate for calculations.

  Non-numeric rates (`zw`, `oo`, `np I`, `np II`) return `Decimal.new(0)`
  since they don't add VAT to the price.

  ## Examples

      iex> VatRate.to_numeric("23")
      Decimal.new(23)

      iex> VatRate.to_numeric("np II")
      Decimal.new(0)
  """
  @spec to_numeric(String.t()) :: Decimal.t()
  def to_numeric("23"), do: Decimal.new(23)
  def to_numeric("22"), do: Decimal.new(22)
  def to_numeric("8"), do: Decimal.new(8)
  def to_numeric("7"), do: Decimal.new(7)
  def to_numeric("5"), do: Decimal.new(5)
  def to_numeric("4"), do: Decimal.new(4)
  def to_numeric("3"), do: Decimal.new(3)
  # All other rates (0 KR, 0 WDT, 0 EX, zw, oo, np I, np II) have 0% VAT
  def to_numeric(_), do: Decimal.new(0)

  @doc """
  Returns display label for a VAT rate.

  ## Examples

      iex> VatRate.label("23")
      "23%"

      iex> VatRate.label("zw")
      "zw (zwolnione)"

      iex> VatRate.label("np II")
      "np II (usługi B2B dla UE)"
  """
  @spec label(String.t()) :: String.t()
  def label("23"), do: "23%"
  def label("22"), do: "22%"
  def label("8"), do: "8%"
  def label("7"), do: "7%"
  def label("5"), do: "5%"
  def label("4"), do: "4%"
  def label("3"), do: "3%"
  def label("0 KR"), do: "0% (krajowa)"
  def label("0 WDT"), do: "0% (WDT)"
  def label("0 EX"), do: "0% (eksport)"
  def label("zw"), do: "zw (zwolnione)"
  def label("oo"), do: "oo (odwrotne obciążenie)"
  def label("np I"), do: "np I (poza terytorium kraju)"
  def label("np II"), do: "np II (usługi B2B dla UE)"
  def label(rate), do: rate

  @doc """
  Returns short display label for a VAT rate (acronym only, no description).

  ## Examples

      iex> VatRate.short_label("23")
      "23%"

      iex> VatRate.short_label("zw")
      "zw"

      iex> VatRate.short_label("np II")
      "np II"
  """
  @spec short_label(String.t()) :: String.t()
  def short_label("23"), do: "23%"
  def short_label("22"), do: "22%"
  def short_label("8"), do: "8%"
  def short_label("7"), do: "7%"
  def short_label("5"), do: "5%"
  def short_label("4"), do: "4%"
  def short_label("3"), do: "3%"
  def short_label("0 KR"), do: "0%"
  def short_label("0 WDT"), do: "0%"
  def short_label("0 EX"), do: "0%"
  def short_label("zw"), do: "zw"
  def short_label("oo"), do: "oo"
  def short_label("np I"), do: "np I"
  def short_label("np II"), do: "np II"
  def short_label(rate), do: rate

  @doc """
  Returns options for Phoenix select input.

  ## Examples

      iex> VatRate.select_options(["23", "8"])
      [{"23%", "23"}, {"8%", "8"}]
  """
  @spec select_options([String.t()]) :: [{String.t(), String.t()}]
  def select_options(rates) do
    Enum.map(rates, &{label(&1), &1})
  end

  @doc """
  Returns options for Phoenix select input with short labels (acronyms only).

  ## Examples

      iex> VatRate.select_options_short(["23", "zw"])
      [{"23%", "23"}, {"zw", "zw"}]
  """
  @spec select_options_short([String.t()]) :: [{String.t(), String.t()}]
  def select_options_short(rates) do
    Enum.map(rates, &{short_label(&1), &1})
  end

  @doc """
  Derives the VAT summary type from a rate code.

  Used by `InvoiceRenderer.calculate_vat_summary/1` to group items correctly
  for KSeF XML generation.

  ## Types

  - `:standard` - numeric rates (23, 22, 8, 7, 5, 4, 3)
  - `:zero_domestic` - 0 KR
  - `:zero_wdt` - 0 WDT
  - `:zero_export` - 0 EX
  - `:exempt` - zw
  - `:reverse_charge` - oo
  - `:not_subject_i` - np I
  - `:not_subject_ii` - np II
  """
  @spec summary_type(String.t()) :: atom()
  def summary_type("23"), do: :standard
  def summary_type("22"), do: :standard
  def summary_type("8"), do: :standard
  def summary_type("7"), do: :standard
  def summary_type("5"), do: :standard
  def summary_type("4"), do: :standard
  def summary_type("3"), do: :standard
  def summary_type("0 KR"), do: :zero_domestic
  def summary_type("0 WDT"), do: :zero_wdt
  def summary_type("0 EX"), do: :zero_export
  def summary_type("zw"), do: :exempt
  def summary_type("oo"), do: :reverse_charge
  def summary_type("np I"), do: :not_subject_i
  def summary_type("np II"), do: :not_subject_ii
end
