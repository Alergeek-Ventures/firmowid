defmodule Firmowid.Ash.Blobs do
  @moduledoc """
  Ash domain for blob storage.

  Manages file uploads to S3, presigned URL generation, and blob lifecycle.
  Blobs are organization-scoped binary objects (PDFs, images, XML files) used
  by cost invoices, hours records, avatars, and other features.
  """
  use Ash.Domain

  alias Ash.Error.Changes.InvalidAttribute
  alias Ash.Error.Changes.InvalidChanges
  alias Ash.Error.Invalid
  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Scope

  require Ash.Query

  resources do
    resource Blob do
      define :get_blob, action: :read, get_by: [:id]

      define :create_blob, args: [:upload_path, :content_type, :original_filename]

      define :create_blob_for_processing,
        action: :create_blob,
        args: [
          :upload_path,
          :content_type,
          :original_filename,
          :processing_target,
          :processing_metadata
        ]

      define :process_blob_as_cost_invoice, action: :process_cost_invoice
      define :destroy_blob, action: :destroy
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  @doc """
  Creates a cost-invoice blob or requeues processing for an existing failed one.
  """
  @spec create_or_retry_cost_invoice_blob(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Blob.t()}
          | {:ok, :blob_reprocessing_started}
          | {:ok, :blob_already_processing}
          | {:ok, {:existing_cost_invoice, CostInvoice.t()}}
          | {:error, term()}
  def create_or_retry_cost_invoice_blob(path, content_type, original_filename, opts) do
    scope = Keyword.fetch!(opts, :scope)

    case create_blob_for_processing(
           path,
           content_type,
           original_filename,
           :cost_invoice,
           %{},
           opts
         ) do
      {:ok, blob} ->
        {:ok, blob}

      {:error, %Invalid{} = error} ->
        if blob_checksum_conflict?(error) do
          checksum = compute_checksum(path)
          retry_failed_cost_invoice_blob(checksum, scope)
        else
          {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp retry_failed_cost_invoice_blob(checksum, %Scope{} = scope) do
    opts = [scope: scope]

    query =
      Blob
      |> Ash.Query.filter(blob_checksum == ^checksum)
      |> Ash.Query.for_read(:read, %{}, opts)

    case Ash.read_one(query, opts) do
      {:ok, %Blob{} = blob} ->
        handle_existing_cost_invoice_blob(blob, opts)

      _ ->
        {:error, :blob_already_exists}
    end
  end

  defp handle_existing_cost_invoice_blob(%Blob{processing_target: :cost_invoice, processing_state: :failed} = blob, opts) do
    with {:ok, pending_blob} <-
           blob
           |> Ash.Changeset.for_update(:mark_processing_pending, %{}, opts)
           |> Ash.update(opts) do
      AshOban.run_trigger(pending_blob, :process_cost_invoice, tenant: pending_blob.organization_id)

      {:ok, :blob_reprocessing_started}
    end
  end

  defp handle_existing_cost_invoice_blob(%Blob{processing_target: :cost_invoice, processing_state: state} = blob, opts)
       when state in [:pending, :processing] do
    if linked_cost_invoice = get_cost_invoice_for_blob(blob, opts) do
      {:ok, {:existing_cost_invoice, linked_cost_invoice}}
    else
      {:ok, :blob_already_processing}
    end
  end

  defp handle_existing_cost_invoice_blob(%Blob{processing_target: :cost_invoice} = blob, opts) do
    if linked_cost_invoice = get_cost_invoice_for_blob(blob, opts) do
      {:ok, {:existing_cost_invoice, linked_cost_invoice}}
    else
      {:error, :blob_already_exists}
    end
  end

  defp handle_existing_cost_invoice_blob(_blob, _opts), do: {:error, :blob_already_exists}

  defp get_cost_invoice_for_blob(%Blob{id: blob_id}, opts) do
    case CostInvoice
         |> Ash.Query.filter(blob_id == ^blob_id)
         |> Ash.Query.for_read(:read, %{}, opts)
         |> Ash.read_one(opts) do
      {:ok, result} -> result
      {:error, _} -> nil
    end
  end

  defp blob_checksum_conflict?(%Invalid{errors: errors}) do
    Enum.any?(errors, &blob_checksum_conflict_error?/1)
  end

  defp blob_checksum_conflict_error?(%InvalidAttribute{field: :blob_checksum}), do: true

  defp blob_checksum_conflict_error?(%InvalidChanges{fields: fields}) when is_list(fields), do: :blob_checksum in fields

  defp blob_checksum_conflict_error?(_), do: false

  # sobelow_skip ["Traversal.FileModule"]
  # path comes from Briefly temp files or Phoenix uploads, not user-controlled web input.
  defp compute_checksum(upload_path) do
    upload_path
    |> Path.expand()
    |> File.stream!()
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16()
    |> String.downcase()
  end
end
