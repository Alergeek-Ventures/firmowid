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

  @doc "Returns `true` if the invoice was successfully submitted to KSeF."
  @spec submitted?(t()) :: boolean()
  def submitted?(%__MODULE__{status: :submitted}), do: true
  def submitted?(%__MODULE__{}), do: false

  @doc "Returns `true` if the submission is currently in progress."
  @spec submitting?(t()) :: boolean()
  def submitting?(%__MODULE__{status: :submitting}), do: true
  def submitting?(%__MODULE__{}), do: false

  @doc "Returns whether normal invoice editing must be blocked."
  @spec editing_blocked?(map(), t()) :: boolean()
  def editing_blocked?(%{ksef_number: nil, locked_at: locked_at}, _submission_info) when not is_nil(locked_at), do: true

  def editing_blocked?(_invoice, submission_info), do: submitting?(submission_info)

  @doc """
  Returns whether a numbered invoice was issued outside KSeF, before KSeF was mandatory.
  Such invoices are kept for reference only and are neither edited nor corrected.
  """
  @spec outside_ksef?(map(), t()) :: boolean()
  def outside_ksef?(%{invoice_number: number, ksef_number: nil} = invoice, submission_info) when not is_nil(number),
    do: not editing_blocked?(invoice, submission_info)

  def outside_ksef?(_invoice, _submission_info), do: false

  @doc "Explains why an invoice issued outside KSeF cannot be edited."
  @spec outside_ksef_message() :: String.t()
  def outside_ksef_message, do: "Faktura wystawiona poza KSeF — nie można jej edytować ani korygować."

  @doc "Explains why the edit control is unavailable, for an invoice that is locked or outside KSeF."
  @spec edit_unavailable_reason(map(), t()) :: String.t()
  def edit_unavailable_reason(invoice, submission_info) do
    if outside_ksef?(invoice, submission_info),
      do: outside_ksef_message(),
      else: "Faktura jest zablokowana. Edycja będzie dostępna po zakończeniu wysyłki do KSeF."
  end

  @doc "Returns `true` if the submission failed."
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{status: :failed}), do: true
  def failed?(%__MODULE__{}), do: false

  @doc "Returns `true` if submission has been attempted (submitted, submitting, or failed)."
  @spec attempted?(t()) :: boolean()
  def attempted?(%__MODULE__{status: :not_submitted}), do: false
  def attempted?(%__MODULE__{}), do: true
end
