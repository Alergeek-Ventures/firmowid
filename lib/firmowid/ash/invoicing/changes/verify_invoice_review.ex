defmodule Firmowid.Ash.Invoicing.Changes.VerifyInvoiceReview do
  @moduledoc "Binds draft finalization to the complete document reviewed before confirmation."

  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Resource.Change.Context
  alias Firmowid.Ash.Invoicing.SalesInvoice.Preview

  @doc false
  @impl true
  @spec change(Ash.Changeset.t(), keyword(), Context.t()) :: Ash.Changeset.t()
  def change(changeset, _opts, context) do
    expected = Ash.Changeset.get_argument(changeset, :expected_review)
    opts = Ash.Context.to_opts(context)

    # Runs after GetAndLockForUpdate, so the preview uses the locked draft.
    Ash.Changeset.before_action(changeset, fn changeset ->
      with {:ok, invoice} <- Ash.load(changeset.data, :sales_invoice_items, opts),
           changeset = %{changeset | data: invoice},
           {:ok, preview} <- Preview.from_changeset(changeset, opts) do
        if Preview.review_snapshot(preview) == expected do
          changeset
        else
          Ash.Changeset.add_error(changeset,
            field: :input,
            message: gettext("The invoice data changed. Review the updated preview and confirm again.")
          )
        end
      else
        {:error, error} -> Ash.Changeset.add_error(changeset, error)
      end
    end)
  end
end
