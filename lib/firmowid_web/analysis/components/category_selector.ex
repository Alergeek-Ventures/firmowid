defmodule FirmowidWeb.Analysis.Components.CategorySelector do
  @moduledoc """
  Pure category badges and category selector for document tables.
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
  attr :target, :any, default: nil

  @doc "Renders historical tags and a selector for built-in, custom and project categories."
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
    <div class="relative flex justify-end">
      <%= if @can_write and @editable do %>
        <FirmowidUI.Components.Button.button
          id={"#{@popover_id}-trigger"}
          type="button"
          variant="unstyled"
          role="combobox"
          aria-label={gettext("Edit categories")}
          aria-haspopup="listbox"
          aria-controls={"#{@popover_id}-listbox"}
          phx-click={show_popover(@popover_id)}
          class="flex min-h-9 w-full cursor-pointer items-center justify-end gap-2 rounded-md px-2 py-1 text-left text-grey-700 transition hover:bg-grey-100 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-grey-600"
        >
          <.badges tags={@tags} colors={@colors} />
          <.icon name="hero-chevron-up-down-mini" class="size-4 shrink-0 text-grey-500" />
        </FirmowidUI.Components.Button.button>
        <.popover
          id={@popover_id}
          reference_id={"#{@popover_id}-trigger"}
          placement="bottom-end"
          strategy="fixed"
          class="overflow-hidden rounded-lg border border-grey-200 bg-white"
        >
          <div id={"#{@popover_id}-combobox"} class="w-72" phx-hook=".CategoryCombobox">
            <input
              type="text"
              autocomplete="off"
              placeholder={gettext("Search categories")}
              aria-label={gettext("Search categories")}
              aria-controls={"#{@popover_id}-listbox"}
              data-combobox-input
              class="w-full border-0 border-b border-grey-200 px-3 py-2 text-sm text-grey-700 placeholder:text-grey-500 focus:ring-0 focus:outline-none"
            />
            <div
              id={"#{@popover_id}-listbox"}
              role="listbox"
              aria-multiselectable="true"
              class="flex max-h-72 flex-col overflow-y-auto p-1 transition-opacity phx-click-loading:pointer-events-none phx-click-loading:opacity-50"
            >
              <FirmowidUI.Components.Button.button
                :for={category <- @categories}
                type="button"
                variant="unstyled"
                role="option"
                aria-selected={to_string(category.id in @project_ids)}
                data-combobox-option={category.name}
                phx-click={JS.push("toggle-project-tag", loading: "##{@popover_id}-combobox")}
                phx-target={@target}
                phx-value-entity_type={@type}
                phx-value-entity_id={@entry.id}
                phx-value-tag_definition_id={category.id}
                class={option_styles()}
              >
                <.color_dot color={Map.fetch!(@colors, {:project, category.id})} />
                <span class="flex-1 truncate">{category.name}</span>
                <.icon
                  name="hero-check-mini"
                  class="invisible size-4 shrink-0 group-aria-selected:visible"
                />
              </FirmowidUI.Components.Button.button>
              <div
                :if={@categories != []}
                role="separator"
                data-combobox-separator
                class="mx-2 my-1 border-t border-grey-100"
              />
              <FirmowidUI.Components.Button.button
                type="button"
                variant="unstyled"
                role="option"
                aria-selected={to_string(@selected_kind == :company)}
                data-combobox-option={gettext("Company")}
                phx-click={JS.push("set-entity-category", loading: "##{@popover_id}-combobox")}
                phx-target={@target}
                phx-value-entity_type={@type}
                phx-value-entity_id={@entry.id}
                phx-value-kind="company"
                class={option_styles()}
              >
                <.color_dot color={Map.fetch!(@colors, :company)} />
                <span class="flex-1">{gettext("Company")}</span>
                <.icon
                  name="hero-check-mini"
                  class="invisible size-4 shrink-0 group-aria-selected:visible"
                />
              </FirmowidUI.Components.Button.button>
              <FirmowidUI.Components.Button.button
                type="button"
                variant="unstyled"
                role="option"
                aria-selected={to_string(@selected_kind == :internal)}
                data-combobox-option={gettext("Omitted")}
                phx-click={JS.push("set-entity-category", loading: "##{@popover_id}-combobox")}
                phx-target={@target}
                phx-value-entity_type={@type}
                phx-value-entity_id={@entry.id}
                phx-value-kind="internal"
                class={option_styles()}
              >
                <.omitted_dot />
                <span class="flex-1">{gettext("Omitted")}</span>
                <.icon
                  name="hero-check-mini"
                  class="invisible size-4 shrink-0 group-aria-selected:visible"
                />
              </FirmowidUI.Components.Button.button>
              <FirmowidUI.Components.Button.button
                type="button"
                variant="unstyled"
                role="option"
                aria-selected={to_string(@selected_kind == :taxes)}
                data-combobox-option={gettext("Taxes")}
                phx-click={JS.push("set-entity-category", loading: "##{@popover_id}-combobox")}
                phx-target={@target}
                phx-value-entity_type={@type}
                phx-value-entity_id={@entry.id}
                phx-value-kind="taxes"
                class={option_styles()}
              >
                <.color_dot color={Map.fetch!(@colors, :taxes)} />
                <span class="flex-1">{gettext("Taxes")}</span>
                <.icon
                  name="hero-check-mini"
                  class="invisible size-4 shrink-0 group-aria-selected:visible"
                />
              </FirmowidUI.Components.Button.button>
              <FirmowidUI.Components.Button.button
                type="button"
                variant="unstyled"
                role="option"
                aria-selected="false"
                hidden
                data-combobox-create
                phx-click={JS.push("create-category", loading: "##{@popover_id}-combobox")}
                phx-target={@target}
                phx-value-entity_type={@type}
                phx-value-entity_id={@entry.id}
                class={option_styles()}
              >
                <.icon name="hero-plus-mini" class="size-4 shrink-0" />
                <span class="shrink-0">{gettext("New category")}</span>
                <span class="min-w-0 truncate font-medium" data-combobox-create-name />
              </FirmowidUI.Components.Button.button>
            </div>
            <div class="flex items-center justify-between gap-2 border-t border-grey-200 px-3 py-2 text-xs text-grey-700">
              <.icon
                name="hero-arrow-path-mini"
                class="invisible size-4 shrink-0 animate-spin phx-click-loading:visible"
              />
              <FirmowidUI.Components.Button.button
                type="button"
                variant="unstyled"
                disabled={@selected_kind == :unassigned}
                phx-click={JS.push("clear-entity-tags", loading: "##{@popover_id}-combobox")}
                phx-target={@target}
                phx-value-entity_type={@type}
                phx-value-entity_id={@entry.id}
                class="shrink-0 cursor-pointer underline hover:text-grey-900 disabled:cursor-default disabled:text-grey-400 disabled:no-underline"
              >
                {gettext("Clear categories")}
              </FirmowidUI.Components.Button.button>
            </div>
          </div>
        </.popover>
      <% else %>
        <.badges tags={@tags} colors={@colors} />
      <% end %>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".CategoryCombobox">
        export default {
          mounted() {
            this.input = this.el.querySelector("[data-combobox-input]");
            this.input.addEventListener("input", () => this.filter());
            this.el.addEventListener("keydown", (event) => this.onKeydown(event));
            this.filter();
          },
          updated() {
            this.filter();
          },
          options() {
            return [...this.el.querySelectorAll("[data-combobox-option], [data-combobox-create]")].filter((option) => !option.hidden);
          },
          filter() {
            const name = this.input.value.trim();
            const query = name.toLocaleLowerCase();
            let matches = 0;
            this.el.querySelectorAll("[data-combobox-option]").forEach((option) => {
              option.hidden = !option.dataset.comboboxOption.toLocaleLowerCase().includes(query);
              if (!option.hidden) matches += 1;
            });
            const create = this.el.querySelector("[data-combobox-create]");
            const separator = this.el.querySelector("[data-combobox-separator]");
            if (separator) separator.hidden = query !== "";
            create.hidden = name === "" || matches > 0;
            create.setAttribute("phx-value-name", name);
            create.querySelector("[data-combobox-create-name]").textContent = name;
          },
          onKeydown(event) {
            const options = this.options();
            const index = options.indexOf(document.activeElement);

            if (event.key === "ArrowDown" || event.key === "ArrowUp") {
              event.preventDefault();
              const step = event.key === "ArrowDown" ? 1 : -1;
              const next = index === -1 ? (step === 1 ? 0 : options.length - 1) : index + step;
              options[next]?.focus();
              if (next < 0) this.input.focus();
            } else if (event.key === "Enter" && document.activeElement === this.input) {
              event.preventDefault();
              options[0]?.click();
            }
          },
        };
      </script>
    </div>
    """
  end

  attr :tags, :list, required: true
  attr :colors, :map, required: true

  @doc """
  Renders categories on one line: the first three and a count of the rest, with
  all names in the title. An empty list shows an explicit unassigned badge.
  """
  @spec badges(map()) :: Rendered.t()
  def badges(assigns) do
    assigns = update(assigns, :tags, &Enum.sort_by(&1, fn tag -> tag_label(tag) end))

    ~H"""
    <span
      class="flex min-w-0 items-center gap-1 overflow-hidden"
      title={Enum.map_join(@tags, ", ", &tag_label/1)}
    >
      <span
        :if={@tags == []}
        class="inline-flex items-center gap-1.5 rounded-full bg-grey-100 px-2 py-0.5 text-xs text-grey-600"
      >
        <.color_dot color={Map.fetch!(@colors, :unassigned)} />{gettext("Unassigned")}
      </span>
      <span
        :for={tag <- Enum.take(@tags, 3)}
        class="inline-flex min-w-0 items-center gap-1.5 rounded-full bg-grey-100 px-2 py-0.5 text-xs text-grey-700"
      >
        <.omitted_dot :if={tag.kind == :internal} />
        <.color_dot :if={tag.kind != :internal} color={tag_color(tag, @colors)} />
        <span class="truncate">{tag_label(tag)}</span>
      </span>
      <span
        :if={length(@tags) > 3}
        class="shrink-0 rounded-full bg-grey-100 px-1.5 py-0.5 text-xs text-grey-700"
      >
        +{length(@tags) - 3}
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

  defp omitted_dot(assigns) do
    ~H"""
    <span class="size-2.5 shrink-0 rounded-full border-2 border-grey-500" aria-hidden="true" />
    """
  end

  defp option_styles do
    "group flex min-h-9 w-full cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm text-grey-700 transition hover:bg-grey-100 focus-visible:bg-grey-100 focus-visible:outline-none"
  end

  defp tag_color(%{kind: :company}, colors), do: Map.fetch!(colors, :company)
  defp tag_color(%{kind: :taxes}, colors), do: Map.fetch!(colors, :taxes)

  defp tag_color(%{kind: :project, tag_definition_id: id}, colors), do: Map.fetch!(colors, {:project, id})

  defp tag_color(_tag, colors), do: Map.fetch!(colors, :unassigned)

  defp entity_type(%SalesInvoice{}), do: :sales_invoice
  defp entity_type(%CostInvoice{}), do: :cost_invoice
  defp entity_type(%Transaction{}), do: :transaction

  defp editable?(%Transaction{} = row), do: row.skip_invoicing

  defp editable?(row), do: row.skip_invoicing or row.transactions != []

  defp tag_label(%{kind: :company}), do: gettext("Company")
  defp tag_label(%{kind: :taxes}), do: gettext("Taxes")
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
