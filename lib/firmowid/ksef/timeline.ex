defmodule Firmowid.Ksef.Timeline do
  @moduledoc """
  Derives KSeF timeline events from existing invoice data.

  KSeF is immutable - once an invoice is submitted, it cannot be modified.
  Corrections are separate documents that reference the original.
  This module reconstructs the timeline from existing fields without
  requiring additional event storage.
  """

  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.SalesInvoices.SalesInvoice

  @type event :: %{
          occurred_at: DateTime.t() | NaiveDateTime.t(),
          event: atom(),
          metadata: map()
        }

  @doc """
  Builds a timeline of KSeF events for a sales invoice.

  Events (in chronological order):
  - `:created` - Invoice was created in the system
  - `:confirmed` - Invoice was sent and confirmed by KSeF
  - `:correction_issued` - A correction invoice was issued (one per correction)

  The invoice must have `:corrections` preloaded for correction events to appear.
  """
  @spec for_sales_invoice(SalesInvoice.t()) :: [event()]
  def for_sales_invoice(%SalesInvoice{} = invoice) do
    []
    |> maybe_add_created_event(invoice)
    |> maybe_add_confirmed_event(invoice)
    |> maybe_add_correction_events(invoice, :sales)
    |> Enum.sort_by(& &1.occurred_at, NaiveDateTime)
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
    |> Enum.sort_by(& &1.occurred_at, NaiveDateTime)
  end

  # Sales invoice events

  defp maybe_add_created_event(events, %SalesInvoice{inserted_at: inserted_at, invoice_number: number}) do
    [
      %{
        occurred_at: inserted_at,
        event: :created,
        metadata: %{invoice_number: number}
      }
      | events
    ]
  end

  defp maybe_add_confirmed_event(events, %SalesInvoice{ksef_number: nil}), do: events

  defp maybe_add_confirmed_event(events, %SalesInvoice{locked_at: locked_at, ksef_number: ksef_number}) do
    [
      %{
        occurred_at: locked_at,
        event: :confirmed,
        metadata: %{ksef_number: ksef_number}
      }
      | events
    ]
  end

  # Cost invoice events

  defp maybe_add_downloaded_event(events, %CostInvoice{ksef_downloaded_at: nil}), do: events

  defp maybe_add_downloaded_event(events, %CostInvoice{ksef_downloaded_at: downloaded_at, ksef_number: ksef_number}) do
    [
      %{
        occurred_at: downloaded_at,
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
            occurred_at: correction.inserted_at,
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
end
