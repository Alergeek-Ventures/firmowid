defmodule Firmowid.Invoicing.Validations.ValidatePositiveItemQuantities do
  @moduledoc """
  Ash validation that rejects line items with a quantity of zero or less.

  Used on regular invoices and the browser wizard. Corrections and KSeF imports
  do not use it: a correction records a removed line with quantity 0.

  ## Options

    * `:field` — the items argument to check (default: `:sales_invoice_items`)
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  alias Ash.Error.Changes.InvalidAttribute

  @doc "Returns an error on the quantity of each item whose quantity is not greater than zero."
  @spec validate(Ash.Changeset.t(), keyword(), Ash.Resource.Validation.Context.t()) ::
          :ok | {:error, [Exception.t()]}
  @impl true
  def validate(changeset, opts, _context) do
    field = opts[:field] || :sales_invoice_items

    errors =
      changeset
      |> Ash.Changeset.get_argument(field)
      |> List.wrap()
      |> Enum.with_index()
      |> Enum.flat_map(fn {item, index} ->
        if positive_or_unset?(Map.get(item, :quantity, item["quantity"])) do
          []
        else
          [
            InvalidAttribute.exception(
              field: :quantity,
              path: [field, index],
              message: gettext_noop("Quantity must be greater than zero.")
            )
          ]
        end
      end)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  # A missing or unparsable quantity is reported by the item's own attribute validation.
  defp positive_or_unset?(quantity) do
    case Decimal.cast(quantity) do
      {:ok, decimal} -> Decimal.gt?(decimal, 0)
      :error -> true
    end
  end
end
