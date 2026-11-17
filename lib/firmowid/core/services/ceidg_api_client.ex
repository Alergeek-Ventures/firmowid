defmodule Firmowid.Core.Services.CeidgApiClient do
  @moduledoc "CEIDG register of sole proprietorships, shared by invoicing and company registration."

  # CEIDG allows 50 requests in 3 minutes and 1000 an hour, and blocks for 3 minutes
  # when exceeded; a steady 3.7 s between requests keeps under both.
  @pause_ms 3_700

  @doc """
  Returns the businesses CEIDG lists for a NIP, deregistered ones included, each
  with its `"status"` (`"AKTYWNY"`, `"ZAWIESZONY"`, `"WYKRESLONY"`, …); `[]` when
  CEIDG does not know the NIP. Waits before each request to stay within the limit.
  """
  @spec fetch_businesses(String.t()) :: {:ok, [map()]} | {:error, :not_configured | term()}
  def fetch_businesses(nip) do
    case Application.get_env(:firmowid, :ceidg_api_token) do
      nil ->
        {:error, :not_configured}

      token ->
        Process.sleep(@pause_ms)
        request(nip, token)
    end
  end

  defp request(nip, token) do
    case Req.get("https://dane.biznes.gov.pl/api/ceidg/v3/firma",
           params: [nip: nip],
           auth: {:bearer, token},
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"firma" => businesses}}} -> {:ok, businesses}
      {:ok, %{status: 204}} -> {:ok, []}
      {:ok, %{status: status}} -> {:error, {:ceidg_http_error, status}}
      {:error, _reason} = error -> error
    end
  end
end
