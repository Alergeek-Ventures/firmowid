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
    |> maybe_add_correction_events(invoice, :sales)
    |> Enum.sort_by(&event_sort_key/1, DateTime)
  end

  @doc "Builds a timeline of events for a cost invoice."
  @spec for_cost_invoice(CostInvoice.t()) :: [event()]
  def for_cost_invoice(%CostInvoice{} = invoice) do
    []
    |> maybe_add_downloaded_event(invoice)
    |> maybe_add_correction_events(invoice, :cost)
    |> Enum.sort_by(&event_sort_key/1, DateTime)
  end

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

      org_id = Firmowid.Repo.get_org_id()

      submission_events =
        corrections
        |> Task.async_stream(
          fn correction ->
            Firmowid.Repo.put_org_id(org_id)
            Ksef.get_submission_info(correction)
          end,
          ordered: false
        )
        |> Enum.flat_map(fn
          {:ok, submission_info} -> maybe_add_submission_events([], submission_info)
          {:exit, reason} -> raise "Failed to fetch submission info for correction: #{inspect(reason)}"
        end)
        |> Enum.map(fn event ->
          event_type =
            case event.event do
              :submitted -> :correction_submitted
              :confirmed -> :correction_confirmed
              :failed -> :correction_failed
              _ -> raise "Unexpected event type: #{event.event}"
            end

          %{event | event: event_type}
        end)

      correction_events ++ submission_events ++ events
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

  defp to_datetime(nil), do: nil
  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")

  defp event_sort_key(%{occurred_at: nil}), do: DateTime.from_unix!(0)
  defp event_sort_key(%{occurred_at: dt}), do: dt
end
