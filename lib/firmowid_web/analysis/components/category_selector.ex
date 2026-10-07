defmodule FirmowidWeb.Analysis.Components.CategorySelector do
  @moduledoc """
  Pure category badges and active-project selector for document tables.
  """
  use FirmowidWeb, :html

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Phoenix.LiveView.Rendered

  attr :entry, :any, required: true
  attr :categories, :list, default: []
  attr :can_write, :boolean, default: false

  @doc "Renders historical tags and an active-project-only category selector."
  @spec cell(map()) :: Rendered.t()
  def cell(assigns) do
    tags = displayed_tags(assigns.entry)

    assigns =
      assigns
      |> assign(:tags, tags)
      |> assign(:type, entity_type(assigns.entry))
      |> assign(:editable, editable?(assigns.entry))
      |> assign(:popover_id, "category-select-#{entity_type(assigns.entry)}-#{assigns.entry.id}")
      |> assign(
        :project_ids,
        Enum.map(Enum.filter(tags, &(&1.kind == :project)), & &1.tag_definition_id)
      )

    ~H"""
    <div class="relative flex flex-wrap items-center gap-1">
      <.badges tags={@tags} />
      <%= if @can_write and @editable do %>
        <FirmowidWeb.DesignSystem.Components.Button.button
          id={"#{@popover_id}-trigger"}
          type="button"
          variant="unstyled"
          aria-label={gettext("Edit categories")}
          phx-click={show_popover(@popover_id)}
          class="text-darkGrey shrink-0 rounded-md p-1"
        >
          <.icon name="hero-pencil-square-mini" class="size-4.5" />
        </FirmowidWeb.DesignSystem.Components.Button.button>
        <.popover
          id={@popover_id}
          reference_id={"#{@popover_id}-trigger"}
          placement="bottom-start"
          class="bg-grey-50 border-grey-200 w-64 rounded-lg border"
        >
          <div class="flex max-h-64 flex-col gap-1 overflow-auto p-2">
            <FirmowidWeb.DesignSystem.Components.Button.button
              type="button"
              variant="unstyled"
              phx-click="clear-entity-tags"
              phx-value-entity_type={@type}
              phx-value-entity_id={@entry.id}
              class="text-left text-sm"
            >
              {gettext("Unassigned")}
            </FirmowidWeb.DesignSystem.Components.Button.button>
            <FirmowidWeb.DesignSystem.Components.Button.button
              type="button"
              variant="unstyled"
              phx-click="set-entity-category"
              phx-value-entity_type={@type}
              phx-value-entity_id={@entry.id}
              phx-value-kind="company"
              class="text-left text-sm"
            >
              {gettext("Company")}
            </FirmowidWeb.DesignSystem.Components.Button.button>
            <p class="border-grey-200 text-darkGrey border-t pt-2 text-xs">
              {gettext("Active projects")}
            </p>
            <label :for={category <- @categories} class="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                checked={category.id in @project_ids}
                phx-click="toggle-project-tag"
                phx-value-entity_type={@type}
                phx-value-entity_id={@entry.id}
                phx-value-tag_definition_id={category.id}
                class="border-darkGrey size-4 rounded-[3px] border"
              />
              {category.name}
            </label>
            <p class="text-darkGrey text-xs">
              {gettext("Selected projects share the amount equally.")}
            </p>
          </div>
        </.popover>
      <% end %>
    </div>
    """
  end

  attr :tags, :list, required: true

  @doc "Renders categories, including an explicit unassigned badge for an empty list."
  @spec badges(map()) :: Rendered.t()
  def badges(assigns) do
    ~H"""
    <span :if={@tags == []} class="bg-grey-100 text-darkGrey rounded-full px-2 text-xs">
      {gettext("Unassigned")}
    </span>
    <span :for={tag <- @tags} class="bg-grey-100 text-darkGrey rounded-full px-2 text-xs">
      {tag_label(tag)}
    </span>
    """
  end

  defp entity_type(%SalesInvoice{}), do: :sales_invoice
  defp entity_type(%CostInvoice{}), do: :cost_invoice
  defp entity_type(%Transaction{}), do: :transaction

  defp editable?(%Transaction{} = row), do: row.skip_invoicing

  defp editable?(row), do: row.skip_invoicing or row.transactions != []

  defp tag_label(%{kind: :company}), do: gettext("Company")
  defp tag_label(%{kind: :internal}), do: gettext("Internal")
  defp tag_label(%{kind: :project, tag_definition: %{name: name}}), do: name
  defp tag_label(_), do: gettext("Project")

  defp displayed_tags(%Transaction{cost_invoices: costs, sales_invoices: sales})
       when is_list(costs) and is_list(sales) and (costs != [] or sales != []) do
    (costs ++ sales)
    |> Enum.flat_map(& &1.entity_tags)
    |> Enum.uniq_by(&{&1.kind, &1.tag_definition_id})
  end

  defp displayed_tags(%{entity_tags: tags}) when is_list(tags), do: tags
  defp displayed_tags(_entry), do: []
end
