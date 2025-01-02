defmodule Firmowid.Documents.Reducto do
  use GenServer

  alias Firmowid.Documents

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def start_extraction_job(document_id, organization_id) do
    GenServer.cast(__MODULE__, {:extract_invoice_info, document_id, organization_id})
  end

  @impl true
  def init(nil) do
    {:ok, nil}
  end

  @impl true
  def handle_cast({:extract_invoice_info, document_id, organization_id}, state) do
    try do
      extract_invoice_info(document_id, organization_id)
    rescue
      error ->
        Logger.error(
          "Failed to extract invoice info for document #{document_id}: #{inspect(error)}"
        )

        Documents.broadcast_document_upload_failed(document_id)
        Documents.delete_document(organization_id, document_id)
    end

    {:noreply, state}
  end

  defp extract_invoice_info(document_id, organization_id) do
    file_url = Documents.get_file_url(document_id, organization_id)

    invoice_extraction_schema = %{
      type: "object",
      properties: %{
        sale_date: %{
          type: "string",
          format: "date",
          description: "The date of the sale"
        },
        issue_date: %{
          type: "string",
          format: "date",
          description: "The issue date of the invoice"
        },
        due_date: %{
          type: "string",
          format: "date",
          description: "The payment deadline date"
        },
        seller: %{
          type: "string",
          description: "From whom the invoice is, include all of the available
          info like full name, address, bank account etc."
        },
        seller_display_name: %{
          type: "string",
          description:
            "Shortened version (2-5 words) of the name of the seller, that can easily be display in the UI."
        },
        total_amount: %{
          type: "number",
          description: "The total amount of the invoice"
        },
        currency: %{
          type: "string",
          description:
            "The currency of the total amount of the invoice, as three letter ISO 4217 code"
        },
        invoice_identifier: %{
          type: "string",
          description: "The identifier (typically number) of the invoice"
        },
        items_list: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              name: %{
                type: "string",
                description: "The name of the item"
              },
              quantity: %{
                type: "number",
                description: "The quantity of the item"
              },
              price: %{
                type: "number",
                description: "The price of the item"
              }
            },
            required: ["name", "quantity", "price"]
          }
        }
      },
      required: [
        "seller",
        "sale_date",
        "issue_date",
        "due_date",
        "total_amount",
        "currency",
        "items_list"
      ]
    }

    extracted_metadata =
      if true do
        # switch here to mock reducto
        reducto_extract_response =
          Req.post!(
            "https://v1.api.reducto.ai/extract",
            auth:
              {:bearer,
               "f6db515168d1b7c99dcecfd0517062dcbfd083a6ba1e42d0e3bcc623d832288087949aa99728f0d65ff5da7044e9fecc"},
            json: %{
              document_url: file_url,
              options: %{
                extraction_mode: "hybrid"
              },
              async: %{
                enabled: false
              },
              schema: invoice_extraction_schema
            },
            receive_timeout: 120_000,
            connect_options: [timeout: 120_000]
          )

        # it returns as list, so we take first item
        Enum.at(reducto_extract_response.body["result"], 0)
      else
        %{
          "invoice_identifier" => "01/09/2024",
          "seller" => "Mocked Reducto",
          "sale_date" => ~D[2024-11-20],
          "issue_date" => ~D[2024-11-20],
          "due_date" => ~D[2024-11-21],
          "total_amount" => 100.0,
          "currency" => "PLN"
        }
      end

    extracted_metadata =
      Map.put(extracted_metadata, "total_amount", -extracted_metadata["total_amount"])

    extracted_metadata =
      Map.put(extracted_metadata, "description", generate_description(extracted_metadata))

    Documents.update_document_metadata(organization_id, document_id, extracted_metadata)
  end

  defp generate_description(document) do
    {:ok, response} =
      OpenAI.chat_completion(
        model: "gpt-4o-mini",
        max_completion_tokens: 80,
        messages: [
          %{
            role: "system",
            content:
              "Jesteś asystentem dla osób zajmujących się dokumentami " <>
                "i transakcjami w przedsiębiorstwie. Pomagasz w opisywaniu " <>
                "katalogowaniu i dopasowaniu ich do siebie."
          },
          %{
            role: "user",
            content: "
              Oto metadane faktury sprzedażowej, którą chcą skatalogować:

              {
                sprzedawca: #{document["seller"]},
                przedmioty na fakturze: #{inspect(document["items_list"])}
              }

              Na podstawie tych danych, przygotuj opis faktury (w języku polskim)
              Będzie on wykorzystywany przez osoby, które potencjalnie nie mają
              informacji o tym, czym zajmuje się firma sprzedawcy, lub czym jest
              dany artykuł wypisany w dokumencie.  Nie używaj słów 'faktura za'
              (bo każdy dokument to faktura) oraz nie zawieraj w opisie
              informacji, które są już dostępne w metadanych. Skup się na tym,
              co zostało zakupione.

              Dobre przykłady opisów:

              - Paliwo do samochodu z nr rej. RZ941AY, zakupione w Krakowie na stacji Orlen.
              - Abonament telekomunikacyjny, trzy numery telefonu oraz internet mobilny
              - Komunikator, opłata za jedno miejsce na planie pro start
              - Abonament na hosting email, plan Zoho Marketplace Mail Lite

              Postaraj się zamknąć w 5-10 słowach.
              " |> String.trim()
          }
        ]
      )

    description =
      response.choices
      |> List.first()
      |> Map.get("message")
      |> Map.get("content")

    description
  end
end
