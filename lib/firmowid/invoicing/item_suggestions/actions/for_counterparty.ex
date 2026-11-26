defmodule Firmowid.Invoicing.ItemSuggestions.Actions.ForCounterparty do
  @moduledoc """
  The item suggestions for an invoice to a counterparty: first the items of the
  organization's invoices to that counterparty, with their latest quantity, unit,
  price and VAT rate, then the organization's generated suggestions not among
  them. Without a counterparty, only the generated suggestions.
  """
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.ItemSuggestions.InvoicedItems
  alias Firmowid.Invoicing.ItemSuggestions.Suggestion
  alias Firmowid.Scope

  @impl true
  def run(input, _opts, context) do
    scope = %Scope{actor: context.actor, tenant: context.tenant}

    generated =
      case Invoicing.get_item_suggestions!(scope: scope) do
        %{suggestions: suggestions} -> suggestions
        nil -> []
      end

    {:ok,
     input.arguments.counterparty_id
     |> counterparty_items(scope)
     |> Enum.concat(generated)
     |> Enum.uniq_by(&String.downcase(&1.name))}
  end

  defp counterparty_items(nil, _scope), do: []

  defp counterparty_items(counterparty_id, scope) do
    scope
    |> InvoicedItems.list(counterparty_id)
    |> Enum.map(&struct!(Suggestion, Map.delete(&1, :count)))
  end
end
