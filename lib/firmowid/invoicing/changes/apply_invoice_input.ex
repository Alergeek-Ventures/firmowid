defmodule Firmowid.Invoicing.Changes.ApplyInvoiceInput do
  @moduledoc "Applies typed document input through the owning invoice action's accepted fields."
  use Ash.Resource.Change

  alias Ash.Resource.Info

  @doc "Casts accepted fields and forwards supplied line items to relationship management."
  @spec change(Ash.Changeset.t(), keyword(), Ash.Resource.Change.Context.t()) :: Ash.Changeset.t()
  @impl true
  def change(changeset, _opts, _context) do
    changeset = keep_defaults(changeset)

    case Ash.Changeset.get_argument(changeset, :input) do
      nil ->
        changeset

      input ->
        # Clients may send null for fields they leave out; it must not replace a field's default.
        attributes =
          input
          |> Map.take(changeset.action.accept)
          |> Map.reject(fn {field, value} ->
            is_nil(value) and defaulted?(changeset.resource, field)
          end)

        changeset = Ash.Changeset.change_attributes(changeset, attributes)

        case Map.fetch(input, :sales_invoice_items) do
          {:ok, items} -> Ash.Changeset.set_argument(changeset, :sales_invoice_items, items)
          :error -> changeset
        end
    end
  end

  # The same holds for the fields given beside `input`: a null on a field with a default
  # means "left out", so a new invoice takes the default and a revised one keeps its value.
  defp keep_defaults(changeset) do
    Enum.reduce(changeset.action.accept, changeset, fn field, changeset ->
      cond do
        Map.fetch(changeset.attributes, field) != {:ok, nil} or
            not defaulted?(changeset.resource, field) ->
          changeset

        changeset.action_type == :create ->
          default = Info.attribute(changeset.resource, field).default
          Ash.Changeset.change_default_attribute(changeset, field, default)

        true ->
          Ash.Changeset.clear_change(changeset, field)
      end
    end)
  end

  defp defaulted?(resource, field), do: not is_nil(Info.attribute(resource, field).default)
end
