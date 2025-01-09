defmodule Firmowid.Invoices.NipApiClient do
  @moduledoc """
  Client for the Polish VAT Registry API using Req HTTP client and Ecto embedded schemas.
  """

  alias Firmowid.Invoices.NipResponse

  require Logger
  use Ecto.Schema

  @type organization :: %{
          name: String.t(),
          nip: String.t(),
          postal_code: String.t(),
          street: String.t(),
          city: String.t()
        }

  @doc """
  Fetches organization data by NIP (tax identification number).
  Returns {:ok, response} or {:error, reason}.
  """
  @spec fetch_org_data_by_nip(String.t()) ::
          {:ok, organization()}
          | {:error, :not_found}
          | {:error, :invalid_nip}
          | {:error, String.t()}
  def fetch_org_data_by_nip(nip) when is_binary(nip) do
    date = Date.utc_today() |> Date.to_string()
    url = "https://wl-api.mf.gov.pl/api/search/nip/#{nip |> String.trim()}?date=#{date}"

    case Req.get(
           url: url,
           headers: %{
             "Accept" => "application/json"
           }
         ) do
      {:ok, %Req.Response{status: 200, body: %{"result" => %{"subject" => nil}}}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: 200, body: body}} ->
        with {:ok, response} <-
               validate_response(Recase.Enumerable.convert_keys(body, &Recase.to_snake/1)) do
          address_info = generate_address_info(response.result.subject.working_address)

          {:ok,
           %{
             name: response.result.subject.name,
             nip: response.result.subject.nip,
             postal_code: address_info["postal_code"],
             street: address_info["street"],
             city: address_info["city"]
           }}
        end

      {:ok, %Req.Response{status: 400}} ->
        {:error, :invalid_nip}

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP error: #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec generate_address_info(String.t()) :: %{
          postal_code: String.t(),
          city: String.t(),
          street: String.t()
        }
  def generate_address_info(full_address) do
    case OpenAI.chat_completion(
           model: "gpt-4o-mini",
           max_completion_tokens: 200,
           response_format: %{
             type: "json_schema",
             json_schema: %{
               name: "full_address_info",
               strict: true,
               schema: %{
                 type: "object",
                 properties: %{
                   postal_code: %{
                     type: "string"
                   },
                   city: %{
                     type: "string"
                   },
                   street: %{
                     type: "string",
                     description:
                       "Full street name with house number and if available apartment number"
                   }
                 },
                 required: ["postal_code", "city", "street"],
                 additionalProperties: false
               }
             }
           },
           messages: [
             %{
               role: "system",
               content:
                 "You are a helpful assistant that generates full address information based on the full address."
             },
             %{
               role: "user",
               content:
                 "Here is the full address that I want to generate information for: #{full_address}. Please provide me with the postal code, city, and street. If you can't provide all the information fill the missing one with empty strings. Base your answer only on the provided full address, don't infer the city if it isn't specified in the address. Format it like in the example below, make sure to correct the case and punctuation.

           Example:
           {
              postal_code: '00-001',
              city: 'Warszawa',
              street: 'Skwer Kardynała Wyszyńskiego 1/2'
           }"
                 |> String.trim()
             }
           ]
         ) do
      {:ok, response} ->
        response.choices
        |> List.first()
        |> Map.get("message")
        |> Map.get("content")
        |> JSON.decode!()

      {:error, err} ->
        Sentry.capture_exception(err)

        %{
          "postal_code" => "",
          "city" => "",
          "street" => ""
        }
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
