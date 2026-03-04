defmodule Firmowid.SalesInvoices.VatEuApiClient do
  @moduledoc """
  Client for the EU VIES VAT API using Req HTTP client and Ecto embedded schemas.
  """

  alias Firmowid.SalesInvoices.VatEuResponse

  @endpoint "https://ec.europa.eu/taxation_customs/vies/rest-api//check-vat-number"

  @doc """
  Checks an EU VAT number for the provided country code.
  Returns {:ok, response} or {:error, reason}.
  """
  @spec check_vat_number(String.t(), String.t()) ::
          {:ok, VatEuResponse.t()}
          | {:error, :invalid_request}
          | {:error, String.t()}
          | {:error, term()}
  def check_vat_number(country_code, vat_number) when is_binary(country_code) and is_binary(vat_number) do
    payload = %{
      "countryCode" => String.trim(country_code),
      "vatNumber" => String.trim(vat_number)
    }

    case Req.post(@endpoint, json: payload) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case normalize_response(body) do
          {:ok, response} -> {:ok, response}
          {:error, reason} -> {:error, reason}
        end

      {:ok, %Req.Response{status: 400}} ->
        {:error, :invalid_request}

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP error: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_response(body) when is_map(body) do
    body
    |> Recase.Enumerable.convert_keys(&Recase.to_snake/1)
    |> Recase.Enumerable.atomize_keys()
    |> validate_response()
  end

  defp validate_response(attrs) when is_map(attrs) do
    changeset = VatEuResponse.changeset(%VatEuResponse{}, attrs)

    if changeset.valid? do
      {:ok, Ecto.Changeset.apply_changes(changeset)}
    else
      {:error, "Invalid response data"}
    end
  end
end
