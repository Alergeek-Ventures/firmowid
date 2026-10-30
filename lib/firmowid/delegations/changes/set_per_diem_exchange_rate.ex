defmodule Firmowid.Delegations.Changes.SetPerDiemExchangeRate do
  @moduledoc """
  Stores the NBP rate that converts a foreign per diem to PLN.

  A foreign trip is settled with the average NBP rate from the day the advance is paid
  (§ 20 ust. 3 of the regulation on business-trip allowances), and the advance is set
  when the delegation is approved.
  """

  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Currencies.NbpApiClient
  alias Firmowid.Delegations.PerDiemRates

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :destination_country) do
      "PL" -> changeset
      country_code -> set_rate(changeset, country_code)
    end
  end

  defp set_rate(changeset, country_code) do
    currency =
      PerDiemRates.foreign(country_code).per_diem |> Money.to_currency_code() |> Atom.to_string()

    case NbpApiClient.get_exchange_rate_on(currency, Date.utc_today()) do
      {:ok, %{rate: rate, effective_date: effective_date}} ->
        changeset
        |> Ash.Changeset.force_change_attribute(:per_diem_nbp_rate, Decimal.from_float(rate))
        |> Ash.Changeset.force_change_attribute(
          :per_diem_nbp_rate_date,
          Date.from_iso8601!(effective_date)
        )

      {:error, _reason} ->
        Ash.Changeset.add_error(changeset,
          field: :per_diem_nbp_rate,
          message: gettext_noop("Could not fetch the NBP exchange rate.")
        )
    end
  end
end
