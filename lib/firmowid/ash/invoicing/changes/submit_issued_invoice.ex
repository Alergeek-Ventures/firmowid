defmodule Firmowid.Ash.Invoicing.Changes.SubmitIssuedInvoice do
  @moduledoc "Checks KSeF connectivity before saving and queues submission after commit."
  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Scope

  require Logger

  @doc "Validates connectivity and registers post-commit submission when requested."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, context) do
    if Ash.Changeset.get_argument(changeset, :submit_to_ksef) do
      scope = %Scope{actor: context.actor, tenant: context.tenant}

      case Ksef.connection_status(scope: scope) do
        {:ok, %{status: :connected}} ->
          Ash.Changeset.after_transaction(changeset, fn _changeset, result ->
            enqueue(result, scope)
          end)

        {:ok, _status} ->
          Ash.Changeset.add_error(changeset,
            field: :submit_to_ksef,
            message: gettext("Connect to KSeF before issuing this invoice.")
          )

        {:error, error} ->
          Ash.Changeset.add_error(changeset, error)
      end
    else
      changeset
    end
  end

  defp enqueue({:ok, invoice}, scope) do
    case Ksef.submit_sales_invoice(invoice.id, scope) do
      {:ok, job} ->
        invoice =
          invoice
          |> Map.put(:ksef_submission_status, :submitting)
          |> Ash.Resource.put_metadata(:ksef_submission_job_id, job.id)

        {:ok, invoice}

      {:error, error} ->
        # The document is already committed. Return it rather than inviting a duplicate issue.
        Logger.error("Issued invoice could not be queued for KSeF",
          invoice_id: invoice.id,
          error_kind: Firmowid.ErrorKind.classify(error)
        )

        invoice =
          invoice
          |> Map.put(:ksef_submission_status, :failed)
          |> Ash.Resource.put_metadata(:ksef_submission_error, error)

        {:ok, invoice}
    end
  end

  defp enqueue({:error, _error} = result, _scope), do: result
end
