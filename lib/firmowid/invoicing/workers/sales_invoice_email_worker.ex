defmodule Firmowid.Invoicing.Workers.SalesInvoiceEmailWorker do
  @moduledoc """
  Sends one queued sales invoice email and records the final delivery outcome.

  Every attempt of a job sends the same Resend idempotency key, so a retry
  after the provider accepted the email (lost response, node stopped before
  the job completed) does not send it again: Resend answers it with an
  idempotency conflict, because the PDF is rendered again and differs, and
  the delivery is recorded as sent. A job is not enqueued while another one
  for the same invoice and delivery type is waiting or running.
  """

  use Oban.Worker,
    queue: :sales_invoice_emails,
    max_attempts: 2,
    unique: [keys: [:sales_invoice_id, :delivery_type], period: :infinity, states: :incomplete]

  alias Firmowid.ErrorKind
  alias Firmowid.Invoicing.SalesInvoiceEmailDelivery
  alias Firmowid.Invoicing.Services.SalesInvoiceEmailSender
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    organization_id = args["organization_id"]
    sales_invoice_id = args["sales_invoice_id"]
    delivery_type = String.to_existing_atom(args["delivery_type"])

    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :sales_invoice_processor},
      tenant: organization_id
    }

    Logger.info(
      "Sending sales invoice email invoice_id=#{sales_invoice_id} delivery_type=#{delivery_type} attempt=#{job.attempt}/#{job.max_attempts}"
    )

    case SalesInvoiceEmailSender.deliver(
           sales_invoice_id,
           delivery_type,
           "sales-invoice-email-#{job.id}",
           scope
         ) do
      {:ok, attrs} ->
        record_delivery(Map.merge(attrs, %{status: :sent, sent_at: DateTime.utc_now()}), scope)

        Logger.info("Sales invoice email sent invoice_id=#{sales_invoice_id} delivery_type=#{delivery_type}")

        :ok

      # Resend keeps a key only for an email it accepted, so this answer to a retry
      # means an earlier attempt of this job already sent the email.
      {:error, attrs, {409, %{"name" => "invalid_idempotent_request"}}} when job.attempt > 1 ->
        attrs
        |> Map.delete(:error_message)
        |> Map.merge(%{status: :sent, sent_at: DateTime.utc_now()})
        |> record_delivery(scope)

        Logger.info(
          "Sales invoice email was already accepted by the provider invoice_id=#{sales_invoice_id} delivery_type=#{delivery_type}"
        )

        :ok

      {:error, attrs, reason} ->
        handle_delivery_error(attrs, reason, job, scope)

      {:cancel, reason} ->
        {:cancel, reason}
    end
  end

  defp handle_delivery_error(attrs, reason, job, scope) do
    Logger.warning(
      "Sales invoice email attempt failed invoice_id=#{attrs.sales_invoice_id} delivery_type=#{attrs.delivery_type} " <>
        "attempt=#{job.attempt}/#{job.max_attempts} reason=#{ErrorKind.classify(reason)}"
    )

    if job.attempt >= job.max_attempts do
      attrs
      |> Map.merge(%{status: :failed, resend_email_id: nil, failed_at: DateTime.utc_now()})
      |> record_delivery(scope)

      {:cancel, reason}
    else
      {:error, reason}
    end
  end

  # Raises when the record cannot be saved, so Sentry reports it. A retry of a
  # sent email reuses the job's idempotency key, so Resend does not send it again.
  defp record_delivery(attrs, scope) do
    SalesInvoiceEmailDelivery.record_delivery!(attrs, scope: scope)
  end
end
