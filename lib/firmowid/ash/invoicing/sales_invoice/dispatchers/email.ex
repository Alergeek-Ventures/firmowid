defmodule Firmowid.Ash.Invoicing.SalesInvoice.Dispatchers.Email do
  @moduledoc """
  Dispatches sales invoice communication events to the email channel.
  """

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope

  require Logger

  @reminder_cadence_days 7

  @doc """
  Dispatches a sales invoice event to the email channel.
  """
  @spec dispatch(SalesInvoice.t(), :ksef_confirmed | :overdue_reminder, Scope.t()) ::
          {:ok, :dispatched | :skipped} | {:error, term()}
  def dispatch(%SalesInvoice{should_send_emails: false}, _event, _scope), do: {:ok, :skipped}

  def dispatch(%SalesInvoice{should_send_emails: true} = invoice, :ksef_confirmed, scope) do
    invoice.id
    |> Invoicing.enqueue_sales_invoice_email(ksef_confirmation_delivery_type(invoice),
      scope: scope
    )
    |> normalize_dispatch_result(invoice, scope, "KSeF confirmation")
  end

  def dispatch(%SalesInvoice{should_send_emails: true} = invoice, :overdue_reminder, scope) do
    invoice = Ash.load!(invoice, [:email_deliveries], scope: scope)

    if should_dispatch_reminder?(invoice) do
      invoice.id
      |> Invoicing.enqueue_sales_invoice_email(:reminder, scope: scope)
      |> normalize_dispatch_result(invoice, scope, "overdue reminder")
    else
      {:ok, :skipped}
    end
  end

  defp should_dispatch_reminder?(%SalesInvoice{} = invoice) do
    not last_email_delivery_failed?(invoice) and reminder_cadence_elapsed?(invoice)
  end

  defp normalize_dispatch_result({:ok, :enqueued}, _invoice, _scope, _event), do: {:ok, :dispatched}

  defp normalize_dispatch_result({:error, reason}, invoice, scope, event) do
    Logger.error(
      "Failed to dispatch #{event} email invoice_id=#{invoice.id} org=#{scope.tenant} reason=#{inspect(reason)}"
    )

    {:error, reason}
  end

  defp reminder_cadence_elapsed?(invoice) do
    case last_sent_reminder_at(invoice) do
      nil ->
        true

      %DateTime{} = sent_at ->
        Date.diff(Date.utc_today(), DateTime.to_date(sent_at)) >= @reminder_cadence_days
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

  defp ksef_confirmation_delivery_type(%SalesInvoice{ksef_invoice_kind: :kor}), do: :invoice_correction

  defp ksef_confirmation_delivery_type(%SalesInvoice{}), do: :basic

  defp to_datetime(nil), do: nil
  defp to_datetime(%DateTime{} = value), do: value
  defp to_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
end
