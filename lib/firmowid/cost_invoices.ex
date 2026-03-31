defmodule Firmowid.CostInvoices do
  @moduledoc false
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Ash.Error.Unknown
  alias Ash.Error.Unknown.UnknownError
  alias Firmowid.Ash.Billing.Limits, as: AshLimits
  alias Firmowid.Ash.Blobs.Blob, as: AshBlob
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Ksef
  alias Firmowid.Repo

  require Logger

  @correction_invoice_types [:kor, :kor_zal, :kor_roz]

  @cost_invoice_broadcast_topic "cost_invoice_broadcast_topic"

  def authorize(action, %{role: :admin, organization_id: org_id}, %{organization_id: org_id})
      when action in [:show, :update, :delete], do: true

  def authorize(:upload, %{role: :admin}, _), do: true
  def authorize(:read_inbox, %{role: :admin}, _), do: true
  def authorize(_, _, _), do: false

  def subscribe_cost_invoice_broadcast(organization_id) do
    Phoenix.PubSub.subscribe(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{organization_id}"
    )
  end

  def broadcast_cost_invoice_added(cost_invoice) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{cost_invoice.organization_id}",
      {:cost_invoice_added, cost_invoice}
    )
  end

  def broadcast_cost_invoice_list_updated(organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{organization_id}",
      :cost_invoice_list_updated
    )
  end

  def broadcast_cost_invoice_failed_to_process(original_filename, organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{organization_id}",
      {:cost_invoice_failed_to_process, original_filename}
    )
  end

  def broadcast_invalid_document_uploaded(original_filename, organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@cost_invoice_broadcast_topic}:#{organization_id}",
      {:invalid_document_uploaded, original_filename}
    )
  end

  def get_processing_cost_invoices_count do
    Oban.Job
    |> where(
      [j],
      j.state in ["available", "scheduled", "executing"] and
        fragment("args->>'name' = ?", "extract_cost_invoice_metadata")
    )
    |> Repo.aggregate(:count, oban_jobs: true)
  end

  @doc """
  Deletes a cost invoice by ID.

  Note: The billing counter decrement happens outside the delete transaction.
  This is intentional - billing limits are soft limits (informational only),
  so we prioritize successful invoice deletion over counter accuracy.
  If the decrement fails, a warning is logged but the invoice is still deleted.
  Counter drift is acceptable for soft limit tracking.
  """
  def delete_cost_invoice(cost_invoice_id) do
    # use SQL cascading
    cost_invoice =
      CostInvoice
      |> Repo.get!(cost_invoice_id)
      |> Repo.preload(:blob)

    if CostInvoice.ksef_imported?(cost_invoice) do
      raise "Cost invoice #{cost_invoice_id} is imported from KSeF and cannot be deleted"
    end

    organization_id = cost_invoice.organization_id

    if !correction_invoice?(cost_invoice) do
      case AshLimits.decrement(organization_id, :cost_invoices, authorize?: false, actor: %{}) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Failed to decrement cost_invoices limit: #{inspect(reason)}")
      end
    end

    blob_id = cost_invoice.blob_id
    AshBlob.destroy_blob!(blob_id, blob_opts())

    broadcast_cost_invoice_list_updated(organization_id)
  end

  def toggle_skip_invoicing(id) do
    cost_invoice = Repo.get!(CostInvoice, id)

    cost_invoice =
      cost_invoice
      |> CostInvoice.changeset(%{skip_invoicing: !cost_invoice.skip_invoicing})
      |> Repo.update!()

    broadcast_cost_invoice_list_updated(cost_invoice.organization_id)

    cost_invoice
  end

  def upload_cost_invoice(upload_path, content_type, original_filename, inbound_email_id \\ nil)

  def upload_cost_invoice(upload_path, "image/" <> _ext = content_type, original_filename, inbound_email_id) do
    create_cost_invoice_job(upload_path, content_type, original_filename, inbound_email_id)
  end

  def upload_cost_invoice(upload_path, "application/pdf" = content_type, original_filename, inbound_email_id) do
    create_cost_invoice_job(upload_path, content_type, original_filename, inbound_email_id)
  end

  def upload_cost_invoice(_upload_path, _content_type, _original_filename, _inbound_email_id) do
    {:error, :unsupported_content_type}
  end

  defp create_cost_invoice_job(upload_path, content_type, original_filename, inbound_email_id) do
    Repo.transaction(fn ->
      case AshBlob.create_blob(upload_path, content_type, original_filename, blob_opts()) do
        {:ok, blob} ->
          enqueue_extraction_job(blob, inbound_email_id)
          broadcast_cost_invoice_list_updated(blob.organization_id)
          blob

        {:error, error} ->
          handle_blob_create_error(error)
      end
    end)
  end

  defp handle_blob_create_error(%Unknown{} = error) do
    if blob_already_exists_error?(error) do
      Repo.rollback({:blob_already_exists, nil})
    else
      Logger.error("Failed to upload cost invoice: #{inspect(error)}")
      Repo.rollback(:failure)
    end
  end

  defp handle_blob_create_error(reason) do
    Logger.error("Failed to upload cost invoice: #{inspect(reason)}")
    Repo.rollback(:failure)
  end

  defp blob_already_exists_error?(%Unknown{errors: errors}) do
    Enum.any?(errors, fn
      %UnknownError{error: %Ecto.ConstraintError{constraint: constraint}} ->
        String.contains?(constraint, "blob_checksum")

      %UnknownError{error: %Ecto.Changeset{errors: changeset_errors}} ->
        Keyword.has_key?(changeset_errors, :blob_checksum)

      %UnknownError{error: error} when is_binary(error) ->
        String.contains?(error, "blob_checksum") and String.contains?(error, "has already been taken")

      _ ->
        false
    end)
  end

  defp blob_already_exists_error?(_), do: false

  defp enqueue_extraction_job(blob, inbound_email_id) do
    %{name: "extract_cost_invoice_metadata", blob_id: blob.id, organization_id: blob.organization_id}
    |> then(fn args ->
      if inbound_email_id, do: Map.put(args, :inbound_email_id, inbound_email_id), else: args
    end)
    |> Firmowid.CostInvoices.Worker.new()
    |> Firmowid.Oban.insert!()
  end

  @doc """
  Creates a cost invoice from extracted metadata.

  Note: The billing counter increment happens outside the insert transaction.
  This is intentional - billing limits are soft limits (informational only),
  so we prioritize successful invoice creation over counter accuracy.
  If the increment fails, a warning is logged but the invoice is still created.
  Counter drift is acceptable for soft limit tracking.
  """
  def create_cost_invoice(extracted_metadata) do
    # allow worker to insert the invoice
    organization_id = Map.get(extracted_metadata, "organization_id", Repo.get_org_id())

    cost_invoice =
      %CostInvoice{}
      |> CostInvoice.changeset(extracted_metadata)
      |> Repo.insert!(organization_id: organization_id)

    if !correction_invoice?(cost_invoice) do
      case AshLimits.increment(organization_id, :cost_invoices, authorize?: false, actor: %{}) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("Failed to increment cost_invoices limit: #{inspect(reason)}")
      end
    end

    broadcast_cost_invoice_added(cost_invoice)

    %{
      name: "match_cost_invoice",
      cost_invoice_id: cost_invoice.id,
      organization_id: organization_id
    }
    |> Firmowid.Invoicing.Worker.new()
    |> Firmowid.Oban.insert!()
  end

  defp correction_invoice?(%CostInvoice{invoice_type: invoice_type}) do
    invoice_type in @correction_invoice_types
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Path comes from Briefly.create/1 (OS-managed temp directory), not user input.
  def hydrate_invoice_with_fa3_blob(%{ksef_number: ksef_number, blob_id: blob_id} = invoice)
      when not is_nil(ksef_number) and is_nil(blob_id) do
    # Fetch the Ecto schema for the changeset update
    ecto_invoice = Repo.get!(CostInvoice, invoice.id)

    with {:ok, xml} <- Ksef.get_invoice_xml_by_ksef_number(ksef_number),
         {:ok, path} <- Briefly.create(extname: ".xml"),
         :ok <- File.write(path, xml),
         {:ok, blob} <- AshBlob.create_blob(path, "application/xml", "#{ksef_number}.xml", blob_opts()) do
      try do
        ecto_invoice
        |> CostInvoice.changeset(%{blob_id: blob.id})
        |> Repo.update!()

        # Return the Ash struct with blob loaded
        Ash.load!(invoice, [blob: [:url]], authorize?: false, actor: %{})
      rescue
        error ->
          AshBlob.destroy_blob!(blob.id, blob_opts())
          reraise error, __STACKTRACE__
      end
    else
      {:error, reason} ->
        Logger.error("Failed to fetch KSeF XML for cost invoice #{invoice.id}: #{inspect(reason)}")
        invoice
    end
  end

  def hydrate_invoice_with_fa3_blob(invoice), do: invoice

  # TODO: replace authorize?: false with system actor once available
  # TODO: replace authorize?: false + actor: %{} with system actor once available
  defp blob_opts, do: [tenant: Repo.get_org_id(), authorize?: false, actor: %{}]
end
