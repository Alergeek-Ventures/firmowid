defmodule Firmowid.Ash.Invoicing.Actions.SendOverdueReminders do
  @moduledoc """
  Sends payment reminder emails for overdue sales invoices in a single tenant.
  """

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.Services.SalesInvoiceChain
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  require Ash.Query
  require Logger

  @first_reminder_after_days 1
  @reminder_cadence_days 7

  @doc false
  @impl true
  @spec run(Ash.ActionInput.t(), Keyword.t(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, non_neg_integer()}
  def run(_input, _opts, context) do
    organization_id = context.tenant

    scope = %Scope{
      actor: %SystemActor{org_id: organization_id, role: :sales_invoice_processor},
      tenant: organization_id
    }

    today = Date.utc_today()
    invoices = overdue_candidates(scope, today)

    Logger.info("Overdue reminder scan org=#{organization_id} candidates=#{length(invoices)}")

    {sent_count, skipped_count, failed_count} =
      Enum.reduce(invoices, {0, 0, 0}, fn invoice, {sent, skipped, failed} ->
        if should_send_reminder?(invoice, today) do
          case Invoicing.send_sales_invoice_email(invoice.id, :reminder, scope: scope) do
            {:ok, _delivery} ->
              {sent + 1, skipped, failed}

            {:error, reason} ->
              Logger.error(
                "Failed reminder send invoice_id=#{invoice.id} org=#{organization_id} reason=#{inspect(reason)}"
              )

              {sent, skipped, failed + 1}
          end
        else
          {sent, skipped + 1, failed}
        end
      end)

    Logger.info(
      "Overdue reminder scan finished org=#{organization_id} sent=#{sent_count} skipped=#{skipped_count} failed=#{failed_count}"
    )

    {:ok, sent_count}
  end

  defp overdue_candidates(scope, today) do
    SalesInvoice
    |> Ash.Query.filter(
      should_send_emails == true and
        not is_nil(invoice_number) and
        not is_nil(ksef_number) and
        not is_nil(due_date) and
        due_date < ^today and
        skip_invoicing == false and
        not exists(transactions, true)
    )
    |> Ash.Query.load([:email_deliveries])
    |> Ash.read!(scope: scope)
    |> Enum.filter(&latest_invoice?(&1, scope))
  end

  defp latest_invoice?(invoice, scope) do
    latest_invoice = SalesInvoiceChain.latest_invoice(invoice, scope: scope)

    latest_invoice.id == invoice.id
  end

  defp should_send_reminder?(invoice, today) do
    overdue_days = Date.diff(today, invoice.due_date)

    cond do
      overdue_days < @first_reminder_after_days ->
        false

      last_email_delivery_failed?(invoice) ->
        false

      true ->
        case last_sent_reminder_at(invoice) do
          nil ->
            true

          %DateTime{} = sent_at ->
            Date.diff(today, DateTime.to_date(sent_at)) >= @reminder_cadence_days
        end
    end
  end

  defp last_email_delivery_failed?(invoice) do
    case last_email_delivery(invoice) do
      %{status: :failed} -> true
      _delivery -> false
    end
  end

  defp last_email_delivery(invoice) do
    invoice.email_deliveries
    |> Enum.map(fn delivery -> {delivery, delivery_occurred_at(delivery)} end)
    |> Enum.reject(fn {_delivery, occurred_at} -> is_nil(occurred_at) end)
    |> Enum.max_by(fn {_delivery, occurred_at} -> occurred_at end, DateTime, fn -> nil end)
    |> case do
      nil -> nil
      {delivery, _occurred_at} -> delivery
    end
  end

  defp delivery_occurred_at(%{status: :sent, sent_at: sent_at, inserted_at: inserted_at}) do
    to_datetime(sent_at || inserted_at)
  end

  defp delivery_occurred_at(%{status: :failed, failed_at: failed_at, inserted_at: inserted_at}) do
    to_datetime(failed_at || inserted_at)
  end

  defp last_sent_reminder_at(invoice) do
    invoice.email_deliveries
    |> Enum.filter(&(&1.delivery_type == :reminder and &1.status == :sent))
    |> Enum.map(&to_datetime(&1.sent_at || &1.inserted_at))
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp to_datetime(nil), do: nil
  defp to_datetime(%DateTime{} = value), do: value
  defp to_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
end
