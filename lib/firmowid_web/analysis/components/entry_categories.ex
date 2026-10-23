defmodule FirmowidWeb.Analysis.Components.EntryCategories do
  @moduledoc "Category editing below the matching controls on invoice and transaction details."
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Link
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Analysis.EntityTag
  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias FirmowidWeb.Analysis.Components.CategoryChart
  alias FirmowidWeb.Analysis.Components.CategorySelector
  alias FirmowidWeb.Analysis.Utilities.Navigation

  @impl true
  def update(assigns, socket) do
    definitions = TagDefinition.list_tag_definitions!(scope: assigns.scope)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:categories, definitions)
     |> assign(:colors, CategoryChart.category_colors(definitions))
     |> load_entry()}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:title, category_title(assigns.entry))
      |> assign(:explanation, category_explanation(assigns.entry))
      |> assign(
        :analysis_path,
        Navigation.dashboard_path(Date.beginning_of_month(entry_date(assigns.entry)))
      )

    ~H"""
    <section id={@id} class="flex flex-col gap-4 pbs-18">
      <h2 class="text-lg/tight font-medium">{@title}</h2>
      <div class="flex flex-wrap items-start gap-6">
        <p class="min-w-0 flex-[2_1_20rem] text-sm/snug text-grey-700">
          {@explanation}
          <.link kind="text" size="small" navigate={@analysis_path}>
            {gettext("See in analysis")}
          </.link>
        </p>
        <CategorySelector.cell
          entry={@entry}
          categories={@categories}
          colors={@colors}
          can_write={
            flag_enabled?(:analysis_dashboard, assigns) and
              @scope.actor.member.role in [:admin, :accountant]
          }
          class="min-w-0 flex-[1_1_16rem]"
          target={@myself}
        />
      </div>
    </section>
    """
  end

  @impl true
  def handle_event(event, params, socket)
      when event in ["set-entity-category", "clear-entity-tags", "toggle-project-tag"] do
    if flag_enabled?(:analysis_dashboard, socket.assigns) and editable?(socket.assigns.entry) do
      case change_category(event, params, socket.assigns) do
        {:ok, _} ->
          {:noreply, load_entry(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Could not update categories."))}
      end
    else
      {:noreply, socket}
    end
  end

  defp load_entry(socket) do
    entry =
      Ash.load!(socket.assigns.entry, category_loads(socket.assigns.entry), scope: socket.assigns.scope)

    assign(socket, :entry, entry)
  end

  defp category_loads(%Transaction{}),
    do: [
      entity_tags: :tag_definition,
      cost_invoices: [entity_tags: :tag_definition],
      sales_invoices: [entity_tags: :tag_definition]
    ]

  defp category_loads(_invoice), do: [entity_tags: :tag_definition]

  defp change_category("clear-entity-tags", _params, assigns) do
    EntityTag.clear_entity_tags(entity_arguments(assigns.entry), scope: assigns.scope)
  end

  defp change_category("set-entity-category", %{"kind" => kind}, assigns) when kind in ["company", "internal"] do
    arguments = Map.put(entity_arguments(assigns.entry), :kind, kind)
    EntityTag.set_entity_category(arguments, scope: assigns.scope)
  end

  defp change_category("toggle-project-tag", %{"tag_definition_id" => id}, assigns) do
    if Enum.any?(assigns.categories, &(&1.id == id)) do
      current =
        assigns.entry.entity_tags
        |> Enum.filter(&(&1.kind == :project))
        |> Enum.map(& &1.tag_definition_id)

      ids = if id in current, do: List.delete(current, id), else: [id | current]
      arguments = Map.put(entity_arguments(assigns.entry), :tag_definition_ids, ids)
      EntityTag.set_entity_project_tags(arguments, scope: assigns.scope)
    else
      {:error, :invalid_category}
    end
  end

  defp entity_arguments(%SalesInvoice{id: id}), do: %{entity_type: :sales_invoice, resource_id: id}

  defp entity_arguments(%CostInvoice{id: id}), do: %{entity_type: :cost_invoice, resource_id: id}
  defp entity_arguments(%Transaction{id: id}), do: %{entity_type: :transaction, resource_id: id}

  defp category_title(%Transaction{}), do: gettext("Transaction categories")
  defp category_title(_invoice), do: gettext("Invoice categories")

  defp category_explanation(entry) do
    if Money.positive?(entry_amount(entry)) do
      gettext("Categories help you understand how this income affects your budget.")
    else
      gettext("Categories help you understand how this expense affects your budget.")
    end
  end

  defp entry_amount(%Transaction{amount: amount}), do: amount
  defp entry_amount(invoice), do: invoice.effective_amount

  defp entry_date(%Transaction{booking_date: date}), do: date
  defp entry_date(invoice), do: invoice.effective_sale_date

  defp editable?(%Transaction{} = transaction) do
    is_nil(transaction.salary_user_id) and transaction.cost_invoices == [] and
      transaction.sales_invoices == []
  end

  defp editable?(_invoice), do: true
end
