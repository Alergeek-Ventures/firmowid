defmodule Firmowid.Invoices.NipApiClient do
  @moduledoc """
  Client for the Polish VAT Registry API using Req HTTP client.
  """
  require Logger

  @type pesel :: String.t()

  @type entity_person :: %{
          company_name: String.t() | nil,
          first_name: String.t() | nil,
          last_name: String.t() | nil,
          pesel: pesel() | nil,
          nip: String.t() | nil
        }

  @type entity :: %{
          name: String.t(),
          nip: String.t() | nil,
          status_vat: String.t() | nil,
          regon: String.t() | nil,
          pesel: pesel() | nil,
          krs: String.t() | nil,
          residence_address: String.t() | nil,
          working_address: String.t() | nil,
          representatives: [entity_person()] | nil,
          authorized_clerks: [entity_person()] | nil,
          partners: [entity_person()] | nil,
          registration_legal_date: String.t() | nil,
          registration_denial_date: String.t() | nil,
          registration_denial_basis: String.t() | nil,
          restoration_date: String.t() | nil,
          restoration_basis: String.t() | nil,
          removal_date: String.t() | nil,
          removal_basis: String.t() | nil,
          account_numbers: [String.t()] | nil,
          has_virtual_accounts: boolean() | nil
        }

  @type entity_item :: %{
          optional(:subject) => entity(),
          optional(:request_date_time) => String.t(),
          optional(:request_id) => String.t()
        }

  @type api_response :: %{
          optional(:result) => entity_item()
        }

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
        response = validate_response(body)

        address_info = generate_address_info(response.result.subject.working_address)

        {:ok,
         %{
           name: response.result.subject.name,
           nip: response.result.subject.nip,
           postal_code: address_info["postal_code"],
           street: address_info["street"],
           city: address_info["city"]
         }}

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
                 "Here is the full address that I want to generate information for: #{full_address}. Please provide me with the postal code, city, and street. If you can't provide all the information fill the missing one with empty strings. Base your answer only on the provided full address. Format it like in the example below, make sure to correct the case and punctuation.

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
        Logger.error("Failed to generate address info: #{inspect(err)}")

        %{
          "postal_code" => "",
          "city" => "",
          "street" => ""
        }
    end
  end

  @doc """
  Validates the response against the expected schema.
  In a production environment, you'd want to add more thorough validation.
  """
  @spec validate_response(map()) :: api_response()
  def validate_response(body) when is_map(body) do
    # In a real implementation, you'd want to add more validation here
    # This is a simplified version that just ensures the basic structure
    case body do
      %{"result" => result} when is_map(result) ->
        %{result: normalize_entity_item(result)}

      _ ->
        %{}
    end
  end

  @spec normalize_entity_item(map()) :: entity_item()
  defp normalize_entity_item(item) do
    %{
      subject: normalize_entity(item["subject"]),
      request_date_time: item["requestDateTime"],
      request_id: item["requestId"]
    }
  end

  @spec normalize_entity(map()) :: entity() | nil
  defp normalize_entity(entity) when is_map(entity) do
    %{
      name: entity["name"],
      nip: entity["nip"],
      status_vat: normalize_status_vat(entity["statusVat"]),
      regon: entity["regon"],
      pesel: entity["pesel"],
      krs: entity["krs"],
      residence_address: entity["residenceAddress"],
      working_address: entity["workingAddress"],
      representatives: normalize_persons(entity["representatives"]),
      authorized_clerks: normalize_persons(entity["authorizedClerks"]),
      partners: normalize_persons(entity["partners"]),
      registration_legal_date: entity["registrationLegalDate"],
      registration_denial_date: entity["registrationDenialDate"],
      registration_denial_basis: entity["registrationDenialBasis"],
      restoration_date: entity["restorationDate"],
      restoration_basis: entity["restorationBasis"],
      removal_date: entity["removalDate"],
      removal_basis: entity["removalBasis"],
      account_numbers: entity["accountNumbers"],
      has_virtual_accounts: entity["hasVirtualAccounts"]
    }
  end

  defp normalize_entity(_), do: nil

  @spec normalize_status_vat(String.t() | nil) :: String.t() | nil
  defp normalize_status_vat(status) when status in ["Czynny", "Zwolniony", "Niezarejestrowany"],
    do: status

  defp normalize_status_vat(_), do: nil

  @spec normalize_persons(list(map()) | nil) :: [entity_person()] | nil
  defp normalize_persons(nil), do: nil

  defp normalize_persons(persons) when is_list(persons) do
    Enum.map(persons, &normalize_person/1)
  end

  @spec normalize_person(map()) :: entity_person()
  defp normalize_person(person) when is_map(person) do
    %{
      company_name: person["companyName"],
      first_name: person["firstName"],
      last_name: person["lastName"],
      pesel: person["pesel"],
      nip: person["nip"]
    }
  end
end
