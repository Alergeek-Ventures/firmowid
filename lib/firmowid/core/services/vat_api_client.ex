defmodule Firmowid.Core.Services.VatApiClient do
  @moduledoc """
  Keyless VAT white list lookups shared by invoicing and company registration.
  Each request takes one from the daily limit shared by all processes
  (`RegisterRateLimiter`); a used-up limit returns `{:error, :rate_limited}`.
  """

  alias Firmowid.Core.Services.RegisterRateLimiter

  @doc "Returns the VAT registry response for one NIP."
  @spec fetch_by_nip(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch_by_nip(nip, options \\ []), do: request(:mf_search, "api/search/nip/#{nip}", options)

  @doc """
  Returns subjects for a batch of at most 30 NIPs, including their KRS numbers.
  Not retried: a failed batch fails the caller's run, which is repeated later.
  """
  @spec fetch_by_nips([String.t()]) :: {:ok, [map()]} | {:error, term()}
  def fetch_by_nips(nips) do
    with {:ok, %{"result" => %{"entries" => entries}}} <-
           request(:mf_search, "api/search/nips/#{Enum.join(nips, ",")}", []) do
      Enum.reduce_while(entries, {:ok, []}, fn
        %{"subjects" => subjects}, {:ok, found} -> {:cont, {:ok, subjects ++ found}}
        %{"error" => error}, _found -> {:halt, {:error, {:vat_lookup_error, error}}}
      end)
    end
  end

  @doc """
  Returns the VAT status code of one NIP from the WL2 status API: `"C"` active,
  `"Z"` exempt, `"N"` not registered, `"B"` not in the VAT register at all, `"I"`
  invalid NIP, `"X"` service inactive. WL2 allows 50 000 requests a day,
  `search` only 100.
  """
  @spec fetch_status(String.t()) :: {:ok, String.t()} | {:error, term()}
  def fetch_status(nip) do
    options = Application.get_env(:firmowid, :vat_status_api_request_options, [])

    case request(:mf_status, "api2/status/nip/#{nip}", options) do
      {:ok, %{"result" => %{"subject" => %{"statusCode" => code}}}} -> {:ok, code}
      {:error, _reason} = error -> error
    end
  end

  defp request(register, path, options) do
    with :ok <- RegisterRateLimiter.acquire(register), do: get(path, options)
  end

  defp get(path, options) do
    options =
      [
        url: "https://wykazpodatnikowvat.mf.gov.pl/#{path}",
        params: [date: Date.to_iso8601(Date.utc_today())],
        headers: %{"Accept" => "application/json"}
      ]
      |> Keyword.merge(Application.get_env(:firmowid, :nip_api_request_options, []))
      |> Keyword.merge(options)
      # A retry would be a request the limit does not count; the caller asks again later.
      |> Keyword.put(:retry, false)

    case Req.get(options) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 400}} -> {:error, :invalid_nip}
      {:ok, %{status: status}} -> {:error, "HTTP error: #{status}"}
      {:error, _reason} = error -> error
    end
  end
end
