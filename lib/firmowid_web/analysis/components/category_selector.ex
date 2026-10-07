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
  attr :colors, :map, required: true
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
      |> assign(:selected_kind, if(tags == [], do: :unassigned, else: hd(tags).kind))
      |> assign(:popover_id, "category-select-#{entity_type(assigns.entry)}-#{assigns.entry.id}")
      |> assign(
        :project_ids,
        Enum.map(Enum.filter(tags, &(&1.kind == :project)), & &1.tag_definition_id)
      )

    ~H"""
    <div class="relative flex flex-wrap items-center gap-1">
      <%= if @can_write and @editable do %>
        <FirmowidWeb.DesignSystem.Components.Button.button
          id={"#{@popover_id}-trigger"}
          type="button"
          variant="unstyled"
          aria-label={gettext("Edit categories")}
          phx-click={show_popover(@popover_id)}
          aria-haspopup="true"
          class="border-grey-200 focus-visible:outline-grey-600 hover:bg-grey-50 hover:border-grey-400 text-darkGrey flex min-h-10 w-full cursor-pointer items-center justify-between gap-2 rounded-lg border bg-white px-2 py-1.5 text-left shadow-sm transition focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          <.badges tags={@tags} colors={@colors} />
          <.icon name="hero-chevron-down-mini" class="size-4 shrink-0" />
        </FirmowidWeb.DesignSystem.Components.Button.button>
        <.popover
          id={@popover_id}
          reference_id={"#{@popover_id}-trigger"}
          placement="bottom-start"
          strategy="fixed"
          class="bg-grey-50 border-grey-200 w-64 rounded-lg border"
        >
          <div class="flex max-h-80 flex-col gap-1 overflow-auto p-2">
            <FirmowidWeb.DesignSystem.Components.Button.button
              type="button"
              variant="unstyled"
              phx-click="clear-entity-tags"
              phx-value-entity_type={@type}
              phx-value-entity_id={@entry.id}
              aria-pressed={to_string(@selected_kind == :unassigned)}
              class={option_styles(@selected_kind == :unassigned)}
            >
              <.color_dot color={Map.fetch!(@colors, :unassigned)} />
              <span class="flex-1">{gettext("Unassigned")}</span>
              <.icon :if={@selected_kind == :unassigned} name="hero-check-mini" class="size-4" />
            </FirmowidWeb.DesignSystem.Components.Button.button>
            <FirmowidWeb.DesignSystem.Components.Button.button
              type="button"
              variant="unstyled"
              phx-click="set-entity-category"
              phx-value-entity_type={@type}
              phx-value-entity_id={@entry.id}
              phx-value-kind="company"
              aria-pressed={to_string(@selected_kind == :company)}
              class={option_styles(@selected_kind == :company)}
            >
              <.color_dot color={Map.fetch!(@colors, :company)} />
              <span class="flex-1">{gettext("Company")}</span>
              <.icon :if={@selected_kind == :company} name="hero-check-mini" class="size-4" />
            </FirmowidWeb.DesignSystem.Components.Button.button>
            <FirmowidWeb.DesignSystem.Components.Button.button
              type="button"
              variant="unstyled"
              phx-click="set-entity-category"
              phx-value-entity_type={@type}
              phx-value-entity_id={@entry.id}
              phx-value-kind="internal"
              aria-pressed={to_string(@selected_kind == :internal)}
              class={option_styles(@selected_kind == :internal)}
            >
              <.icon name="hero-minus-circle-mini" class="text-grey-500 size-4 shrink-0" />
              <span class="flex-1">{gettext("Omitted")}</span>
              <.icon :if={@selected_kind == :internal} name="hero-check-mini" class="size-4" />
            </FirmowidWeb.DesignSystem.Components.Button.button>
            <p class="border-grey-200 text-darkGrey border-t pt-2 text-xs">
              {gettext("Active projects")}
            </p>
            <label :for={category <- @categories} class={option_styles(category.id in @project_ids)}>
              <input
                type="checkbox"
                checked={category.id in @project_ids}
                phx-click="toggle-project-tag"
                phx-value-entity_type={@type}
                phx-value-entity_id={@entry.id}
                phx-value-tag_definition_id={category.id}
                class="border-darkGrey size-4 cursor-pointer rounded-[3px] border focus-visible:outline-2 focus-visible:outline-offset-2"
              />
              <.color_dot color={Map.fetch!(@colors, {:project, category.id})} />
              {category.name}
            </label>
            <p class="text-darkGrey text-xs">
              {gettext("Selected projects share the amount equally.")}
            </p>
          </div>
        </.popover>
      <% else %>
        <.badges tags={@tags} colors={@colors} />
      <% end %>
    </div>
    """
  end

  attr :tags, :list, required: true
  attr :colors, :map, required: true

  @doc "Renders categories, including an explicit unassigned badge for an empty list."
  @spec badges(map()) :: Rendered.t()
  def badges(assigns) do
    ~H"""
    <span class="flex flex-wrap items-center gap-1">
      <span
        :if={@tags == []}
        class="border-grey-200 text-darkGrey inline-flex items-center gap-1.5 rounded-full border bg-white px-2 py-1 text-xs"
      >
        <.color_dot color={Map.fetch!(@colors, :unassigned)} />{gettext("Unassigned")}
      </span>
      <span
        :for={tag <- @tags}
        class={[
          "text-darkGrey inline-flex items-center gap-1.5 rounded-full border px-2 py-1 text-xs",
          if(tag.kind == :internal,
            do: "bg-grey-100 border-grey-400 border-dashed",
            else: "border-grey-200 bg-white"
          )
        ]}
      >
        <.icon
          :if={tag.kind == :internal}
          name="hero-minus-circle-mini"
          class="text-grey-500 size-3.5"
        />
        <.color_dot :if={tag.kind != :internal} color={tag_color(tag, @colors)} />
        {tag_label(tag)}
      </span>
    </span>
    """
  end

  attr :color, :string, required: true

  defp color_dot(assigns) do
    ~H"""
    <span
      class="size-2.5 shrink-0 rounded-full"
      style={"background-color: #{@color}"}
      aria-hidden="true"
    />
    """
  end

  defp option_styles(selected?) do
    [
      "text-darkGrey flex min-h-10 w-full cursor-pointer items-center gap-2 rounded-md border px-3 py-2 text-left text-sm transition hover:border-grey-400 hover:bg-grey-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-grey-600",
      if(selected?,
        do: "border-grey-400 bg-grey-100 font-medium",
        else: "border-grey-200 bg-white"
      )
    ]
  end

  defp tag_color(%{kind: :company}, colors), do: Map.fetch!(colors, :company)

  defp tag_color(%{kind: :project, tag_definition_id: id}, colors), do: Map.fetch!(colors, {:project, id})

  defp tag_color(_tag, colors), do: Map.fetch!(colors, :unassigned)

  defp entity_type(%SalesInvoice{}), do: :sales_invoice
  defp entity_type(%CostInvoice{}), do: :cost_invoice
  defp entity_type(%Transaction{}), do: :transaction

  defp editable?(%Transaction{} = row), do: row.skip_invoicing

  defp editable?(row), do: row.skip_invoicing or row.transactions != []

  defp tag_label(%{kind: :company}), do: gettext("Company")
  defp tag_label(%{kind: :internal}), do: gettext("Omitted")
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
