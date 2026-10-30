defmodule Firmowid.Invoicing.Changes.ValidateTransactionAvailability do
  @moduledoc "Checks transaction eligibility and keeps cost invoice payments on the original."

  use Ash.Resource.Change
  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Finances
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Scope

  @impl true
  def change(changeset, _opts, context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      ids = Ash.Changeset.get_argument(changeset, :transaction_ids)
      scope = Scope.new!(context.actor, context.tenant)

      available_ids =
        %{ids: ids}
        |> Finances.list_transactions!(
          query: [lock: :for_update, sort: [id: :asc]],
          load: [:invoice_matchable?],
          scope: scope
        )
        |> Enum.filter(& &1.invoice_matchable?)
        |> MapSet.new(& &1.id)

      if original_invoice?(changeset.data, scope) and
           Enum.all?(ids, &MapSet.member?(available_ids, &1)) do
        changeset
      else
        Ash.Changeset.add_error(changeset,
          field: :transaction_ids,
          message: gettext_noop("Could not link this transaction to the invoice.")
        )
      end
    end)
  end

  defp original_invoice?(%CostInvoice{} = invoice, scope) do
    invoice = Ash.load!(invoice, :original_invoice, scope: scope)
    is_nil(invoice.original_invoice)
  end

  defp original_invoice?(_invoice, _scope), do: true
end
