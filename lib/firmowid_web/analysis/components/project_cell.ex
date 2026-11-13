defmodule FirmowidWeb.Analysis.Components.ProjectCell do
  @moduledoc """
  Project selector in an invoicing table row. The tags of every row on screen
  load together, so rows of months not shown cost nothing. They load again when
  the list hands the rows a new `loaded_at`, which it does on every reload and
  when a row sends it `:projects_changed`: a paying transaction shows its
  invoice's projects, and a new project gets its colour before any row shows it.
  """
  use FirmowidWeb, :live_component

  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [attach_access_hook: 2]

  alias Firmowid.Analysis
  alias Firmowid.Finances.Transaction
  alias FirmowidWeb.Analysis.Components.CategorySelector
  alias FirmowidWeb.Analysis.Utilities.EntryCategoryChanges

  @impl true
  def mount(socket), do: {:ok, socket |> attach_access_hook(:scope) |> assign(:opened?, false)}

  # Every row of the list shares the scope.
  @impl true
  def update_many([{%{scope: scope}, _socket} | _] = assigns_sockets) do
    entries =
      assigns_sockets
      |> Enum.map(fn {assigns, _socket} -> assigns.entry end)
      |> load_tags(scope)

    # Assigned loaded at once, an unchanged row is not rendered again.
    Enum.zip_with(assigns_sockets, entries, fn {assigns, socket}, entry ->
      assign(socket, %{assigns | entry: entry})
    end)
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
        lazy
        opened={@opened?}
      />
    </div>
    """
  end

  # Every row holding the whole list of projects made the page several times larger,
  # so a row's selector is rendered once it is first opened.
  @impl true
  def handle_event("open-categories", _params, socket), do: {:noreply, assign(socket, :opened?, true)}

  def handle_event(event, params, socket) do
    %{entry: entry, projects: projects, scope: scope} = socket.assigns

    if socket.assigns.can_write and CategorySelector.editable?(entry) do
      case EntryCategoryChanges.change(event, params, entry, projects, scope) do
        {:ok, _} ->
          send(self(), :projects_changed)
          {:noreply, socket}

        {:error, _} ->
          LiveToast.send_toast(:error, gettext("Could not update categories."))
          {:noreply, socket}
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

  defp load_tags(entries, scope) do
    loaded =
      entries
      |> Enum.group_by(& &1.__struct__)
      |> Enum.flat_map(fn {resource, list} ->
        Ash.load!(list, loads(resource), scope: scope, lazy?: true)
      end)
      |> with_salary_tags(scope)
      |> Map.new(&{{&1.__struct__, &1.id}, &1})

    Enum.map(entries, &Map.fetch!(loaded, {&1.__struct__, &1.id}))
  end

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
