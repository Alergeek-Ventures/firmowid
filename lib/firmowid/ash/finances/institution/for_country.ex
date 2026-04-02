defmodule Firmowid.Ash.Finances.Institution.ForCountry do
  @moduledoc """
  ManualRead implementation that fetches banking institutions from the
  GoCardless API for a given country code.
  """

  use Ash.Resource.ManualRead

  alias Firmowid.Ash.Finances.GoCardless.ApiClient
  alias Firmowid.Ash.Finances.Institution

  @impl true
  def read(query, _data_layer_query, _opts, _context) do
    country = Ash.Query.get_argument(query, :country)

    case ApiClient.get_available_institutions_for_country(country) do
      {:ok, institutions} ->
        results =
          Enum.map(institutions, fn inst ->
            struct!(Institution, %{
              id: inst["id"],
              name: inst["name"],
              logo: inst["logo"],
              bic: inst["bic"],
              countries: inst["countries"] || [],
              transaction_total_days: inst["transaction_total_days"]
            })
          end)

        {:ok, results}

      {:error, reason} ->
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        {:error, Ash.Error.Unknown.exception(errors: [reason])}
    end
  end
end
