defmodule Firmowid.Analysis.Actions.ClearMonth do
  @moduledoc "Removes every category from a month's analysis entries in one transaction."
  use Ash.Resource.Actions.Implementation

  alias Firmowid.Analysis
  alias Firmowid.Analysis.EntityTag
  alias Firmowid.Scope

  @impl true
  def run(input, _opts, context) do
    scope = %Scope{actor: context.actor, tenant: context.tenant}
    month = Date.beginning_of_month(input.arguments.month)
    entries = Analysis.get_organization_entries(month, Date.end_of_month(month), scope)

    EntityTag
    |> Ash.DataLayer.transaction(fn ->
      for {type, entities} <- [
            sales_invoice: entries.sales_invoices,
            cost_invoice: entries.cost_invoices,
            transaction: entries.transactions
          ] do
        EntityTag.clear_tags_for_resources(
          EntityTag.table_for_entity_type(type),
          Enum.map(entities, & &1.id),
          scope
        )
      end
    end)
    |> case do
      {:ok, _counts} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
