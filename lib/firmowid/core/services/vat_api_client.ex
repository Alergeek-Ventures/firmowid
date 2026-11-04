defmodule Firmowid.Core.Services.VatApiClient do
  @moduledoc "Keyless VAT white list lookups shared by invoicing and company registration."

  @doc "Returns the VAT registry response for one NIP."
  @spec fetch_by_nip(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def fetch_by_nip(nip, options \\ []), do: request("nip/#{nip}", options)

  @doc """
  Returns subjects for a batch of at most 30 NIPs, including their KRS numbers.
  Not retried: a failed batch fails the caller's run, which is repeated later.
  """
  @spec fetch_by_nips([String.t()]) :: {:ok, [map()]} | {:error, term()}
  def fetch_by_nips(nips) when length(nips) in 1..30 do
    with {:ok, %{"result" => %{"entries" => entries}}} <-
           request("nips/#{Enum.join(nips, ",")}", retry: false) do
      Enum.reduce_while(entries, {:ok, []}, fn
        %{"subjects" => subjects}, {:ok, found} -> {:cont, {:ok, subjects ++ found}}
        %{"error" => error}, _found -> {:halt, {:error, {:vat_lookup_error, error}}}
      end)
    end
  end

  defp request(path, options) do
    options =
      [
        url: "https://wykazpodatnikowvat.mf.gov.pl/api/search/#{path}",
        params: [date: Date.to_iso8601(Date.utc_today())],
        headers: %{"Accept" => "application/json"}
      ]
      |> Keyword.merge(Application.get_env(:firmowid, :nip_api_request_options, []))
      |> Keyword.merge(options)

    case Req.get(options) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 400}} -> {:error, :invalid_nip}
      {:ok, %{status: status}} -> {:error, "HTTP error: #{status}"}
      {:error, _reason} = error -> error
    end
  end
end
