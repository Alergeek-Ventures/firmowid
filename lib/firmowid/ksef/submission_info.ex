defmodule Firmowid.Ksef.SubmissionInfo do
  @moduledoc """
  Struct representing the KSeF submission status for a sales invoice.

  Encapsulates all information about an invoice's KSeF submission lifecycle,
  including timestamps, identifiers, and error details. This provides a unified
  API for both the invoicing entries table and the timeline component.

  ## Statuses

  - `:not_submitted` - Invoice has never been submitted to KSeF
  - `:submitting` - Submission is in progress (job pending/executing)
  - `:submitted` - Successfully confirmed by KSeF (has ksef_number)
  - `:failed` - Submission was attempted but failed

  ## Examples

      # Not submitted
      %SubmissionInfo{status: :not_submitted}

      # Successfully submitted
      %SubmissionInfo{
        status: :submitted,
        ksef_number: "1234567890-20260128-ABC123",
        session_reference: "20260128-SO-...",
        submitted_at: ~U[2026-01-28 21:54:04Z],
        confirmed_at: ~U[2026-01-28 21:54:10Z]
      }

      # Failed submission
      %SubmissionInfo{
        status: :failed,
        session_reference: "20260128-SO-...",
        submitted_at: ~U[2026-01-28 21:54:04Z],
        failed_at: ~U[2026-01-28 21:54:05Z],
        error: "Błąd walidacji KSeF: nieprawidłowy kod kraju"
      }
  """

  @type status :: :not_submitted | :submitting | :submitted | :failed

  @type t :: %__MODULE__{
          status: status(),
          submitted_at: DateTime.t() | nil,
          confirmed_at: DateTime.t() | nil,
          failed_at: DateTime.t() | nil,
          ksef_number: String.t() | nil,
          session_reference: String.t() | nil,
          error: String.t() | nil
        }

  defstruct [
    :status,
    :submitted_at,
    :confirmed_at,
    :failed_at,
    :ksef_number,
    :session_reference,
    :error
  ]
end
