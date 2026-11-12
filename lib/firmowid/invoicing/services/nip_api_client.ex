defmodule Firmowid.Invoicing.Services.NipApiClient do
  @moduledoc """
  Looks up a company's name and working address in the Polish VAT white list by NIP.
  """

  alias Firmowid.Core.Nip
  alias Firmowid.Core.Services.VatApiClient

  @type organization :: %{
          name: String.t(),
          nip: String.t(),
          address: String.t()
        }

  @doc """
  Fetches organization data by NIP (tax identification number).

  Returns {:ok, response} or {:error, reason}.
  """
  @spec fetch_org_data_by_nip(String.t(), keyword()) ::
          {:ok, organization()}
          | {:error, :not_found}
          | {:error, :invalid_nip}
          | {:error, String.t()}
  def fetch_org_data_by_nip(nip, request_options \\ []) when is_binary(nip) do
    if Nip.valid?(nip) do
      fetch_valid_nip(Nip.normalize_digits(nip), request_options)
    else
      {:error, :invalid_nip}
    end
  end

  defp fetch_valid_nip(nip, request_options) do
    case VatApiClient.fetch_by_nip(nip, request_options) do
      {:ok, %{"result" => %{"subject" => nil}}} ->
        {:error, :not_found}

      {:ok, %{"result" => %{"subject" => %{} = subject}}} ->
        {:ok, %{name: subject["name"], nip: subject["nip"], address: subject["workingAddress"]}}

      {:ok, _body} ->
        {:error, "Invalid response format"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
