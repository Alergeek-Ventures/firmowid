defmodule Firmowid.Invoicing.Actions.WaitForKsefSubmissions do
  @moduledoc """
  Waits until KSeF accepts or rejects the given issued invoices, or until the wait limit runs
  out, and returns each invoice's submission status with its KSeF number or error.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ksef

  require Ash.Query

  # Most invoices get their KSeF number within a minute; the assistant's whole turn may last 10.
  @max_wait to_timeout(minute: 3)

  # The worker broadcasts before Oban records the job's outcome, which the status is read from,
  # so a broadcast only prompts a re-read and the interval catches the outcome recorded after it.
  @recheck_interval to_timeout(second: 5)

  @impl true
  def run(input, _opts, context) do
    opts = Ash.Context.to_opts(context)
    deadline = System.monotonic_time(:millisecond) + @max_wait

    :ok = Ksef.subscribe_ksef_status(context.tenant)

    try do
      wait(input.resource, input.arguments.invoice_ids, opts, deadline)
    after
      Ksef.unsubscribe_ksef_status(context.tenant)
      flush_status_messages()
    end
  end

  defp wait(resource, invoice_ids, opts, deadline) do
    with {:ok, statuses} <- read_statuses(resource, invoice_ids, opts) do
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining > 0 and Enum.any?(statuses, &(&1.status == :submitting)) do
        receive do
          {:ksef_invoice_status, _payload} -> :ok
        after
          min(remaining, @recheck_interval) -> :ok
        end

        wait(resource, invoice_ids, opts, deadline)
      else
        {:ok, statuses}
      end
    end
  end

  defp read_statuses(resource, invoice_ids, opts) do
    with {:ok, invoices} <-
           resource
           |> Ash.Query.filter(id in ^invoice_ids)
           |> Ash.Query.select([:id, :ksef_number, :ksef_session_reference_number, :locked_at])
           |> Ash.read(opts) do
      statuses =
        invoices
        |> Ksef.get_submission_infos()
        |> Enum.zip_with(invoices, fn info, invoice ->
          %{
            invoice_id: invoice.id,
            status: info.status,
            ksef_number: info.ksef_number,
            error: info.error
          }
        end)

      {:ok, statuses}
    end
  end

  defp flush_status_messages do
    receive do
      {:ksef_invoice_status, _payload} -> flush_status_messages()
    after
      0 -> :ok
    end
  end
end
