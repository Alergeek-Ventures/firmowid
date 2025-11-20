defmodule Firmowid.CostInvoices.Worker do
  @moduledoc false
  use Oban.Worker,
    queue: :cost_invoices,
    unique: true,
    max_attempts: 2

  alias Firmowid.Blobs
  alias Firmowid.CostInvoices
  alias Firmowid.CostInvoices.OpenAIEnrichment
  alias Firmowid.ReductoApiClient

  require Logger

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

        try do
          extract_cost_invoice_metadata(blob_id, organization_id, inbound_email_id)
        rescue
          error ->
            Logger.error("Failed to extract cost invoice metadata for blob #{blob_id}: #{inspect(error)}")

            # on failure, clean up dangling blob from DB and S3
            blob = Blobs.get_blob!(blob_id)
            Blobs.delete_blob(blob_id)

            CostInvoices.broadcast_cost_invoice_failed_to_process(
              blob.original_filename,
              organization_id
            )

            Sentry.capture_exception(error)

            :ok
        end

      _ ->
        Logger.error("Unknown job args: #{inspect(args)}")
    end
  end

  defp extract_cost_invoice_metadata(blob_id, organization_id, inbound_email_id) do
    # Organization context already set in perform/1, so get_blob_url uses it automatically
    blob_url = Blobs.get_blob_url(blob_id)

    {:ok, extracted_metadata} =
      ReductoApiClient.extract(
        blob_url,
        %{
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
              description: "Full name of the seller, including any
              organizational prefixes or suffixes, like first name."
            },
            seller_address: %{
              type: "string",
              description: "The address of the seller"
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
              description: "The currency of the total amount of the invoice, as three letter ISO 4217 code"
            },
            invoice_identifier: %{
              type: "string",
              description: "The identifier (typically number) of the invoice.

              Very often based on the date (e.g. 01/05/2023) or a serial number
              (e.g. 124/Z/2023).

              For receipts it can be any freeform-placed number.

              If it's neither an invoice or a receipt, but a contract for sale,
              then say e.g. 'Sale contract on day YYYY-MM-DD in City'.

              If identifier is not available at all - provide 'N/A'."
            },
            account_number: %{
              type: "string",
              description: "If provided, the account number of the seller that
              a wire transfer should be sent to."
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
            "invoice_identifier",
            "sale_date",
            "issue_date",
            "due_date",
            "total_amount",
            "currency",
            "items_list"
          ]
        }
      )

    extracted_metadata =
      extracted_metadata
      |> Map.put(
        "description",
        OpenAIEnrichment.generate_description(extracted_metadata)
      )
      |> Map.put("total_amount", -extracted_metadata["total_amount"])
      |> Map.put("organization_id", organization_id)
      |> Map.put("blob_id", blob_id)

    extracted_metadata =
      if inbound_email_id do
        Map.put(extracted_metadata, "inbound_email_id", inbound_email_id)
      else
        extracted_metadata
      end

    CostInvoices.create_cost_invoice(extracted_metadata)

    :ok
  end
end
