defmodule FirmowidWeb.Analysis.Components.ProjectCell do
  @moduledoc """
  Project selector in an invoicing table row. Entries arrive with their tags
  preloaded for the whole list. A change sends `:projects_changed` to the list,
  which reloads every row: a paying transaction shows its invoice's projects,
  and a new project gets its colour before any row shows it.
  """
  use FirmowidWeb, :live_component

  alias Firmowid.Analysis
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.SalesInvoice
  alias FirmowidWeb.Analysis.Components.CategorySelector
  alias FirmowidWeb.Analysis.Utilities.EntryCategoryChanges

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, assign(socket, :entry, load(socket.assigns.entry, socket.assigns.scope))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <CategorySelector.cell
        entry={@entry}
        categories={selectable(@projects, @entry)}
        colors={@colors}
        can_write={@can_write}
        target={@myself}
        limit={2}
      />
    </div>
    """
  end

  @impl true
  def handle_event(event, params, socket) do
    %{entry: entry, projects: projects, scope: scope} = socket.assigns

    if socket.assigns.can_write and CategorySelector.editable?(entry) do
      case EntryCategoryChanges.change(event, params, entry, projects, scope) do
        {:ok, _} ->
          send(self(), :projects_changed)
          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update categories."))}
      end
    else
      {:noreply, socket}
    end
  end

  # Projects already on the entry stay selectable, so they can be removed after they end.
  defp selectable(projects, entry) do
    assigned =
      for %{kind: :project, tag_definition: definition} <- entry.entity_tags,
          not Enum.any?(projects, &(&1.id == definition.id)),
          do: definition

    projects ++ Enum.uniq_by(assigned, & &1.id)
  end

  @doc "Loads the selector's tags for a whole list at once, leaving other entries (groups) as they are."
  @spec preload(list(), Firmowid.Scope.t()) :: list()
  def preload(entries, scope) do
    loaded =
      entries
      |> Enum.filter(&(is_struct(&1, Transaction) or is_struct(&1, CostInvoice) or is_struct(&1, SalesInvoice)))
      |> Enum.group_by(& &1.__struct__)
      |> Enum.flat_map(fn {resource, list} ->
        Ash.load!(list, loads(resource), scope: scope, lazy?: true)
      end)
      |> with_salary_tags(scope)
      |> Map.new(&{{&1.__struct__, &1.id}, &1})

    Enum.map(entries, &Map.get(loaded, {&1.__struct__, Map.get(&1, :id)}, &1))
  end

  # Entries from the list arrive loaded; one replaced elsewhere (a status change) loads again.
  defp load(%{entity_tags: tags} = entry, _scope) when is_list(tags), do: entry
  defp load(entry, scope), do: [entry] |> preload(scope) |> hd()

  # Salary transfers show the projects the analysis derives from tracked time, not stored tags.
  defp with_salary_tags(entries, scope) do
    salaries =
      Enum.filter(
        entries,
        &match?(%Transaction{salary_user_id: user_id} when not is_nil(user_id), &1)
      )

    tags = Analysis.salary_project_tags(salaries, scope)

    Enum.map(entries, fn entry ->
      case Map.fetch(tags, entry.id) do
        {:ok, salary_tags} when is_struct(entry, Transaction) ->
          %{entry | entity_tags: salary_tags}

        _stored ->
          entry
      end
    end)
  end

  # A transaction paying invoices shows their tags.
  defp loads(Transaction),
    do: [
      entity_tags: :tag_definition,
      cost_invoices: [entity_tags: :tag_definition],
      sales_invoices: [entity_tags: :tag_definition]
    ]

  defp loads(_invoice), do: [entity_tags: :tag_definition]
end
