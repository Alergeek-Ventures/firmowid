defmodule Firmowid.Blobs do
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
  alias Firmowid.Blobs.Blob
  alias Firmowid.Blobs.UploadFingerprint
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  require Ash.Query

  resources do
    resource Blob do
      define :list_blobs, action: :list
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

      define :destroy_blob, action: :destroy
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  @doc """
  Finds an existing blob by checksum within the given scope, along with its linked CostInvoice (if any).

  Used by both manual upload and KSeF flows to resolve duplicate blob conflicts.
  The query is scoped to the organization via the scope's tenant.
  """
  @spec find_blob_with_cost_invoice(String.t(), keyword()) ::
          {:ok, Blob.t(), CostInvoice.t() | nil} | {:error, :not_found}
  def find_blob_with_cost_invoice(checksum, opts) do
    with {:ok, blob} <- find_blob_by_checksum(checksum, opts) do
      cost_invoice =
        case Invoicing.get_cost_invoice_by_blob_id(blob.id, opts) do
          {:ok, invoice} -> invoice
          {:error, _} -> nil
        end

      {:ok, blob, cost_invoice}
    end
  end

  @doc """
  Finds an existing blob by checksum within the given scope.

  Used to safely reuse an existing organization-scoped blob instead of failing
  on duplicate checksum uploads.
  """
  @spec find_blob_by_checksum(String.t(), keyword()) :: {:ok, Blob.t()} | {:error, :not_found}
  def find_blob_by_checksum(checksum, opts) do
    blob_query =
      Blob
      |> Ash.Query.filter(blob_checksum == ^checksum)
      |> Ash.Query.for_read(:read, %{}, opts)

    case Ash.read_one(blob_query, opts) do
      {:ok, %Blob{} = blob} -> {:ok, blob}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Creates a blob or reuses an existing one with the same checksum.

  Makes uploads idempotent within an organization (avatars, leave attachments,
  etc.), including when the same file was uploaded previously.
  """
  @spec create_or_reuse_blob(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Blob.t()} | {:error, term()}
  def create_or_reuse_blob(path, content_type, original_filename, opts) do
    case create_blob(path, content_type, original_filename, opts) do
      {:ok, blob} ->
        {:ok, blob}

      {:error, %Invalid{} = error} ->
        if blob_checksum_conflict?(error) do
          checksum = UploadFingerprint.normalized_checksum(path, content_type)

          case find_blob_by_checksum(checksum, stored_file_opts(opts)) do
            {:ok, blob} -> {:ok, blob}
            {:error, :not_found} -> {:error, error}
          end
        else
          {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  # The uploader holds these bytes, so handing back the stored file reveals
  # nothing, even when another member's record holds it. The record the
  # uploader attaches it to is what lets them read it afterwards.
  defp stored_file_opts(opts) do
    tenant =
      case Keyword.fetch(opts, :scope) do
        {:ok, scope} -> Keyword.get(Ash.Scope.to_opts(scope), :tenant)
        :error -> Keyword.get(opts, :tenant)
      end

    [actor: %SystemActor{org_id: tenant, role: :document_blob_processor}, tenant: tenant]
  end

  @doc """
  Creates a cost-invoice blob or requeues processing for an existing failed one.

  Used by the manual upload flow where blobs are processed asynchronously via AshOban
  (Reducto AI extraction). For KSeF invoices (already-parsed XML), use `create_blob/4`
  with `find_blob_with_cost_invoice/2` for duplicate recovery instead.
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
          checksum = UploadFingerprint.normalized_checksum(path, content_type)
          handle_duplicate_cost_invoice_blob(checksum, scope)
        else
          {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp handle_duplicate_cost_invoice_blob(checksum, %Scope{} = scope) do
    opts = [scope: scope]

    case find_blob_with_cost_invoice(checksum, opts) do
      {:ok, blob, cost_invoice} ->
        recover_duplicate_cost_invoice_blob(blob, cost_invoice, opts)

      {:error, :not_found} ->
        {:error, :blob_already_exists}
    end
  end

  defp recover_duplicate_cost_invoice_blob(
         %Blob{processing_target: :cost_invoice, processing_state: :failed} = blob,
         _cost_invoice,
         opts
       ) do
    with {:ok, _pending_blob} <-
           blob
           |> Ash.Changeset.for_update(:mark_processing_pending, %{}, opts)
           |> Ash.update(opts) do
      {:ok, :blob_reprocessing_started}
    end
  end

  defp recover_duplicate_cost_invoice_blob(
         %Blob{processing_target: :cost_invoice, processing_state: state},
         cost_invoice,
         _opts
       )
       when state in [:pending, :processing] do
    if cost_invoice do
      {:ok, {:existing_cost_invoice, cost_invoice}}
    else
      {:ok, :blob_already_processing}
    end
  end

  defp recover_duplicate_cost_invoice_blob(_blob, %CostInvoice{} = cost_invoice, _opts) do
    {:ok, {:existing_cost_invoice, cost_invoice}}
  end

  defp recover_duplicate_cost_invoice_blob(_blob, nil, _opts) do
    {:error, :blob_already_exists}
  end

  defp blob_checksum_conflict?(%Invalid{errors: errors}) do
    Enum.any?(errors, &blob_checksum_conflict_error?/1)
  end

  defp blob_checksum_conflict_error?(%InvalidAttribute{field: :blob_checksum}), do: true

  defp blob_checksum_conflict_error?(%InvalidChanges{fields: fields}) when is_list(fields), do: :blob_checksum in fields

  defp blob_checksum_conflict_error?(_), do: false

  def get_processing_blobs_count(processing_target, scope) do
    processing_target
    |> Blob.query_to_list_processing(scope: scope)
    |> Ash.count!(scope: scope)
  end
end
