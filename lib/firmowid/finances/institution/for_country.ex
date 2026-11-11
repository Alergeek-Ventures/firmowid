defmodule Firmowid.Finances.Institution.ForCountry do
  @moduledoc """
  ManualRead implementation that fetches banking institutions from the
  GoCardless API for a given country code.
  """

  use Ash.Resource.ManualRead

  alias Firmowid.Finances.GoCardless.ApiClient
  alias Firmowid.Finances.Institution
  alias Firmowid.Finances.Institution.ColorCache

  # GoCardless's mock bank, which no country list contains; it is requested by its id.
  # https://developer.gocardless.com/bank-account-data/sandbox
  @sandbox_institution_id "SANDBOXFINANCE_SFIN0000"

  @impl true
  def read(query, _data_layer_query, _opts, _context) do
    country = Ash.Query.get_argument(query, :country)

    with {:ok, institutions} <- ApiClient.get_available_institutions_for_country(country),
         {:ok, institutions} <-
           with_sandbox(institutions, Application.get_env(:firmowid, :environment)) do
      ColorCache.warm_dominant_color_rgbs(Enum.map(institutions, & &1["logo"]))

      results =
        Enum.map(institutions, fn inst ->
          struct!(Institution, %{
            id: inst["id"],
            name: inst["name"],
            logo: inst["logo"],
            dominant_color_rgb: ColorCache.get_dominant_color_rgb(inst["logo"]),
            bic: inst["bic"],
            countries: inst["countries"] || [],
            transaction_total_days: inst["transaction_total_days"]
          })
        end)

      {:ok, results}
    else
      {:error, reason} ->
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        {:error, Ash.Error.Unknown.exception(errors: [reason])}
    end
  end

  # In development the mock bank leads the list, so a bank can be connected end to end.
  defp with_sandbox(institutions, :dev) do
    with {:ok, sandbox} <- ApiClient.get_institution(@sandbox_institution_id) do
      {:ok, [sandbox | institutions]}
    end
  end

  defp with_sandbox(institutions, _environment), do: {:ok, institutions}
end
