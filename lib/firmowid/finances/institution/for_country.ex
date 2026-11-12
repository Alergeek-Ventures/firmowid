defmodule Firmowid.Finances.Institution.ForCountry do
  @moduledoc """
  ManualRead implementation that fetches banking institutions from the
  GoCardless API for a given country code. The list is kept for six hours in the
  `:institutions` cache, which also holds the logo colours.
  """

  use Ash.Resource.ManualRead

  alias Firmowid.Finances.GoCardless.ApiClient
  alias Firmowid.Finances.Institution
  alias Firmowid.Finances.Institution.ColorCache

  # GoCardless's mock bank, which no country list contains; it is requested by its id.
  # https://developer.gocardless.com/bank-account-data/sandbox
  @sandbox_institution_id "SANDBOXFINANCE_SFIN0000"

  @cache :institutions

  # Banks join the list rarely, and every page showing it waited for GoCardless.
  @list_expire to_timeout(hour: 6)

  @impl true
  def read(query, _data_layer_query, _opts, _context) do
    country = Ash.Query.get_argument(query, :country)

    with {:ok, institutions} <- institutions(country) do
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
    end
  end

  # A failed request is not kept, so the next read asks again.
  defp institutions(country) do
    case Cachex.get(@cache, {:country, country}) do
      {:ok, nil} ->
        with {:ok, institutions} <- request_institutions(country) do
          Cachex.put(@cache, {:country, country}, institutions, expire: @list_expire)
          {:ok, institutions}
        end

      {:ok, institutions} ->
        {:ok, institutions}
    end
  end

  defp request_institutions(country) do
    with {:ok, institutions} <- ApiClient.get_available_institutions_for_country(country) do
      with_sandbox(institutions, Application.get_env(:firmowid, :environment))
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
