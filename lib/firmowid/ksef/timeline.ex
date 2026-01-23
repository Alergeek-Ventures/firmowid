defmodule Firmowid.Ksef.Timeline do
  @moduledoc """
  Derives KSeF timeline events from existing invoice data and submission info.

  KSeF is immutable - once an invoice is submitted, it cannot be modified.
  Corrections are separate documents that reference the original.
  This module reconstructs the timeline from existing fields and submission
  status without requiring additional event storage.
  """

  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Ksef.SubmissionInfo
  alias Firmowid.SalesInvoices.SalesInvoice

  @type event :: %{
          occurred_at: DateTime.t() | NaiveDateTime.t() | nil,
          event: atom(),
          metadata: map()
        }

  @doc """
  Builds a timeline of KSeF events for a sales invoice.

  Events (in chronological order):
  - `:created` - Invoice was created in the system
  - `:submitted` - Invoice was sent to KSeF (submission attempted)
  - `:confirmed` - Invoice was confirmed by KSeF (received ksef_number)
  - `:failed` - Submission failed with an error
  - `:correction_issued` - A correction invoice was issued (one per correction)

  The invoice must have `:corrections` preloaded for correction events to appear.
  The `submission_info` parameter provides KSeF submission status and timestamps.
  """
  @spec for_sales_invoice(SalesInvoice.t(), SubmissionInfo.t()) :: [event()]
  def for_sales_invoice(%SalesInvoice{} = invoice, %SubmissionInfo{} = submission_info) do
    []
    |> maybe_add_created_event(invoice)
    |> maybe_add_submission_events(submission_info)
    |> maybe_add_correction_events(invoice, :sales)
    |> Enum.sort_by(&event_sort_key/1, DateTime)
  end

  @doc """
  Builds a timeline of KSeF events for a cost invoice.

  Events (in chronological order):
  - `:downloaded` - Invoice was downloaded from KSeF
  - `:correction_issued` - A correction invoice was issued (one per correction)

  The invoice must have `:correction_invoices` preloaded for correction events to appear.
  """
  @spec for_cost_invoice(CostInvoice.t()) :: [event()]
  def for_cost_invoice(%CostInvoice{} = invoice) do
    []
    |> maybe_add_downloaded_event(invoice)
    |> maybe_add_correction_events(invoice, :cost)
    |> Enum.sort_by(&event_sort_key/1, DateTime)
  end

  # Sales invoice events

  defp maybe_add_created_event(events, %SalesInvoice{inserted_at: inserted_at, invoice_number: number}) do
    [
      %{
        occurred_at: to_datetime(inserted_at),
        event: :created,
        metadata: %{invoice_number: number}
      }
      | events
    ]
  end

  defp maybe_add_submission_events(events, %SubmissionInfo{status: :not_submitted}), do: events

  defp maybe_add_submission_events(events, %SubmissionInfo{status: :submitting} = info) do
    # Submission in progress - show submitted event
    [
      %{
        occurred_at: info.submitted_at,
        event: :submitted,
        metadata: %{session_reference: info.session_reference}
      }
      | events
    ]
  end

  defp maybe_add_submission_events(events, %SubmissionInfo{status: :submitted} = info) do
    # Successfully confirmed - show both submitted and confirmed
    events
    |> add_submitted_event(info)
    |> add_confirmed_event(info)
  end

  defp maybe_add_submission_events(events, %SubmissionInfo{status: :failed} = info) do
    # Failed - show submitted and failed events
    events
    |> add_submitted_event(info)
    |> add_failed_event(info)
  end

  defp add_submitted_event(events, %SubmissionInfo{submitted_at: nil}), do: events

  defp add_submitted_event(events, %SubmissionInfo{} = info) do
    [
      %{
        occurred_at: info.submitted_at,
        event: :submitted,
        metadata: %{session_reference: info.session_reference}
      }
      | events
    ]
  end

  defp add_confirmed_event(events, %SubmissionInfo{} = info) do
    [
      %{
        occurred_at: info.confirmed_at || info.submitted_at,
        event: :confirmed,
        metadata: %{ksef_number: info.ksef_number}
      }
      | events
    ]
  end

  defp add_failed_event(events, %SubmissionInfo{} = info) do
    [
      %{
        occurred_at: info.failed_at || info.submitted_at,
        event: :failed,
        metadata: %{error: info.error}
      }
      | events
    ]
  end

  # Cost invoice events

  defp maybe_add_downloaded_event(events, %CostInvoice{ksef_downloaded_at: nil}), do: events

  defp maybe_add_downloaded_event(events, %CostInvoice{ksef_downloaded_at: downloaded_at, ksef_number: ksef_number}) do
    [
      %{
        occurred_at: to_datetime(downloaded_at),
        event: :downloaded,
        metadata: %{ksef_number: ksef_number}
      }
      | events
    ]
  end

  # Correction events (shared logic)

  defp maybe_add_correction_events(events, invoice, type) do
    corrections = get_corrections(invoice, type)

    if loaded?(corrections) do
      correction_events =
        Enum.map(corrections, fn correction ->
          %{
            occurred_at: to_datetime(correction.inserted_at),
            event: :correction_issued,
            metadata: build_correction_metadata(correction, type)
          }
        end)

      correction_events ++ events
    else
      events
    end
  end

  defp get_corrections(%SalesInvoice{corrections: corrections}, :sales), do: corrections
  defp get_corrections(%CostInvoice{correction_invoices: corrections}, :cost), do: corrections

  defp build_correction_metadata(correction, :sales) do
    %{
      invoice_number: correction.invoice_number,
      invoice_id: correction.id
    }
  end

  defp build_correction_metadata(correction, :cost) do
    %{
      invoice_identifier: correction.invoice_identifier,
      invoice_id: correction.id,
      ksef_number: correction.ksef_number
    }
  end

  defp loaded?(%Ecto.Association.NotLoaded{}), do: false
  defp loaded?(_), do: true

  # Convert NaiveDateTime to DateTime for consistent sorting
  defp to_datetime(nil), do: nil
  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")

  # Sort key that handles nil occurred_at (puts them at the end)
  defp event_sort_key(%{occurred_at: nil}), do: DateTime.from_unix!(0)
  defp event_sort_key(%{occurred_at: dt}), do: dt
end
