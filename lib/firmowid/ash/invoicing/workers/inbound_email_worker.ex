# credo:disable-for-this-file ExDNA.Credo
# Attachment processing repeats guard/scheduling flows for resilience and observability;
# removing duplication would require cross-service refactor beyond a local couple-line change.
defmodule Firmowid.Ash.Invoicing.Workers.InboundEmailWorker do
  @moduledoc """
  Processes inbound emails by:
  1. Validating sender against organization allowlist
  2. Downloading PDF/image attachments from Resend
  3. Creating processing-target blobs for each attachment
  4. Marking inbound_email record with result
  """

  use Oban.Worker,
    queue: :inbound_emails,
    max_attempts: 3

  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.Services.ResendClient
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.ErrorKind

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"inbound_email_id" => id, "organization_id" => org_id}}) do
    actor = %SystemActor{org_id: org_id, role: :cost_invoice_processor}
    scope = %Scope{actor: actor, tenant: org_id}

    opts = [scope: scope]
    inbound_email = Invoicing.get_inbound_email!(id, opts)

    Logger.info("Processing inbound email", inbound_email_id: id, organization_id: org_id)

    case process_email(inbound_email, org_id, scope) do
      {:ok, count} ->
        Invoicing.mark_inbound_email_processed!(inbound_email, nil, opts)
        Logger.info("Successfully scheduled #{count} attachments from inbound email #{id}")
        :ok

      {:error, :unexpected_sender} ->
        Logger.warning("Rejecting inbound email from unexpected sender",
          inbound_email_id: id,
          organization_id: org_id
        )

        Invoicing.mark_inbound_email_processed!(inbound_email, :unexpected_sender, opts)
        {:cancel, :unexpected_sender}

      {:error, :no_attachments} ->
        Logger.info("Email #{id} has no valid attachments to process")
        Invoicing.mark_inbound_email_processed!(inbound_email, :no_attachment, opts)
        {:cancel, :no_attachments}

      {:error, reason} ->
        Logger.error("Failed to process inbound email",
          inbound_email_id: id,
          organization_id: org_id,
          error_kind: ErrorKind.classify(reason)
        )

        Invoicing.mark_inbound_email_processed!(inbound_email, :processing_failed, opts)
        {:error, reason}
    end
  end

  defp process_email(inbound_email, org_id, scope) do
    with :ok <- validate_sender(inbound_email, org_id, scope),
         {:ok, attachments} <- list_and_filter_attachments(inbound_email),
         :ok <- schedule_attachments(attachments, inbound_email.id, scope) do
      {:ok, length(attachments)}
    end
  end

  defp validate_sender(inbound_email, org_id, scope) do
    organization = Core.get_organization!(org_id, scope: scope)

    if inbound_email.sender_email in organization.allowed_sender_emails do
      :ok
    else
      {:error, :unexpected_sender}
    end
  end

  # Attachment listing and filtering
  defp list_and_filter_attachments(inbound_email) do
    with {:ok, attachments} <- ResendClient.list_attachments(inbound_email.resend_email_id) do
      attachments
      |> Enum.filter(&valid_attachment?/1)
      |> case do
        [] -> {:error, :no_attachments}
        valid -> {:ok, valid}
      end
    end
  end

  defp valid_attachment?(attachment) do
    content_type =
      attachment["content_type"] || attachment[:content_type] || attachment["contentType"]

    String.starts_with?(content_type, "application/pdf") or
      String.starts_with?(content_type, "image/")
  end

  # Attachment scheduling - download and pass to blob processing
  defp schedule_attachments(attachments, inbound_email_id, scope) do
    results = Enum.map(attachments, &schedule_single_attachment(&1, inbound_email_id, scope))

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {_successes, []} ->
        :ok

      {[], failures} ->
        Logger.warning("All attachments failed to schedule", attachment_count: length(failures))
        {:error, :all_attachments_failed}

      {_successes, failures} ->
        Logger.warning("Some attachments failed to schedule", attachment_count: length(failures))
        :ok
    end
  end

  defp schedule_single_attachment(attachment, inbound_email_id, scope) do
    filename = attachment["filename"] || attachment[:filename]
    content_type = attachment["content_type"] || attachment[:content_type]
    download_url = attachment["download_url"] || attachment[:download_url]

    Logger.debug("Scheduling inbound attachment", content_type: content_type)

    with {:ok, binary} <- ResendClient.download_attachment(download_url),
         {:ok, temp_path} <- write_to_temp_file(binary, filename),
         {:ok, _blob} <-
           create_blob_for_cost_invoice(
             temp_path,
             content_type,
             filename,
             inbound_email_id,
             scope
           ) do
      {:ok, filename}
    else
      {:error, reason} = error ->
        Logger.error("Failed to schedule inbound attachment",
          content_type: content_type,
          error_kind: ErrorKind.classify(reason)
        )

        error
    end
  end

  defp create_blob_for_cost_invoice(temp_path, content_type, filename, inbound_email_id, scope) do
    Blobs.create_blob_for_processing(
      temp_path,
      content_type,
      filename,
      :cost_invoice,
      %{inbound_email_id: inbound_email_id},
      scope: scope
    )
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Path comes from Briefly.create/1 (OS-managed temp directory), not user input.
  defp write_to_temp_file(binary, original_filename) do
    extension = Path.extname(original_filename)

    with {:ok, path} <- Briefly.create(extname: extension),
         :ok <- File.write(path, binary) do
      {:ok, path}
    else
      {:error, reason} -> {:error, {:file_write_failed, reason}}
    end
  end
end
