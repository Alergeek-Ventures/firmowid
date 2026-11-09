defmodule Firmowid.Invoicing.FailureReporter do
  @moduledoc """
  Reports failed issuing, correcting and cancelling of invoices and failed KSeF exchange to Sentry.

  These failures are handled where they happen: the user sees the reason, or a KSeF job ends
  without retrying because the invoice was already withdrawn. Handled failures never crash,
  so nothing would report them; this module does it explicitly. Sentry's privacy filter drops
  error messages, so the operation, the error kind and the failing fields go as tags, and the
  caller's stacktrace keeps failures from different places in separate issues.
  """

  alias Firmowid.ErrorKind
  alias Firmowid.Sentry

  defmodule InvoicingError do
    @moduledoc "The Sentry event of an invoicing failure that was handled without crashing."
    defexception [:operation]

    @impl true
    def message(%{operation: operation}), do: "Invoicing operation failed: #{operation}"
  end

  @type operation ::
          :issue
          | :correct
          | :cancel
          | :finalize
          | :ksef_enqueue
          | :ksef_submission
          | :ksef_verification
          | :ksef_fetch
          | :ksef_document

  @doc "Reports the failure of an invoicing operation in the organization to Sentry."
  @spec report(term(), operation(), Ash.UUID.t() | nil, Ash.UUID.t() | nil) :: :ok
  def report(error, operation, organization_id, invoice_id \\ nil) do
    {:current_stacktrace, [_process_info, _report | caller]} =
      Process.info(self(), :current_stacktrace)

    Sentry.capture_exception(%InvoicingError{operation: operation},
      stacktrace: caller,
      event_source: :invoicing,
      tags:
        Map.reject(
          %{
            source: "invoicing",
            action: operation,
            error_kind: ErrorKind.classify(error),
            error_fields: error_fields(error),
            organization_id: organization_id,
            invoice_id: invoice_id
          },
          fn {_key, value} -> value in [nil, ""] end
        )
    )

    :ok
  end

  @doc """
  Reports a failure unless it is invalid input, which the user or the model sees and corrects.

  The KSeF queue failure also arrives as invalid input, but `SubmitIssuedInvoice` reports its cause.
  """
  @spec report_unexpected(term(), operation(), Ash.UUID.t() | nil, Ash.UUID.t() | nil) :: :ok
  def report_unexpected(error, operation, organization_id, invoice_id \\ nil) do
    if is_struct(Ash.Error.to_error_class(error), Ash.Error.Invalid),
      do: :ok,
      else: report(error, operation, organization_id, invoice_id)
  end

  # Ash errors carry a field; field names come from code, never from data. Other errors,
  # such as an Ecto changeset from a failed job insert, keep their errors in other shapes.
  defp error_fields(%{errors: errors}) when is_list(errors) do
    errors
    |> Enum.flat_map(fn
      %{field: field} when is_atom(field) and not is_nil(field) -> [field]
      _error -> []
    end)
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp error_fields(_error), do: ""
end
