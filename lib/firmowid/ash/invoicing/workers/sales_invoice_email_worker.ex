defmodule Firmowid.Ash.Invoicing.Workers.SalesInvoiceEmailWorker do
  @moduledoc """
  Sends one queued sales invoice email and records the final delivery outcome.
  """

  use Oban.Worker,
    queue: :sales_invoice_emails,
    max_attempts: 2

  alias Firmowid.Ash.Invoicing.SalesInvoiceEmailDelivery
  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceEmailSender
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

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

    case SalesInvoiceEmailSender.deliver(sales_invoice_id, delivery_type, scope) do
      {:ok, attrs} ->
        record_delivery(Map.merge(attrs, %{status: :sent, sent_at: DateTime.utc_now()}), scope)

        Logger.info("Sales invoice email sent invoice_id=#{sales_invoice_id} delivery_type=#{delivery_type}")

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
        "attempt=#{job.attempt}/#{job.max_attempts} reason=#{inspect(reason)}"
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

  defp record_delivery(attrs, scope) do
    attrs
    |> SalesInvoiceEmailDelivery.changeset_to_record_delivery(scope: scope)
    |> Ash.create(scope: scope)
  end
end
