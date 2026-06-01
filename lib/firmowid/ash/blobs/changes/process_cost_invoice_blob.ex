defmodule Firmowid.Ash.Blobs.Changes.ProcessCostInvoiceBlob do
  @moduledoc """
  Processes a pending blob into a cost invoice by extracting metadata.
  """
  use Ash.Resource.Change

  alias Firmowid.Ash.Blobs.Changes.ProcessBlobHelpers
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Logger

  @cost_invoice_system_prompt """
  Extract data from this cost invoice, receipt, or bill document.

  Guidelines:
  - Dates should be in YYYY-MM-DD format
  - Currency should be a 3-letter ISO 4217 code (e.g., PLN, USD, EUR)
  - For Polish invoices: "Sprzedawca" = seller, "Data wystawienia" = issue date, "Data sprzedaży/dostawy" = sale date
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

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, blob ->
      actor = %SystemActor{
        org_id: blob.organization_id,
        role: :cost_invoice_processor,
        blob_id: blob.id
      }

      scope = %Scope{actor: actor, tenant: blob.organization_id}
      opts = [scope: scope]

      case run_processing(blob, opts) do
        :ok ->
          {:ok, blob}

        {:error, reason} ->
          Logger.warning("Failed to process cost invoice blob #{blob.id}: #{inspect(reason)}")
          _ = handle_failure(blob, reason, opts)
          {:ok, blob}
      end
    end)
  end

  defp run_processing(blob, opts) do
    with {:ok, blob} <- ProcessBlobHelpers.ensure_processing(blob, opts),
         {:ok, blob_url} <- ProcessBlobHelpers.load_blob_url(blob, opts),
         {:ok, extracted_metadata} <- extract_metadata(blob_url),
         :ok <- ensure_cost_invoice_document(extracted_metadata),
         :ok <- create_invoice(extracted_metadata, blob, opts),
         {:ok, _updated_blob} <- ProcessBlobHelpers.mark_succeeded(blob, opts) do
      :ok
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

  defp ensure_cost_invoice_document(%{"document_type" => "cost_invoice"}), do: :ok
  defp ensure_cost_invoice_document(_), do: {:error, :invalid_document}

  defp create_invoice(extracted_metadata, blob, _opts) do
    inbound_email_id =
      blob.processing_metadata["inbound_email_id"] ||
        blob.processing_metadata[:inbound_email_id]

    attrs =
      extracted_metadata
      |> Map.delete("document_type")
      |> Map.put("total_amount", -extracted_metadata["total_amount"])
      |> Map.put("organization_id", blob.organization_id)
      |> Map.put("blob_id", blob.id)
      |> maybe_put_inbound_email_id(inbound_email_id)

    case Invoicing.create_cost_invoice(attrs) do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_failure(blob, reason, opts) do
    ProcessBlobHelpers.handle_failure(
      blob,
      reason,
      opts,
      "Plik nie zawiera danych wymaganych dla faktury kosztowej."
    )
  end

  defp maybe_put_inbound_email_id(attrs, nil), do: attrs

  defp maybe_put_inbound_email_id(attrs, inbound_email_id), do: Map.put(attrs, "inbound_email_id", inbound_email_id)
end
