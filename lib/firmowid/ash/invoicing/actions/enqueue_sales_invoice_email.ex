defmodule Firmowid.Ash.Invoicing.Actions.EnqueueSalesInvoiceEmail do
  @moduledoc """
  Enqueues a sales invoice email delivery job.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Invoicing.Workers.SalesInvoiceEmailWorker

  require Logger

  @impl true
  def run(input, _opts, context) do
    sales_invoice_id = input.arguments.sales_invoice_id
    delivery_type = input.arguments.delivery_type

    %{
      "organization_id" => context.tenant,
      "sales_invoice_id" => sales_invoice_id,
      "delivery_type" => Atom.to_string(delivery_type)
    }
    |> SalesInvoiceEmailWorker.new()
    |> Firmowid.Oban.insert(skip_organization_id: true)
    |> case do
      {:ok, _job} ->
        Logger.info(
          "Enqueued sales invoice email invoice_id=#{sales_invoice_id} delivery_type=#{delivery_type} org=#{context.tenant}"
        )

        {:ok, :enqueued}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
