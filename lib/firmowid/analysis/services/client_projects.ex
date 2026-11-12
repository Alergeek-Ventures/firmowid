defmodule Firmowid.Analysis.Services.ClientProjects do
  @moduledoc """
  Gives issued sales invoices without tags the project their client always has.
  Drafts and corrections take no part.

  A client always has a project when at least two of its sales invoices were
  tagged by a human and each carries only that one project. Automatic tags never
  count as history, so assignments do not reinforce themselves, and assigned
  invoices are no longer untagged, so a repeated run changes nothing.
  """

  alias Firmowid.Analysis.EntityTag
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Scope

  require Ash.Query

  @doc """
  Assigns the client's project to each untagged sales invoice of a client that
  always has one. Assigns through `EntityTag.assign_if_unassigned/2`, so a tag set
  meanwhile wins.
  """
  @spec assign(Scope.t()) :: :ok | {:error, term()}
  def assign(scope) do
    with {:ok, invoices} <-
           SalesInvoice
           # Drafts may still change client or vanish, and a correction repeats its invoice.
           |> Ash.Query.filter(
             not is_nil(counterparty_id) and not is_nil(invoice_number) and
               not is_correction
           )
           |> Ash.Query.select([:id, :counterparty_id])
           |> Ash.Query.load(entity_tags: [:kind, :tag_definition_id, :assignment_source])
           |> Ash.read(scope: scope) do
      invoices
      |> Enum.group_by(& &1.counterparty_id)
      |> Enum.flat_map(fn {_client, invoices} ->
        case client_project(invoices) do
          nil -> []
          project_id -> for %{entity_tags: []} = invoice <- invoices, do: {invoice.id, project_id}
        end
      end)
      |> assign_projects(scope)
    end
  end

  # The one project of every invoice of the client a human tagged, when there are at least two.
  # An invoice with any human tag counts with all its tags, so a person's other choice blocks it.
  defp client_project(invoices) do
    human_tags =
      for %{entity_tags: [_ | _] = tags} <- invoices,
          Enum.any?(tags, &(&1.assignment_source == :manual)),
          do: tags

    projects =
      human_tags
      |> Enum.map(fn
        [%{kind: :project, tag_definition_id: project_id}] -> project_id
        _tags -> nil
      end)
      |> Enum.uniq()

    case {human_tags, projects} do
      {[_, _ | _], [project_id]} when project_id != nil -> project_id
      _other -> nil
    end
  end

  defp assign_projects([], _scope), do: :ok

  defp assign_projects(assignments, scope) do
    result =
      Enum.reduce_while(assignments, :ok, fn {invoice_id, project_id}, :ok ->
        case EntityTag.assign_if_unassigned(
               %{
                 entity_type: :sales_invoice,
                 resource_id: invoice_id,
                 shares: [%{kind: :project, tag_definition_id: project_id}]
               },
               scope: scope
             ) do
          {:ok, _tags} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "analysis-classification:#{scope.tenant}",
      :analysis_classification_updated
    )

    result
  end
end
