defmodule Firmowid.Ksef.Workers.SubmissionWorker do
  @moduledoc """
  Handles sales invoice submission to KSeF.

  This worker manages the full submission lifecycle:
  1. "submit" action: Opens session, encrypts and sends invoice, closes session, schedules verification
  2. "verify" action: Polls for KSeF number until invoice is fully processed

  Each invoice gets its own session (one session per invoice).

  A numbered invoice must not remain outside KSeF. When a submission finally fails,
  a VAT invoice returns to an unnumbered draft and a correction is deleted.
  """
  use Oban.Worker,
    queue: :ksef_submissions,
    max_attempts: 3

  alias Firmowid.ErrorKind
  alias Firmowid.Invoicing.FailureReporter
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Ksef
  alias Firmowid.Ksef.Credential
  alias Firmowid.Ksef.Services.ApiClient
  alias Firmowid.Ksef.Services.InvoiceRenderer
  alias Firmowid.Ksef.Workers.SessionWorker
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  require Logger

  @verify_snooze_seconds 10
  # How many times an invoice KSeF cancelled on its side (status 550) is sent again.
  @max_resends 3
  @resend_delay_seconds 60
  @max_verify_snooze_count 360
  @recheck_after_seconds 3600

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: Oban.Worker.result()
  def perform(%Oban.Job{args: %{"action" => action, "organization_id" => organization_id} = args} = job) do
    actor = %SystemActor{org_id: organization_id, role: :sales_invoice_processor}
    scope = %Scope{actor: actor, tenant: organization_id}

    case action do
      "submit" -> submit_invoice(args, job, scope)
      "verify" -> verify_invoice(args, job, scope)
    end
  end

  defp submit_invoice(%{"sales_invoice_id" => sales_invoice_id}, job, scope) do
    Logger.info("Starting KSeF submission for sales invoice #{sales_invoice_id}")

    with {:ok, invoice} <- load_invoice(sales_invoice_id, job, scope),
         {:ok, invoice} <- lock_invoice(invoice, scope),
         {:ok, result} <- do_ksef_submission(invoice, scope) do
      handle_submission_success(result, sales_invoice_id, job)
    else
      {:resume_verification, invoice, session_reference, invoice_reference} ->
        schedule_verification(invoice.id, session_reference, invoice_reference, job)
        Logger.info("Resumed KSeF verification for sales invoice #{invoice.id}")

      {:error, reason}
      when reason in [:invoice_not_found, :invoice_is_draft, :invoice_already_submitted] ->
        FailureReporter.report(reason, :ksef_submission, scope.tenant, sales_invoice_id)
        Ksef.broadcast_ksef_status(scope.tenant, sales_invoice_id, :failed)
        {:cancel, reason}

      {:error, reason} = error ->
        handle_submission_error(sales_invoice_id, reason, job, scope, error)
    end
  end

  # Handles the actual KSeF API interaction (session, render, send).
  # Returns {:ok, result} or {:error, reason}. Catches exceptions from render_fa3 and get_access_token!.
  defp do_ksef_submission(invoice, scope) do
    invoice_xml = InvoiceRenderer.render_fa3(invoice, scope: scope)
    access_token = SessionWorker.get_access_token!(scope.tenant)

    with {:ok, session_data} <- ApiClient.open_online_session(access_token),
         {:ok, invoice} <-
           persist_session_reference(invoice, session_data.session_reference, scope),
         {:ok, invoice_reference} <-
           ApiClient.send_invoice(access_token, session_data, invoice_xml),
         {:ok, _invoice} <- persist_invoice_reference(invoice, invoice_reference, scope) do
      maybe_close_session(access_token, session_data.session_reference)
      {:ok, {session_data.session_reference, invoice_reference}}
    end
  rescue
    e -> {:error, {:exception, e, __STACKTRACE__}}
  end

  defp handle_submission_success({session_reference, invoice_reference}, sales_invoice_id, job) do
    schedule_verification(sales_invoice_id, session_reference, invoice_reference, job)

    Logger.info("Invoice submitted to KSeF",
      invoice_id: sales_invoice_id,
      operation: "submission"
    )
  end

  defp handle_submission_error(sales_invoice_id, {:exception, e, stacktrace}, job, scope, _error) do
    maybe_unlock_invoice(sales_invoice_id, scope)

    Logger.error("Exception during KSeF submission",
      invoice_id: sales_invoice_id,
      error_kind: ErrorKind.classify(e)
    )

    if final_attempt?(job) do
      withdraw_failed_submission(sales_invoice_id, e, scope)
      {:cancel, e}
    else
      reraise e, stacktrace
    end
  end

  defp handle_submission_error(sales_invoice_id, reason, job, scope, error) do
    maybe_unlock_invoice(sales_invoice_id, scope)

    Logger.error("Failed to submit invoice",
      invoice_id: sales_invoice_id,
      error_kind: ErrorKind.classify(reason)
    )

    if final_attempt?(job) do
      withdraw_failed_submission(sales_invoice_id, reason, scope)
      {:cancel, reason}
    else
      error
    end
  end

  defp load_invoice(sales_invoice_id, job, scope) do
    case SalesInvoice.by_id(sales_invoice_id,
           scope: scope,
           load: [sales_invoice_items: [:net_value, :vat_value, :gross_value]],
           not_found_error?: false
         ) do
      {:ok, nil} -> {:error, :invoice_not_found}
      {:ok, invoice} -> load_invoice_state(invoice, job)
      {:error, _error} = error -> error
    end
  end

  defp lock_invoice(invoice, scope) do
    opts = [scope: scope]

    updated_invoice =
      SalesInvoice.start_ksef_submission!(invoice, opts)

    {:ok, updated_invoice}
  end

  defp persist_session_reference(invoice, session_reference, scope) do
    opts = [scope: scope]

    updated_invoice =
      SalesInvoice.record_ksef_submission!(
        invoice,
        %{ksef_session_reference_number: session_reference},
        opts
      )

    {:ok, updated_invoice}
  end

  defp persist_invoice_reference(invoice, invoice_reference, scope) do
    opts = [scope: scope]

    updated_invoice =
      SalesInvoice.record_ksef_submission!(
        invoice,
        %{ksef_invoice_checksum: pending_invoice_reference(invoice_reference)},
        opts
      )

    {:ok, updated_invoice}
  end

  defp maybe_close_session(access_token, session_reference) do
    case ApiClient.close_online_session(access_token, session_reference) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to close KSeF session after submission; continuing verification",
          error_kind: ErrorKind.classify(reason)
        )
    end
  end

  defp maybe_unlock_invoice(sales_invoice_id, scope) do
    opts = [scope: scope]

    case SalesInvoice.by_id(sales_invoice_id, opts) do
      {:ok, %{ksef_number: nil} = invoice} ->
        if pending_verification_context(invoice) == :error and not is_nil(invoice.locked_at) do
          unlock_invoice(invoice, scope)
        end

      _ ->
        :ok
    end
  end

  defp pending_verification_context(invoice) do
    with session_reference when is_binary(session_reference) <-
           invoice.ksef_session_reference_number,
         checksum when is_binary(checksum) <- invoice.ksef_invoice_checksum,
         "pending_ref:" <> invoice_reference <- checksum do
      {:ok, session_reference, invoice_reference}
    else
      _ -> :error
    end
  end

  defp pending_invoice_reference(invoice_reference) do
    "pending_ref:" <> invoice_reference
  end

  defp load_invoice_state(invoice, job) do
    case pending_verification_context(invoice) do
      {:ok, session_reference, invoice_reference} ->
        {:resume_verification, invoice, session_reference, invoice_reference}

      :error ->
        cond do
          # A retry that finds the invoice locked without a reference or a KSeF number was
          # interrupted while sending it. It sends again: had KSeF received the invoice, it
          # reports a duplicate of itself.
          not is_nil(invoice.locked_at) and (job.attempt == 1 or not is_nil(invoice.ksef_number)) ->
            {:error, :invoice_already_submitted}

          is_nil(invoice.invoice_number) ->
            {:error, :invoice_is_draft}

          true ->
            {:ok, invoice}
        end
    end
  end

  # Unlocks invoice for editing/resubmission while preserving ksef_session_reference_number.
  # The session reference is kept as it represents the last used session - successful or failed.
  defp unlock_invoice(invoice, scope) do
    opts = [scope: scope]

    SalesInvoice.withdraw_ksef_submission!(invoice, opts)
  end

  defp schedule_verification(sales_invoice_id, session_reference, invoice_reference, %Oban.Job{args: args}) do
    %{
      "action" => "verify",
      "organization_id" => args["organization_id"],
      "sales_invoice_id" => sales_invoice_id,
      "session_reference" => session_reference,
      "invoice_reference" => invoice_reference,
      "resends" => Map.get(args, "resends", 0)
    }
    |> new()
    |> Firmowid.Oban.insert!(skip_organization_id: true)
  end

  defp verify_invoice(
         %{
           "sales_invoice_id" => sales_invoice_id,
           "session_reference" => session_reference,
           "invoice_reference" => invoice_reference
         },
         %Oban.Job{} = job,
         scope
       ) do
    Logger.info("Verifying KSeF submission for sales invoice #{sales_invoice_id}")

    opts = [scope: scope]
    sales_invoice = SalesInvoice.by_id!(sales_invoice_id, opts)

    result =
      with :ok <- ensure_connected(scope.tenant),
           {:ok, access_token} <- SessionWorker.get_access_token(scope.tenant) do
        ApiClient.get_invoice_status(access_token, session_reference, invoice_reference)
      end

    handle_verification_result(result, sales_invoice, job, scope)
  end

  # Without a usable credential no session can be renewed (a reconnecting one has no refresh token yet),
  # and a reauthentication job would only cancel.
  defp ensure_connected(organization_id) do
    actor = %SystemActor{org_id: organization_id, role: :ksef_session}

    case Credential.get_internal!(scope: %Scope{actor: actor, tenant: organization_id}) do
      %Credential{status: status} when status in [:working, :refreshing] -> :ok
      _no_usable_credential -> :disconnected
    end
  end

  defp handle_verification_result({:ok, %{ksef_number: ksef_number, invoice_hash: hash}}, invoice, _job, scope) do
    opts = [scope: scope]

    SalesInvoice.confirm_in_ksef!(
      invoice,
      %{
        ksef_number: ksef_number,
        ksef_invoice_checksum: hash
      },
      opts
    )

    Logger.info("Invoice received KSeF confirmation",
      invoice_id: invoice.id,
      operation: "verification"
    )

    Ksef.broadcast_ksef_status(scope.tenant, invoice.id, :submitted)
  end

  defp handle_verification_result(:pending, invoice, job, _scope) do
    # A snooze does not use up an attempt; Oban counts snoozes in the job's meta.
    snooze_count = Map.get(job.meta, "snoozed", 0)

    # KSeF has not rejected the invoice, so it stays numbered and locked and is checked hourly from then on.
    if snooze_count >= @max_verify_snooze_count do
      FailureReporter.report(:pending, :ksef_verification, invoice.organization_id, invoice.id)
      {:snooze, @recheck_after_seconds}
    else
      Logger.debug("Invoice #{invoice.id} still pending, will retry")
      {:snooze, @verify_snooze_seconds}
    end
  end

  # The invoice stays locked and numbered until the organization reconnects to KSeF.
  defp handle_verification_result(:disconnected, invoice, _job, _scope) do
    Logger.info("KSeF is disconnected; checking the invoice again later", invoice_id: invoice.id)
    {:snooze, @recheck_after_seconds}
  end

  # KSeF cancelled the processing on its side and asks to send the invoice again.
  defp handle_verification_result(:retry, invoice, job, scope) do
    resends = Map.get(job.args, "resends", 0)

    cond do
      # A repeated run of this job finds the invoice already sent again or withdrawn.
      invoice.ksef_invoice_checksum != pending_invoice_reference(job.args["invoice_reference"]) ->
        :ok

      resends < @max_resends ->
        Logger.warning("KSeF asked to resubmit the invoice; sending it again",
          invoice_id: invoice.id,
          operation: "verification"
        )

        {:ok, _job} =
          Ash.transact(SalesInvoice, fn ->
            unlock_invoice(invoice, scope)

            %{
              "action" => "submit",
              "organization_id" => scope.tenant,
              "sales_invoice_id" => invoice.id,
              "resends" => resends + 1
            }
            |> new(schedule_in: @resend_delay_seconds)
            |> Firmowid.Oban.insert!(skip_organization_id: true)
          end)

      true ->
        withdraw_failed_submission(invoice.id, :retry, scope)
    end

    :ok
  end

  defp handle_verification_result({:error, {:invoice_duplicate, ksef_number, session_ref}}, invoice, job, scope) do
    case stored_invoice_hash(invoice, ksef_number, job, scope) do
      {:ok, hash} ->
        handle_verification_result(
          {:ok, %{ksef_number: ksef_number, invoice_hash: hash}},
          invoice,
          job,
          scope
        )

      :other_document ->
        Logger.warning("Invoice matched existing KSeF document; rejecting submission",
          invoice_id: invoice.id,
          operation: "verification"
        )

        withdraw_failed_submission(invoice.id, :invoice_duplicate, scope)
        {:cancel, {:invoice_duplicate, ksef_number, session_ref}}

      {:error, _reason} = error ->
        handle_verification_result(error, invoice, job, scope)
    end
  end

  defp handle_verification_result({:error, {:invoice_processing_failed, _, _} = error}, invoice, _job, scope) do
    fail_invoice(invoice, error, scope)
  end

  defp handle_verification_result({:error, reason} = error, invoice, job, _scope) do
    Logger.error("Failed to verify invoice",
      invoice_id: invoice.id,
      error_kind: ErrorKind.classify(reason)
    )

    # An unreadable status is not a rejection; keep the invoice locked and retry.
    if final_attempt?(job) do
      FailureReporter.report(reason, :ksef_verification, invoice.organization_id, invoice.id)
      {:snooze, @recheck_after_seconds}
    else
      error
    end
  end

  # An invoice sent again after KSeF had accepted an earlier sending whose response was lost
  # (a timed-out request is retried) is rejected as a duplicate of itself. The document KSeF
  # stores is then this invoice, rendered at another moment, and its number is the invoice's.
  defp stored_invoice_hash(_invoice, nil, _job, _scope), do: :other_document

  defp stored_invoice_hash(invoice, ksef_number, job, scope) do
    with {:ok, access_token} <- SessionWorker.get_access_token(scope.tenant),
         {:ok, stored} <- ApiClient.get_invoice_xml(access_token, ksef_number) do
      rendered = invoice |> InvoiceRenderer.render_fa3(scope: scope) |> IO.iodata_to_binary()

      if without_creation_time(stored) == without_creation_time(rendered),
        do: {:ok, Ksef.compute_fa3_checksum(stored)},
        else: :other_document
    else
      # KSeF does not give the seller the document, so it is not this invoice. A document KSeF
      # has just numbered may not be readable yet, so only the last attempt concludes that.
      {:error, {:unexpected_response, status, _body}} = error when status in 400..499 ->
        if final_attempt?(job), do: :other_document, else: error

      {:error, _reason} = error ->
        error
    end
  end

  defp without_creation_time(xml), do: String.replace(xml, ~r|<DataWytworzeniaFa>[^<]*</DataWytworzeniaFa>|, "")

  defp fail_invoice(invoice, error, scope) do
    Logger.error("Invoice verification failed",
      invoice_id: invoice.id,
      error_kind: ErrorKind.classify(error)
    )

    withdraw_failed_submission(invoice.id, error, scope)
    {:cancel, error}
  end

  # Terminal failure: a numbered document must not stay outside KSeF.
  defp withdraw_failed_submission(sales_invoice_id, reason, scope) do
    FailureReporter.report(reason, :ksef_submission, scope.tenant, sales_invoice_id)

    case SalesInvoice.by_id(sales_invoice_id, scope: scope) do
      {:ok, %{ksef_number: nil, ksef_invoice_kind: :vat} = invoice} ->
        SalesInvoice.return_to_draft!(invoice, scope: scope)

        Logger.info("Returned invoice KSeF did not accept to a draft",
          invoice_id: sales_invoice_id
        )

      {:ok, %{ksef_number: nil, ksef_invoice_kind: :kor} = invoice} ->
        invoice
        |> unlock_invoice(scope)
        |> delete_failed_correction(scope)

      _accepted_or_missing ->
        :ok
    end

    Ksef.broadcast_ksef_status(scope.tenant, sales_invoice_id, :failed)
  end

  defp delete_failed_correction(correction, scope) do
    case SalesInvoice.destroy(correction, scope: scope) do
      :ok ->
        Logger.info("Deleted correction KSeF did not accept", invoice_id: correction.id)

      {:error, reason} ->
        FailureReporter.report(reason, :ksef_submission, scope.tenant, correction.id)
    end
  end

  defp final_attempt?(%Oban.Job{attempt: attempt, max_attempts: max_attempts}) do
    attempt >= max_attempts
  end
end
