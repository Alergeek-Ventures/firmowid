defmodule Firmowid.Ash.Invoicing.Workers.InboundEmailWorker do
  @moduledoc """
  Processes inbound emails by:
  1. Validating sender against organization allowlist
  2. Downloading PDF/image attachments from Resend
  3. Scheduling CostInvoiceWorker jobs for each attachment
  4. Marking inbound_email record with result
  """

  use Oban.Worker,
    queue: :inbound_emails,
    max_attempts: 3

  alias Firmowid.Accounts
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.Services.ResendClient
  alias Firmowid.Repo

  require Logger

  # TODO: replace authorize?: false + actor: %{} with system actor once available
  @bridge_opts [authorize?: false, actor: %{}]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"inbound_email_id" => id, "organization_id" => org_id}}) do
    Repo.put_org_id(org_id)
    opts = [tenant: org_id] ++ @bridge_opts
    inbound_email = Invoicing.get_inbound_email!(id, opts)

    Logger.info("Processing inbound email #{id} from #{inbound_email.sender_email}")

    case process_email(inbound_email, org_id) do
      {:ok, count} ->
        Invoicing.mark_inbound_email_processed!(inbound_email, nil, @bridge_opts)
        Logger.info("Successfully scheduled #{count} attachments from inbound email #{id}")
        :ok

      {:error, :unexpected_sender} ->
        Logger.warning("Rejecting email #{id} from unexpected sender #{inbound_email.sender_email}")

        Invoicing.mark_inbound_email_processed!(inbound_email, :unexpected_sender, @bridge_opts)
        {:error, :unexpected_sender}

      {:error, :no_attachments} ->
        Logger.info("Email #{id} has no valid attachments to process")
        Invoicing.mark_inbound_email_processed!(inbound_email, :no_attachment, @bridge_opts)
        {:error, :no_attachments}

      {:error, reason} ->
        Logger.error("Failed to process inbound email #{id}: #{inspect(reason)}")
        Invoicing.mark_inbound_email_processed!(inbound_email, :processing_failed, @bridge_opts)
        {:error, reason}
    end
  end

  defp process_email(inbound_email, org_id) do
    with :ok <- validate_sender(inbound_email, org_id),
         {:ok, attachments} <- list_and_filter_attachments(inbound_email),
         :ok <- schedule_attachments(attachments, inbound_email.id) do
      {:ok, length(attachments)}
    end
  end

  defp validate_sender(inbound_email, org_id) do
    {:ok, organization} = Accounts.get_organization(org_id)

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

  # Attachment scheduling - download and pass to upload_cost_invoice
  defp schedule_attachments(attachments, inbound_email_id) do
    results = Enum.map(attachments, &schedule_single_attachment(&1, inbound_email_id))

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {_successes, []} ->
        :ok

      {[], failures} ->
        Logger.warning("All attachments failed to schedule: #{inspect(failures)}")
        {:error, :all_attachments_failed}

      {_successes, failures} ->
        Logger.warning("Some attachments failed to schedule: #{inspect(failures)}")
        :ok
    end
  end

  defp schedule_single_attachment(attachment, inbound_email_id) do
    filename = attachment["filename"] || attachment[:filename]
    content_type = attachment["content_type"] || attachment[:content_type]
    download_url = attachment["download_url"] || attachment[:download_url]

    Logger.debug("Scheduling attachment #{filename} (#{content_type})")

    with {:ok, binary} <- ResendClient.download_attachment(download_url),
         {:ok, temp_path} <- write_to_temp_file(binary, filename),
         {:ok, _blob} <-
           Invoicing.upload_cost_invoice(temp_path, content_type, filename, inbound_email_id) do
      {:ok, filename}
    else
      {:error, reason} = error ->
        Logger.error("Failed to schedule attachment #{filename}: #{inspect(reason)}")
        error
    end
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
