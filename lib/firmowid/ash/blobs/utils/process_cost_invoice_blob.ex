defmodule Firmowid.Ash.Blobs.Utils.ProcessCostInvoiceBlob do
  @moduledoc """
  Processes a pending blob into a cost invoice by extracting metadata.
  """
  alias Firmowid.Ash.Blobs.Utils.ProcessBlobHelpers
  alias Firmowid.Ash.Invoicing

  @cost_invoice_system_prompt """
  Extract data from this cost invoice, receipt, or bill document.

  Guidelines:
  - Dates should be in YYYY-MM-DD format
  - Currency should be a 3-letter ISO 4217 code (e.g., PLN, USD, EUR)
  - For Polish invoices: "Sprzedawca" = seller, "Data wystawienia" = issue date, "Data sprzedaży/dostawy" = sale date
  - If the invoice includes a KSeF number, extract it exactly as printed
  - If present, extract the seller tax identifier (for Polish invoices usually NIP)
  - Total amount should be the gross/brutto amount (including VAT/tax)
  - If the document is not an invoice, receipt, or bill (e.g., it's a contract, report, or unrelated document), set document_type to "invalid"
  """

  @cost_invoice_schema %{
    type: "object",
    properties: %{
      document_type: %{type: "string", enum: ["cost_invoice", "invalid"]},
      sale_date: %{type: "string", format: "date"},
      issue_date: %{type: "string", format: "date"},
      due_date: %{type: "string", format: "date"},
      seller: %{type: "string"},
      seller_nip: %{type: "string"},
      seller_address: %{type: "string"},
      ksef_number: %{type: "string"},
      total_amount: %{type: "number"},
      currency: %{type: "string"},
      invoice_identifier: %{type: "string"},
      account_number: %{type: "string"},
      items_list: %{
        type: "array",
        items: %{
          type: "object",
          properties: %{
            name: %{type: "string"},
            quantity: %{type: "number"},
            price: %{type: "number"}
          },
          required: ["name", "quantity", "price"]
        }
      }
    },
    required: ["document_type"],
    if: %{properties: %{document_type: %{const: "cost_invoice"}}, required: ["document_type"]},
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

  @required_cost_invoice_fields ~w(
    seller
    invoice_identifier
    sale_date
    issue_date
    due_date
    total_amount
    currency
    items_list
  )

  def run_processing(blob_url, blob, opts) do
    with {:ok, extracted_metadata} <- extract_metadata(blob_url),
         :ok <- ensure_cost_invoice_document(extracted_metadata) do
      create_invoice(extracted_metadata, blob, opts)
    end
  rescue
    error ->
      {:error, error}
  end

  defp extract_metadata(blob_url) do
    ProcessBlobHelpers.reducto_client().extract(blob_url, @cost_invoice_schema,
      system_prompt: @cost_invoice_system_prompt
    )
  end

  defp ensure_cost_invoice_document(%{"document_type" => "cost_invoice"} = extracted_metadata) do
    if Enum.all?(@required_cost_invoice_fields, &(not is_nil(extracted_metadata[&1]))) do
      :ok
    else
      {:error, :invalid_document}
    end
  end

  defp ensure_cost_invoice_document(_), do: {:error, :invalid_document}

  defp create_invoice(extracted_metadata, blob, _opts) do
    inbound_email_id =
      blob.processing_metadata["inbound_email_id"] ||
        blob.processing_metadata[:inbound_email_id]

    attrs =
      extracted_metadata
      |> Map.delete("document_type")
      |> Map.delete("total_amount")
      |> Map.delete("currency")
      |> Map.put("amount", extracted_amount(extracted_metadata))
      |> Map.put("organization_id", blob.organization_id)
      |> Map.put("blob_id", blob.id)
      |> maybe_put_inbound_email_id(inbound_email_id)

    case Invoicing.create_cost_invoice_with_ksef_dedup(attrs) do
      {:ok, _job} -> :ok
      {:error, {:duplicate_ksef_invoice, _id} = dup} -> {:error, dup}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_inbound_email_id(attrs, nil), do: attrs

  defp maybe_put_inbound_email_id(attrs, inbound_email_id), do: Map.put(attrs, "inbound_email_id", inbound_email_id)

  defp extracted_amount(%{"currency" => currency, "total_amount" => total_amount}) do
    Money.new!(currency, total_amount |> decimal_amount() |> Decimal.negate())
  end

  defp decimal_amount(%Decimal{} = amount), do: amount
  defp decimal_amount(amount) when is_float(amount), do: Decimal.from_float(amount)
  defp decimal_amount(amount), do: Decimal.new(amount)
end
