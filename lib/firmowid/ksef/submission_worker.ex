defmodule Firmowid.Ksef.SubmissionWorker do
  @moduledoc """
  Handles sales invoice submission to KSeF.

  This worker manages the full submission lifecycle:
  1. "submit" action: Opens session, encrypts and sends invoice, closes session, schedules verification
  2. "verify" action: Polls for KSeF number until invoice is fully processed

  Each invoice gets its own session (one session per invoice).
  """
  use Oban.Worker,
    queue: :ksef_submissions,
    max_attempts: 3

  alias Firmowid.Ksef
  alias Firmowid.Ksef.ApiClient
  alias Firmowid.Ksef.InvoiceRenderer
  alias Firmowid.Ksef.SessionWorker
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => action, "organization_id" => organization_id} = args} = job) do
    Repo.put_org_id(organization_id)

    case action do
      "submit" -> submit_invoice(args)
      "verify" -> verify_invoice(args, job)
    end
  end

  defp submit_invoice(%{"sales_invoice_id" => sales_invoice_id}) do
    Logger.info("Starting KSeF submission for sales invoice #{sales_invoice_id}")

    with {:ok, invoice} <- load_invoice(sales_invoice_id),
         invoice_xml = InvoiceRenderer.render_fa3(invoice),
         access_token = SessionWorker.get_access_token!(),
         {:ok, session_data} <- ApiClient.open_online_session(access_token),
         {:ok, invoice_reference} <-
           ApiClient.send_invoice(access_token, session_data, invoice_xml),
         :ok <- ApiClient.close_online_session(access_token, session_data.session_reference) do
      Repo.transaction(fn ->
        lock_invoice(invoice, session_data.session_reference)

        schedule_verification(
          sales_invoice_id,
          session_data.session_reference,
          invoice_reference
        )
      end)

      Logger.info("Invoice #{sales_invoice_id} submitted to KSeF, reference: #{invoice_reference}")
    else
      {:error, :invoice_not_found} ->
        Logger.error("Sales invoice #{sales_invoice_id} not found")
        {:cancel, :invoice_not_found}

      {:error, :invoice_is_draft} ->
        Logger.error("Sales invoice #{sales_invoice_id} is a draft (no invoice number)")
        {:cancel, :invoice_is_draft}

      {:error, :invoice_already_submitted} ->
        Logger.error("Sales invoice #{sales_invoice_id} is already submitted")
        {:cancel, :invoice_already_submitted}

      {:error, reason} = error ->
        Logger.error("Failed to submit invoice #{sales_invoice_id}: #{inspect(reason)}")
        error
    end
  end

  defp load_invoice(sales_invoice_id) do
    invoice = SalesInvoices.get_sales_invoice(sales_invoice_id)

    cond do
      is_nil(invoice) ->
        {:error, :invoice_not_found}

      not is_nil(invoice.locked_at) ->
        {:error, :invoice_already_submitted}

      SalesInvoice.draft?(invoice) ->
        {:error, :invoice_is_draft}

      true ->
        {:ok, invoice}
    end
  end

  defp lock_invoice(invoice, session_reference) do
    invoice
    |> SalesInvoice.ksef_update_changeset(%{
      locked_at: DateTime.utc_now(:second),
      ksef_session_reference_number: session_reference
    })
    |> Repo.update!()
  end

  # Unlocks invoice for editing/resubmission while preserving ksef_session_reference_number.
  # The session reference is kept as it represents the last used session - successful or failed.
  defp unlock_invoice(invoice) do
    invoice
    |> SalesInvoice.ksef_update_changeset(%{
      ksef_number: nil,
      locked_at: nil
    })
    |> Repo.update!()
  end

  defp schedule_verification(sales_invoice_id, session_reference, invoice_reference) do
    %{
      "action" => "verify",
      "organization_id" => Repo.get_org_id(),
      "sales_invoice_id" => sales_invoice_id,
      "session_reference" => session_reference,
      "invoice_reference" => invoice_reference
    }
    |> new()
    |> Firmowid.Oban.insert!()
  end

  defp verify_invoice(
         %{
           "sales_invoice_id" => sales_invoice_id,
           "session_reference" => session_reference,
           "invoice_reference" => invoice_reference
         },
         %Oban.Job{} = job
       ) do
    Logger.info("Verifying KSeF submission for sales invoice #{sales_invoice_id}")

    sales_invoice = SalesInvoices.get_sales_invoice!(sales_invoice_id)
    access_token = SessionWorker.get_access_token!()

    access_token
    |> ApiClient.get_invoice_status(session_reference, invoice_reference)
    |> handle_verification_result(sales_invoice, job)
  rescue
    e ->
      if final_attempt?(job) do
        sales_invoice_id
        |> SalesInvoices.get_sales_invoice!()
        |> unlock_invoice()

        Ksef.broadcast_ksef_status(Repo.get_org_id(), sales_invoice_id, :failed)
      end

      reraise e, __STACKTRACE__
  end

  defp handle_verification_result({:ok, %{ksef_number: ksef_number, invoice_hash: hash}}, invoice, _job) do
    invoice
    |> SalesInvoice.ksef_update_changeset(%{
      ksef_number: ksef_number,
      ksef_invoice_checksum: hash
    })
    |> Repo.update!()

    Logger.info("Invoice #{invoice.id} received KSeF number: #{ksef_number}")
    Ksef.broadcast_ksef_status(Repo.get_org_id(), invoice.id, :submitted)
  end

  defp handle_verification_result(:pending, invoice, _job) do
    Logger.debug("Invoice #{invoice.id} still pending, will retry")
    {:snooze, 10}
  end

  defp handle_verification_result(:retry, invoice, _job) do
    Logger.debug("Invoice #{invoice.id} needs retry, will retry")

    # TODO: allow resubmitting locked invoices
    unlock_invoice(invoice)
  end

  defp handle_verification_result({:error, {:invoice_duplicate, ksef_number, session_ref}}, invoice, _job) do
    Logger.warning("Invoice #{invoice.id} is a duplicate of KSeF number #{ksef_number}")

    # TODO: prepare correction invoice draft if original invoice is different from this one
    invoice
    |> SalesInvoice.ksef_update_changeset(%{
      ksef_number: ksef_number,
      ksef_session_reference_number: session_ref
    })
    |> Repo.update!()

    Ksef.broadcast_ksef_status(Repo.get_org_id(), invoice.id, :submitted)
    :ok
  end

  defp handle_verification_result({:error, {:invoice_processing_failed, _, _} = error}, invoice, _job) do
    fail_invoice(invoice, error)
  end

  defp handle_verification_result({:error, {:unexpected_status, _, _} = error}, invoice, _job) do
    fail_invoice(invoice, error)
  end

  defp handle_verification_result({:error, reason} = error, invoice, job) do
    Logger.error("Failed to verify invoice #{invoice.id}: #{inspect(reason)}")

    if final_attempt?(job), do: fail_invoice_status(invoice)

    error
  end

  defp fail_invoice(invoice, error) do
    Logger.error("Invoice #{invoice.id} verification failed: #{inspect(error)}")
    fail_invoice_status(invoice)
    {:cancel, error}
  end

  defp fail_invoice_status(invoice) do
    unlock_invoice(invoice)
    Ksef.broadcast_ksef_status(Repo.get_org_id(), invoice.id, :failed)
  end

  defp final_attempt?(%Oban.Job{attempt: attempt, max_attempts: max_attempts}) do
    attempt >= max_attempts
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{} = job) do
    # Use exponential backoff starting from attempt 1
    corrected_attempt = 3 - (job.max_attempts - job.attempt)
    Worker.backoff(%{job | attempt: corrected_attempt})
  end
end
