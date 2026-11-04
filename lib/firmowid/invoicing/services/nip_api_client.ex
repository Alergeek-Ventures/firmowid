defmodule Firmowid.Invoicing.Services.NipApiClient do
  @moduledoc """
  Client for the Polish VAT Registry API using Req HTTP client and Ecto embedded schemas.
  """

  use Ecto.Schema

  alias Firmowid.Core.Nip
  alias Firmowid.Invoicing.Services.NipResponse

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
    case Firmowid.Core.Services.VatApiClient.fetch_by_nip(nip, request_options) do
      {:ok, %{"result" => %{"subject" => nil}}} ->
        {:error, :not_found}

      {:ok, body} ->
        with {:ok, response} <-
               validate_response(Recase.Enumerable.convert_keys(body, &Recase.to_snake/1)) do
          {:ok,
           %{
             name: response.result.subject.name,
             nip: response.result.subject.nip,
             address: response.result.subject.working_address
           }}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_response(%{"result" => result}) when is_map(result) do
    {:ok, subject} = normalize_entity(result["subject"])

    {:ok,
     %{
       result: %{
         subject: subject,
         request_date_time: result["requestDateTime"],
         request_id: result["requestId"]
       }
     }}
  end

  defp validate_response(_), do: {:error, "Invalid response format"}

  defp normalize_entity(entity) when is_map(entity) do
    changeset = NipResponse.changeset(%NipResponse{}, Recase.Enumerable.atomize_keys(entity))

    if changeset.valid? do
      {:ok, Ecto.Changeset.apply_changes(changeset)}
    else
      {:error, "Invalid entity data"}
    end
  end

  defp normalize_entity(_), do: {:error, "Invalid entity format"}
end
