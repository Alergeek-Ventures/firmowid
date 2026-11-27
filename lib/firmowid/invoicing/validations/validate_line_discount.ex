defmodule Firmowid.Invoicing.Validations.ValidateLineDiscount do
  @moduledoc """
  Keeps a line discount between zero and the line value before discount.

  A negative imported line uses the same invariant in the negative direction.
  """
  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  @doc "Returns an error when a discount would change the sign of its line's net value."
  @spec validate(Ash.Changeset.t(), keyword(), Ash.Resource.Validation.Context.t()) ::
          :ok | {:error, keyword()}
  @impl true
  def validate(changeset, _opts, _context) do
    discount = Ash.Changeset.get_attribute(changeset, :discount)
    quantity = Ash.Changeset.get_attribute(changeset, :quantity)
    unit_price = Ash.Changeset.get_attribute(changeset, :unit_price)

    with %Decimal{} <- discount,
         %Decimal{} <- quantity,
         %Decimal{} <- unit_price,
         false <- within_line_value?(discount, Decimal.mult(quantity, unit_price)) do
      {:error,
       field: :discount, message: gettext_noop("Discount must be between zero and the line value before discount.")}
    else
      _ -> :ok
    end
  end

  defp within_line_value?(discount, before_discount) do
    case Decimal.compare(before_discount, 0) do
      :gt -> not Decimal.lt?(discount, 0) and not Decimal.gt?(discount, before_discount)
      :lt -> not Decimal.gt?(discount, 0) and not Decimal.lt?(discount, before_discount)
      :eq -> Decimal.eq?(discount, 0)
    end
  end
end
