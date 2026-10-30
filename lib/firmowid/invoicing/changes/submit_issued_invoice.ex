defmodule Firmowid.Invoicing.Changes.SubmitIssuedInvoice do
  @moduledoc """
  Requires an active KSeF connection and queues the submission inside the issuing transaction.

  An issued invoice must never stay numbered without being sent to KSeF, so a failure to
  queue the submission rolls back the issuance instead of leaving such an invoice behind.
  """
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Ksef
  alias Firmowid.Scope

  @doc "Validates connectivity and queues the submission job before the transaction commits."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    scope = %Scope{actor: context.actor, tenant: context.tenant}

    case Ksef.connection_status(scope: scope) do
      {:ok, %{status: :connected}} ->
        Ash.Changeset.after_action(changeset, fn _changeset, invoice ->
          enqueue(invoice, scope)
        end)

      {:ok, _status} ->
        Ash.Changeset.add_error(changeset, not_connected_error())

      {:error, error} ->
        Ash.Changeset.add_error(changeset, error)
    end
  end

  defp enqueue(invoice, scope) do
    case Ksef.submit_sales_invoice(invoice.id, scope) do
      {:ok, _job} ->
        {:ok, Map.put(invoice, :ksef_submission_status, :submitting)}

      {:error, :not_authenticated} ->
        {:error, not_connected_error()}

      {:error, _reason} ->
        {:error,
         InvalidAttribute.exception(
           field: :invoice_number,
           message: gettext_noop("The invoice could not be queued for KSeF submission. Nothing was issued.")
         )}
    end
  end

  defp not_connected_error do
    InvalidAttribute.exception(
      field: :invoice_number,
      message: gettext_noop("Connect to KSeF before issuing this invoice.")
    )
  end
end
