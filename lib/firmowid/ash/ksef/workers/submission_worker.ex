defmodule Firmowid.Ash.Ksef.Workers.SubmissionWorker do
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

  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.Services.ApiClient
  alias Firmowid.Ash.Ksef.Services.InvoiceRenderer
  alias Firmowid.Ash.Ksef.Workers.SessionWorker
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Repo

  require Logger

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: Oban.Worker.result()
  def perform(%Oban.Job{args: %{"action" => action, "organization_id" => organization_id} = args} = job) do
    actor = %SystemActor{org_id: organization_id, role: :sales_invoice_processor}
    scope = %Scope{actor: actor, tenant: organization_id}

    case action do
      "submit" -> submit_invoice(args, scope)
      "verify" -> verify_invoice(args, job, scope)
    end
  end

  defp submit_invoice(%{"sales_invoice_id" => sales_invoice_id}, scope) do
    Logger.info("Starting KSeF submission for sales invoice #{sales_invoice_id}")

    with {:ok, invoice} <- load_invoice(sales_invoice_id, scope),
         invoice_xml = InvoiceRenderer.render_fa3(invoice),
         access_token = SessionWorker.get_access_token!(scope.tenant),
         {:ok, session_data} <- ApiClient.open_online_session(access_token),
         {:ok, invoice_reference} <-
           ApiClient.send_invoice(access_token, session_data, invoice_xml),
         :ok <- ApiClient.close_online_session(access_token, session_data.session_reference) do
      Repo.transaction(fn ->
        lock_invoice(invoice, session_data.session_reference, scope)

        schedule_verification(
          sales_invoice_id,
          session_data.session_reference,
          invoice_reference,
          scope.tenant
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

  defp load_invoice(sales_invoice_id, scope) do
    opts = [scope: scope]

    case SalesInvoice.by_id(
           sales_invoice_id,
           Keyword.put(opts, :load, sales_invoice_items: [:net_value, :vat_value, :gross_value])
         ) do
      {:ok, nil} ->
        {:error, :invoice_not_found}

      {:ok, invoice} ->
        cond do
          not is_nil(invoice.locked_at) ->
            {:error, :invoice_already_submitted}

          is_nil(invoice.invoice_number) ->
            {:error, :invoice_is_draft}

          true ->
            {:ok, invoice}
        end

      {:error, _} ->
        {:error, :invoice_not_found}
    end
  end

  defp lock_invoice(invoice, session_reference, scope) do
    opts = [scope: scope]

    SalesInvoice.update_ksef_fields!(
      invoice,
      %{
        locked_at: DateTime.utc_now(:second),
        ksef_session_reference_number: session_reference
      },
      opts
    )
  end

  # Unlocks invoice for editing/resubmission while preserving ksef_session_reference_number.
  # The session reference is kept as it represents the last used session - successful or failed.
  defp unlock_invoice(invoice, scope) do
    opts = [scope: scope]

    SalesInvoice.update_ksef_fields!(
      invoice,
      %{
        ksef_number: nil,
        locked_at: nil
      },
      opts
    )
  end

  defp schedule_verification(sales_invoice_id, session_reference, invoice_reference, organization_id) do
    %{
      "action" => "verify",
      "organization_id" => organization_id,
      "sales_invoice_id" => sales_invoice_id,
      "session_reference" => session_reference,
      "invoice_reference" => invoice_reference
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
    access_token = SessionWorker.get_access_token!(scope.tenant)

    access_token
    |> ApiClient.get_invoice_status(session_reference, invoice_reference)
    |> handle_verification_result(sales_invoice, job, scope)
  rescue
    e ->
      if final_attempt?(job) do
        opts = [scope: scope]
        sales_invoice = SalesInvoice.by_id!(sales_invoice_id, opts)
        unlock_invoice(sales_invoice, scope)

        Ksef.broadcast_ksef_status(scope.tenant, sales_invoice_id, :failed)
      end

      reraise e, __STACKTRACE__
  end

  defp handle_verification_result({:ok, %{ksef_number: ksef_number, invoice_hash: hash}}, invoice, _job, scope) do
    opts = [scope: scope]

    SalesInvoice.update_ksef_fields!(
      invoice,
      %{
        ksef_number: ksef_number,
        ksef_invoice_checksum: hash
      },
      opts
    )

    Logger.info("Invoice #{invoice.id} received KSeF number: #{ksef_number}")
    Ksef.broadcast_ksef_status(scope.tenant, invoice.id, :submitted)
  end

  defp handle_verification_result(:pending, invoice, _job, _scope) do
    Logger.debug("Invoice #{invoice.id} still pending, will retry")
    {:snooze, 10}
  end

  defp handle_verification_result(:retry, invoice, _job, scope) do
    Logger.debug("Invoice #{invoice.id} needs retry, will retry")

    # TODO: allow resubmitting locked invoices
    unlock_invoice(invoice, scope)
  end

  defp handle_verification_result({:error, {:invoice_duplicate, ksef_number, session_ref}}, invoice, _job, scope) do
    Logger.warning("Invoice #{invoice.id} is a duplicate of KSeF number #{ksef_number}")
    opts = [scope: scope]

    # TODO: prepare correction invoice draft if original invoice is different from this one
    SalesInvoice.update_ksef_fields!(
      invoice,
      %{
        ksef_number: ksef_number,
        ksef_session_reference_number: session_ref
      },
      opts
    )

    Ksef.broadcast_ksef_status(scope.tenant, invoice.id, :submitted)
    :ok
  end

  defp handle_verification_result({:error, {:invoice_processing_failed, _, _} = error}, invoice, _job, scope) do
    fail_invoice(invoice, error, scope)
  end

  defp handle_verification_result({:error, {:unexpected_status, _, _} = error}, invoice, _job, scope) do
    fail_invoice(invoice, error, scope)
  end

  defp handle_verification_result({:error, reason} = error, invoice, job, scope) do
    Logger.error("Failed to verify invoice #{invoice.id}: #{inspect(reason)}")

    if final_attempt?(job), do: fail_invoice_status(invoice, scope)

    error
  end

  defp fail_invoice(invoice, error, scope) do
    Logger.error("Invoice #{invoice.id} verification failed: #{inspect(error)}")
    fail_invoice_status(invoice, scope)
    {:cancel, error}
  end

  defp fail_invoice_status(invoice, scope) do
    unlock_invoice(invoice, scope)
    Ksef.broadcast_ksef_status(scope.tenant, invoice.id, :failed)
  end

  defp final_attempt?(%Oban.Job{attempt: attempt, max_attempts: max_attempts}) do
    attempt >= max_attempts
  end
end
