defmodule Firmowid.CostInvoices.Worker do
  require Logger

  alias Firmowid.Blobs

  use Oban.Worker,
    queue: :cost_invoices,
    unique: true,
    max_attempts: 1

  alias Firmowid.CostInvoices
  alias Firmowid.ReductoApiClient
  alias Firmowid.CostInvoices.OpenAIEnrichment

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case args do
      %{
        "name" => "extract_cost_invoice_metadata",
        "blob_id" => blob_id,
        "organization_id" => organization_id
      } ->
        try do
          extract_cost_invoice_metadata(blob_id, organization_id)
        rescue
          error ->
            Logger.error(
              "Failed to extract cost invoice metadata for blob #{blob_id}: #{inspect(error)}"
            )

            # on failure, clean up dangling blob from DB and S3
            blob = Blobs.get_blob!(blob_id, organization_id)
            Blobs.delete_blob(blob_id, organization_id)

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

  defp extract_cost_invoice_metadata(blob_id, organization_id) do
    blob_url = Blobs.get_blob_url(blob_id, :skip_organization_id)

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

    CostInvoices.create_cost_invoice(extracted_metadata)

    :ok
  end
end
