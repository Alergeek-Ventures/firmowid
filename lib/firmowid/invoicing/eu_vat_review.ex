defmodule Firmowid.Invoicing.EuVatReview do
  @moduledoc """
  VAT problems of an EU buyer, shown before an invoice is issued and on issued invoices.

  Only problems are reported; a number that passes every check produces no finding.

  Keeps three questions apart:

    * structure — `EuVatNumber` rules, which also block issuing;
    * registration — VIES, the authoritative status, which only informs: VIES may
      be unavailable, and the buyer's status can be proven otherwise;
    * rate — whether the item rates fit the buyer.

  Under Art. 18(1)(a) of Implementing Regulation (EU) 282/2011 a supplier may treat
  an EU customer as a taxable person once the VAT number's validity is confirmed,
  which rates where the customer accounts for VAT (`oo`, `np II`) rely on.
  """

  alias Firmowid.Invoicing.CountryCodes
  alias Firmowid.Invoicing.EuVatNumber
  alias Firmowid.Invoicing.Services.VatEuApiClient
  alias Firmowid.Invoicing.TaxId

  @type registration :: :active | :inactive | :unavailable | :pending | nil
  @type finding :: %{
          topic: :number | :registration | :rate,
          level: :warning | :error,
          code: atom()
        }

  @domestic_rates ["23", "22", "8", "7", "5", "4", "3", "0 KR", "zw"]
  @buyer_settles_rates ["oo", "np II"]

  @doc "Whether the buyer is identified by an EU VAT number, so the review applies."
  @spec applies?(map()) :: boolean()
  def applies?(invoice) do
    CountryCodes.tax_id_type(invoice.buyer_country, invoice.buyer_pesel, invoice.buyer_type) ==
      :eu_vat and
      present?(invoice.buyer_id)
  end

  @doc "Whether the buyer's EU VAT number breaks its country's rules, which blocks issuing with it."
  @spec number_rejected?(map()) :: boolean()
  def number_rejected?(invoice) do
    applies?(invoice) and
      match?(
        {:error, _rule, _suggestions},
        EuVatNumber.check(invoice.buyer_country, invoice.buyer_id)
      )
  end

  @doc """
  The problem with an issued invoice's buyer EU VAT number: it breaks its country's
  rules, or the buyer's counterparty failed the periodic VIES check for the same number.
  """
  @spec issued_problem(map(), map() | nil) :: :invalid | {:inactive, DateTime.t()} | nil
  def issued_problem(invoice, counterparty) do
    cond do
      not applies?(invoice) -> nil
      number_rejected?(invoice) -> :invalid
      inactive_number?(invoice, counterparty) -> {:inactive, counterparty.vat_id_checked_at}
      true -> nil
    end
  end

  @doc """
  Lists the problems of an invoice with an EU buyer, given the VIES status.

  `invoice` needs the buyer fields and item `vat_rate`s.
  """
  @spec findings(map(), registration()) :: [finding()]
  def findings(invoice, registration) do
    if applies?(invoice) do
      Enum.filter(
        [
          number_finding(invoice),
          registration_finding(registration) | rate_findings(invoice, registration)
        ],
        & &1
      )
    else
      []
    end
  end

  @doc "Asks VIES whether the number is registered. Network and member-state failures are `:unavailable`."
  @spec check_registration(String.t(), String.t()) :: :active | :inactive | :unavailable
  def check_registration(country, number) do
    country
    |> vies_country()
    |> VatEuApiClient.check_vat_number(EuVatNumber.normalize(number))
    |> registration_status()
  end

  @doc "Maps a VIES client result to a registration status."
  @spec registration_status({:ok, map()} | {:error, term()}) :: :active | :inactive | :unavailable
  def registration_status({:ok, %{valid: true}}), do: :active
  def registration_status({:ok, %{valid: false}}), do: :inactive
  # VIES answers 200 without `valid` when the member state's registry does not respond.
  def registration_status({:ok, _response}), do: :unavailable
  def registration_status({:error, _reason}), do: :unavailable

  defp number_finding(invoice) do
    case EuVatNumber.check(invoice.buyer_country, invoice.buyer_id) do
      {:ok, _number} -> nil
      {:error, rule, _suggestions} -> %{topic: :number, level: :error, code: rule}
    end
  end

  defp registration_finding(:inactive), do: %{topic: :registration, level: :warning, code: :inactive}

  defp registration_finding(_other), do: nil

  defp rate_findings(invoice, registration) do
    rates = invoice.sales_invoice_items |> Enum.map(& &1.vat_rate) |> Enum.uniq()

    Enum.filter(
      [
        Enum.any?(rates, &(&1 in @domestic_rates)) &&
          %{topic: :rate, level: :warning, code: :domestic_rate},
        (Enum.any?(rates, &(&1 in @buyer_settles_rates)) and registration == :inactive) &&
          %{topic: :rate, level: :warning, code: :buyer_settles_unconfirmed}
      ],
      & &1
    )
  end

  defp inactive_number?(invoice, %{vat_id_status: :inactive} = counterparty) do
    TaxId.normalize(counterparty.tax_id) == TaxId.normalize(invoice.buyer_id) and
      CountryCodes.normalize(counterparty.country) ==
        CountryCodes.normalize(invoice.buyer_country)
  end

  defp inactive_number?(_invoice, _counterparty), do: false

  # VIES uses EL for Greece, as KSeF does.
  defp vies_country(country), do: CountryCodes.normalize(country)

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
