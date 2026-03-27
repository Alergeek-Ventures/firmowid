defmodule Firmowid.Invoicing.Timeline do
  @moduledoc """
  Builds a timeline for invoices from invoice fields (creation, KSeF submission, corrections).

  Used by both sales and cost invoice detail views.
  """

  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Ksef
  alias Firmowid.Ksef.SubmissionInfo
  alias Firmowid.SalesInvoices.SalesInvoice

  @type event :: %{
          occurred_at: DateTime.t() | NaiveDateTime.t() | nil,
          event: atom(),
          metadata: map()
        }

  @doc "Builds a timeline of events for a sales invoice."
  @spec for_sales_invoice(SalesInvoice.t(), SubmissionInfo.t()) :: [event()]
  def for_sales_invoice(%SalesInvoice{} = invoice, %SubmissionInfo{} = submission_info) do
    []
    |> maybe_add_created_event(invoice)
    |> maybe_add_submission_events(submission_info)
    |> maybe_add_correction_events(invoice)
    |> Enum.sort_by(&event_sort_key/1, DateTime)
  end

  @doc "Builds a timeline of events for a cost invoice."
  @spec for_cost_invoice(CostInvoice.t()) :: [event()]
  def for_cost_invoice(%CostInvoice{} = invoice) do
    []
    |> maybe_add_downloaded_event(invoice)
    |> maybe_add_correction_events(invoice)
    |> Enum.sort_by(&event_sort_key/1, DateTime)
  end

  defp maybe_add_created_event(events, %SalesInvoice{inserted_at: inserted_at, invoice_number: number}) do
    event = %{
      occurred_at: to_datetime(inserted_at),
      event: :created,
      metadata: %{invoice_number: number}
    }

    [event | events]
  end

  defp maybe_add_submission_events(events, %SubmissionInfo{status: :not_submitted}), do: events

  defp maybe_add_submission_events(events, %SubmissionInfo{status: :submitting} = info) do
    add_submitted_event(events, info)
  end

  defp maybe_add_submission_events(events, %SubmissionInfo{status: :submitted} = info) do
    events
    |> add_submitted_event(info)
    |> add_confirmed_event(info)
  end

  defp maybe_add_submission_events(events, %SubmissionInfo{status: :failed} = info) do
    events
    |> add_submitted_event(info)
    |> add_failed_event(info)
  end

  defp add_submitted_event(events, %SubmissionInfo{submitted_at: nil}), do: events

  defp add_submitted_event(events, %SubmissionInfo{} = info) do
    event = %{
      occurred_at: info.submitted_at,
      event: :submitted,
      metadata: %{session_reference: info.session_reference}
    }

    [event | events]
  end

  defp add_confirmed_event(events, %SubmissionInfo{} = info) do
    event = %{
      occurred_at: info.confirmed_at || info.submitted_at,
      event: :confirmed,
      metadata: %{ksef_number: info.ksef_number}
    }

    [event | events]
  end

  defp add_failed_event(events, %SubmissionInfo{} = info) do
    event = %{
      occurred_at: info.failed_at || info.submitted_at,
      event: :failed,
      metadata: %{error: info.error}
    }

    [event | events]
  end

  defp maybe_add_downloaded_event(events, %CostInvoice{ksef_permanent_storage_date: nil}), do: events

  defp maybe_add_downloaded_event(events, %CostInvoice{} = invoice) do
    event = %{
      occurred_at: to_datetime(invoice.ksef_permanent_storage_date),
      event: :downloaded,
      metadata: %{ksef_number: invoice.ksef_number}
    }

    [event | events]
  end

  defguardp is_loaded(corrections) when not is_struct(corrections, Ecto.Association.NotLoaded)

  defp maybe_add_correction_events(events, %SalesInvoice{corrections: corrections}) when is_loaded(corrections) do
    correction_events =
      Enum.map(corrections, fn correction ->
        %{
          occurred_at: to_datetime(correction.inserted_at),
          event: :correction_issued,
          metadata: build_correction_metadata(correction)
        }
      end)

    submission_events = correction_submission_events(corrections)

    correction_events ++ submission_events ++ events
  end

  defp maybe_add_correction_events(events, %CostInvoice{correction_invoices: corrections}) when is_loaded(corrections) do
    corrections
    |> Enum.map(fn correction ->
      %{
        occurred_at: to_datetime(correction.ksef_permanent_storage_date),
        event: :correction_downloaded,
        metadata: build_correction_metadata(correction)
      }
    end)
    |> Kernel.++(events)
  end

  defp maybe_add_correction_events(events, _invoice), do: events

  defp correction_submission_events(corrections) do
    org_id = Firmowid.Repo.get_org_id()

    corrections
    |> Task.async_stream(
      fn correction ->
        Firmowid.Repo.put_org_id(org_id)
        Ksef.get_submission_info(correction)
      end,
      ordered: false
    )
    |> Enum.reduce([], fn
      {:ok, submission_info}, acc -> maybe_add_submission_events(acc, submission_info)
      {:exit, reason}, _acc -> raise "Failed to fetch submission info for correction: #{inspect(reason)}"
    end)
    |> Enum.map(fn
      %{event: :submitted} = event -> %{event | event: :correction_submitted}
      %{event: :confirmed} = event -> %{event | event: :correction_confirmed}
      %{event: :failed} = event -> %{event | event: :correction_failed}
    end)
  end

  defp build_correction_metadata(%SalesInvoice{} = correction) do
    %{
      invoice_number: correction.invoice_number,
      invoice_id: correction.id
    }
  end

  defp build_correction_metadata(%CostInvoice{} = correction) do
    %{
      invoice_identifier: correction.invoice_identifier,
      invoice_id: correction.id,
      ksef_number: correction.ksef_number
    }
  end

  defp to_datetime(nil), do: nil
  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")

  defp event_sort_key(%{occurred_at: nil}), do: DateTime.from_unix!(0)
  defp event_sort_key(%{occurred_at: dt}), do: dt
end
