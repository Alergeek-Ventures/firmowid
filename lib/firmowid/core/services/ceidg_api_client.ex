defmodule Firmowid.Core.Services.CeidgApiClient do
  @moduledoc "CEIDG register of sole proprietorships, shared by invoicing and company registration."

  alias Firmowid.Core.Services.RegisterRateLimiter

  @doc """
  Returns the businesses CEIDG lists for a NIP, deregistered ones included, each
  with its `"status"` (`"AKTYWNY"`, `"ZAWIESZONY"`, `"WYKRESLONY"`, …); `[]` when
  CEIDG does not know the NIP. Waits for its turn in the limit shared by all
  processes (`RegisterRateLimiter`), or returns `{:error, :rate_limited}`.
  """
  @spec fetch_businesses(String.t()) ::
          {:ok, [map()]} | {:error, :not_configured | :rate_limited | term()}
  def fetch_businesses(nip) do
    case Application.get_env(:firmowid, :ceidg_api_token) do
      nil ->
        {:error, :not_configured}

      token ->
        with :ok <- RegisterRateLimiter.acquire(:ceidg), do: request(nip, token)
    end
  end

  defp request(nip, token) do
    options =
      Keyword.merge(
        [
          url: "https://dane.biznes.gov.pl/api/ceidg/v3/firma",
          params: [nip: nip],
          auth: {:bearer, token},
          retry: false
        ],
        Application.get_env(:firmowid, :ceidg_api_request_options, [])
      )

    case Req.get(options) do
      {:ok, %{status: 200, body: %{"firma" => businesses}}} -> {:ok, businesses}
      {:ok, %{status: 204}} -> {:ok, []}
      {:ok, %{status: status}} -> {:error, {:ceidg_http_error, status}}
      {:error, _reason} = error -> error
    end
  end
end
