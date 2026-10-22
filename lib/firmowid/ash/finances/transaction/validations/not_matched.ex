defmodule Firmowid.Ash.Finances.Transaction.Validations.NotMatched do
  @moduledoc "Rejects changes to a transaction already linked to an invoice or a salary."
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidChanges

  @impl true
  def validate(changeset, _opts, context) do
    transaction = Ash.load!(changeset.data, :reconciliation_status, Ash.Context.to_opts(context))

    if transaction.reconciliation_status == :matched do
      {:error,
       InvalidChanges.exception(
         fields: [:skip_invoicing],
         message: gettext("The transaction is already connected to an invoice or a salary. Disconnect it first.")
       )}
    else
      :ok
    end
  end
end
