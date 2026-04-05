defmodule Firmowid.Ash.Invoicing.Workers.CostInvoiceWorker do
  @moduledoc """
  Oban worker that extracts metadata from uploaded cost invoice documents
  using Reducto API, generates a description via OpenAI, and creates
  the cost invoice record.
  """

  use Oban.Worker,
    queue: :cost_invoices,
    unique: true,
    max_attempts: 2

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.Services.OpenAIEnrichment
  alias Firmowid.Ash.Invoicing.Services.ReductoApiClient

  require Logger

  @cost_invoice_system_prompt """
  Extract data from this cost invoice, receipt, or bill document.

  Guidelines:
  - Dates should be in YYYY-MM-DD format
  - Currency should be a 3-letter ISO 4217 code (e.g., PLN, USD, EUR)
  - For Polish invoices: "Sprzedawca" = seller, "Data wystawienia" = issue date, "Data sprzedaży/dostawy" = sale date
  - Total amount should be the gross/brutto amount (including VAT/tax)
  - If the document is not an invoice, receipt, or bill (e.g., it's a contract, report, or unrelated document), set document_type to "invalid"
  """

  # JSON Schema with conditional validation:
  # - document_type is always required
  # - other fields are only required when document_type is "cost_invoice"
  @cost_invoice_schema %{
    type: "object",
    properties: %{
      document_type: %{
        type: "string",
        enum: ["cost_invoice", "invalid"],
        description:
          "Type of document: 'cost_invoice' for invoices, receipts, bills; 'invalid' for any other document type"
      },
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
        description: "Full name of the seller, including any organizational prefixes or suffixes, like first name."
      },
      seller_address: %{
        type: "string",
        description: "The address of the seller"
      },
      seller_display_name: %{
        type: "string",
        description: "Shortened version (2-5 words) of the name of the seller, that can easily be display in the UI."
      },
      total_amount: %{
        type: "number",
        description: "The total amount of the invoice"
      },
      currency: %{
        type: "string",
        description: "The currency of the total amount of the invoice, as three letter ISO 4217 code"
      },
      invoice_identifier: %{
        type: "string",
        description: """
        The identifier (typically number) of the invoice.

        Very often based on the date (e.g. 01/05/2023) or a serial number (e.g. 124/Z/2023).

        For receipts it can be any freeform-placed number.

        If it's neither an invoice or a receipt, but a contract for sale,
        then say e.g. 'Sale contract on day YYYY-MM-DD in City'.

        If identifier is not available at all - provide 'N/A'.
        """
      },
      account_number: %{
        type: "string",
        description: "If provided, the account number of the seller that a wire transfer should be sent to."
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
    required: ["document_type"],
    if: %{
      properties: %{document_type: %{const: "cost_invoice"}},
      required: ["document_type"]
    },
    then: %{
      required: [
        "seller",
        "invoice_identifier",
        "sale_date",
        "issue_date",
        "due_date",
        "total_amount",
        "currency",
        "items_list"
      ]
    }
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case args do
      %{
        "name" => "extract_cost_invoice_metadata",
        "blob_id" => blob_id,
        "organization_id" => organization_id
      } ->
        Firmowid.Repo.put_org_id(organization_id)
        inbound_email_id = Map.get(args, "inbound_email_id")

        # TODO: replace authorize?: false + actor: %{} with system actor once available
        blob_opts = [tenant: organization_id, authorize?: false, actor: %{}]

        try do
          extract_cost_invoice_metadata(blob_id, organization_id, inbound_email_id, blob_opts)
        rescue
          error ->
            Logger.error("Failed to extract cost invoice metadata for blob #{blob_id}: #{inspect(error)}")

            # on failure, clean up dangling blob from DB and S3
            # notification_metadata carries reason through Ash PubSub on blob:destroyed topic
            blob = Blobs.get_blob!(blob_id, blob_opts)

            Blobs.destroy_blob!(
              blob,
              Keyword.put(blob_opts, :notification_metadata, %{reason: :processing_failed})
            )

            ErrorTracker.report(error, __STACKTRACE__)

            :ok
        end

      _ ->
        Logger.error("Unknown job args: #{inspect(args)}")
    end
  end

  defp extract_cost_invoice_metadata(blob_id, organization_id, inbound_email_id, blob_opts) do
    blob_url = Blobs.get_blob!(blob_id, Keyword.put(blob_opts, :load, [:url])).url

    {:ok, extracted_metadata} =
      ReductoApiClient.extract(
        blob_url,
        @cost_invoice_schema,
        system_prompt: @cost_invoice_system_prompt
      )

    case extracted_metadata["document_type"] do
      "cost_invoice" ->
        create_cost_invoice(extracted_metadata, blob_id, organization_id, inbound_email_id)

      _invalid ->
        handle_invalid_document(blob_id, blob_opts)
    end

    :ok
  end

  defp create_cost_invoice(extracted_metadata, blob_id, organization_id, inbound_email_id) do
    extracted_metadata =
      extracted_metadata
      |> Map.delete("document_type")
      |> Map.put("description", OpenAIEnrichment.generate_description(extracted_metadata))
      |> Map.put("total_amount", -extracted_metadata["total_amount"])
      |> Map.put("organization_id", organization_id)
      |> Map.put("blob_id", blob_id)

    extracted_metadata =
      if inbound_email_id do
        Map.put(extracted_metadata, "inbound_email_id", inbound_email_id)
      else
        extracted_metadata
      end

    Invoicing.create_cost_invoice(extracted_metadata)
  end

  defp handle_invalid_document(blob_id, blob_opts) do
    # notification_metadata carries reason through Ash PubSub on blob:destroyed topic
    blob = Blobs.get_blob!(blob_id, blob_opts)

    Blobs.destroy_blob!(
      blob,
      Keyword.put(blob_opts, :notification_metadata, %{reason: :invalid_document})
    )
  end
end
