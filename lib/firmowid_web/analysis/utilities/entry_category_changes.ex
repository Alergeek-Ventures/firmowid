defmodule FirmowidWeb.Analysis.Utilities.EntryCategoryChanges do
  @moduledoc """
  Applies the category selector's events to one invoice or transaction: a new
  project, the built-in company, taxes or omitted category, clearing, or
  toggling one of the given projects.
  """

  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope

  @type entry :: SalesInvoice.t() | CostInvoice.t() | Transaction.t()

  @doc "Applies a selector event to the entry; only the given projects may be added, any assigned one removed."
  @spec change(String.t(), map(), entry(), [TagDefinition.t()], Scope.t()) ::
          {:ok, term()} | {:error, term()}
  def change("create-category", %{"name" => name}, entry, _projects, scope) do
    entry
    |> entity_arguments()
    |> Map.put(:name, name)
    |> TagDefinition.create_for_entry(scope: scope)
  end

  def change("clear-entity-tags", _params, entry, _projects, scope) do
    EntityTag.clear_entity_tags(entity_arguments(entry), scope: scope)
  end

  def change("set-entity-category", %{"kind" => kind}, entry, _projects, scope)
      when kind in ["company", "taxes", "internal"] do
    entry
    |> entity_arguments()
    |> Map.put(:kind, kind)
    |> EntityTag.set_entity_category(scope: scope)
  end

  def change("toggle-project-tag", %{"tag_definition_id" => id}, entry, projects, scope) do
    current =
      entry.entity_tags
      |> Enum.filter(&(&1.kind == :project))
      |> Enum.map(& &1.tag_definition_id)

    if id in current or Enum.any?(projects, &(&1.id == id)) do
      ids = if id in current, do: List.delete(current, id), else: [id | current]

      entry
      |> entity_arguments()
      |> Map.put(:tag_definition_ids, ids)
      |> EntityTag.set_entity_project_tags(scope: scope)
    else
      {:error, :invalid_category}
    end
  end

  def change(_event, _params, _entry, _projects, _scope), do: {:error, :invalid_category}

  @doc "Identifies the entry for entity tag actions."
  @spec entity_arguments(entry()) :: %{entity_type: atom(), resource_id: String.t()}
  def entity_arguments(%SalesInvoice{id: id}), do: %{entity_type: :sales_invoice, resource_id: id}
  def entity_arguments(%CostInvoice{id: id}), do: %{entity_type: :cost_invoice, resource_id: id}
  def entity_arguments(%Transaction{id: id}), do: %{entity_type: :transaction, resource_id: id}
end
