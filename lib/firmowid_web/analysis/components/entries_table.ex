defmodule FirmowidWeb.Analysis.Components.EntriesTable do
  @moduledoc """
  Table component for listing analysis entries (sales invoices, cost invoices,
  and standalone transactions) in the analysis dashboard.

  Each row displays the counterparty, sale/booking date, amount, current tag
  pills and a per-row tag selector popover for assigning tags.
  """
  use FirmowidWeb, :html

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Finances.Transaction

  attr :entries, :list, required: true
  attr :tag_definitions, :list, required: true

  def table(assigns) do
    ~H"""
    <table class="w-full table-fixed border-separate border-spacing-y-2">
      <col />
      <col class="w-32" />
      <col class="w-52" />
      <col class="w-36" />
      <thead>
        <tr>
          <th class="text-darkGrey py-2 pl-5 text-left text-xs font-normal uppercase">
            Kontrahent
          </th>
          <th class="text-darkGrey py-2 text-left text-xs font-normal uppercase">
            Data sprzedaży
          </th>
          <th class="text-darkGrey py-2 text-left text-xs font-normal uppercase">
            Tagi
          </th>
          <th class="text-darkGrey py-2 text-left text-xs font-normal uppercase">
            Kwota
          </th>
        </tr>
      </thead>
      <tbody>
        <tr :if={@entries == []}>
          <td colspan="4" class="text-darkGrey py-8 text-center">Brak wpisów</td>
        </tr>
        <.row :for={entry <- @entries} entry={entry} tag_definitions={@tag_definitions} />
      </tbody>
    </table>
    """
  end

  defp row(%{entry: %SalesInvoice{} = invoice} = assigns) do
    assigns =
      assigns
      |> assign(:party, SalesInvoice.buyer_display_name(invoice) || "")
      |> assign(:description, Enum.map_join(invoice.sales_invoice_items, ", ", & &1.name))
      |> assign(:date, invoice.sale_date || invoice.issue_date)
      |> assign(:amount, Money.new(invoice.currency, SalesInvoice.get_gross_value(invoice)))
      |> assign(:amount_decimal, SalesInvoice.get_gross_value(invoice))
      |> assign(:navigate, ~p"/sprzedazowe/#{invoice.id}")
      |> assign_entity_fields(invoice, :sales_invoice)

    ~H"<.entry_row {assigns} />"
  end

  defp row(%{entry: %CostInvoice{} = invoice} = assigns) do
    assigns =
      assigns
      |> assign(:party, invoice.seller_display_name || invoice.seller || "")
      |> assign(:description, invoice.description)
      |> assign(:date, invoice.sale_date)
      |> assign(:amount, Money.new(invoice.currency, invoice.total_amount))
      |> assign(:amount_decimal, invoice.total_amount)
      |> assign(:navigate, ~p"/kosztowe/#{invoice.id}")
      |> assign_entity_fields(invoice, :cost_invoice)

    ~H"<.entry_row {assigns} />"
  end

  defp row(%{entry: %Transaction{} = transaction} = assigns) do
    party =
      if Decimal.compare(transaction.transaction_amount, 0) == :gt do
        transaction.debtor_name
      else
        transaction.creditor_name
      end

    assigns =
      assigns
      |> assign(:party, party || "")
      |> assign(:description, transaction.remittance_information_unstructured)
      |> assign(:date, transaction.booking_date)
      |> assign(:amount, Money.new(transaction.transaction_currency, transaction.transaction_amount))
      |> assign(:amount_decimal, transaction.transaction_amount)
      |> assign(:navigate, nil)
      |> assign(:entity_tags, Map.get(transaction, :entity_tags, []))
      |> assign(:entity_type, :transaction)
      |> assign(:entity_id, transaction.id)
      |> assign(:taggable, transaction.skip_invoicing)

    ~H"<.entry_row {assigns} />"
  end

  # Shared entity tag assigns for invoice rows (sales and cost).
  defp assign_entity_fields(assigns, invoice, entity_type) do
    assigns
    |> assign(:entity_tags, Map.get(invoice, :entity_tags, []))
    |> assign(:entity_type, entity_type)
    |> assign(:entity_id, invoice.id)
    |> assign(:taggable, invoice.skip_invoicing or invoice.transactions != [])
  end

  defp entry_row(assigns) do
    popover_id = "tag-select-#{assigns.entity_id}"

    assigns =
      assigns
      |> assign(:popover_id, popover_id)
      |> assign(:current_kind, detect_current_kind(assigns.entity_tags))
      |> assign(:current_project_ids, detect_project_ids(assigns.entity_tags))

    ~H"""
    <tr>
      <td class="rounded-l-md bg-white px-5 py-2">
        <div class="truncate">
          <%= if @navigate do %>
            <.link navigate={@navigate} class="hover:underline">
              <.party_cell party={@party} description={@description} />
            </.link>
          <% else %>
            <.party_cell party={@party} description={@description} />
          <% end %>
        </div>
      </td>
      <td class="bg-white py-2 font-light">
        {@date}
      </td>
      <td class="bg-white py-2">
        <div class="relative flex items-center gap-1">
          <.tag_pills entity_tags={@entity_tags} />
          <.tag_selector_popover
            :if={@taggable}
            entity_id={@entity_id}
            entity_type={@entity_type}
            popover_id={@popover_id}
            current_kind={@current_kind}
            current_project_ids={@current_project_ids}
            tag_definitions={@tag_definitions}
          />
        </div>
      </td>
      <td class={[
        "rounded-r-md py-2",
        if(Decimal.gte?(@amount_decimal, 0),
          do: "bg-blueBg text-blueText",
          else: "bg-orangeBg text-orangeText"
        )
      ]}>
        <div class="py-1 pr-5 text-right">
          {@amount}
        </div>
      </td>
    </tr>
    """
  end

  defp tag_selector_popover(assigns) do
    ~H"""
    <button
      id={"tag-trigger-#{@entity_id}"}
      type="button"
      phx-click={show_popover(@popover_id)}
      class="hover:bg-grey-200 hover:text-darkGrey text-darkGrey/50 inline-flex shrink-0 cursor-pointer items-center justify-center rounded-md p-1 transition"
    >
      <.icon name="hero-pencil-square-mini" class="size-4.5" />
    </button>
    <.popover
      id={@popover_id}
      reference_id={"tag-trigger-#{@entity_id}"}
      placement="bottom-start"
      class="bg-grey-50 border-grey-200 w-56 rounded-lg border"
    >
      <ul class="flex max-h-64 flex-col gap-0.5 overflow-auto p-1">
        <li
          phx-click="clear-entity-tags"
          phx-value-entity_type={@entity_type}
          phx-value-entity_id={@entity_id}
          class={[
            "cursor-pointer rounded px-2 py-1.5 text-sm transition",
            if(@current_kind == nil,
              do: "bg-orange-100 font-medium text-orange-800",
              else: "hover:bg-orange-100 hover:text-orange-800"
            )
          ]}
        >
          — Brak
        </li>
        <li
          phx-click="set-entity-category"
          phx-value-entity_type={@entity_type}
          phx-value-entity_id={@entity_id}
          phx-value-kind="company"
          class={[
            "cursor-pointer rounded px-2 py-1.5 text-sm transition",
            if(@current_kind == :company,
              do: "bg-orange-100 font-medium text-orange-800",
              else: "hover:bg-orange-100 hover:text-orange-800"
            )
          ]}
        >
          Firma
        </li>
        <li
          phx-click="set-entity-category"
          phx-value-entity_type={@entity_type}
          phx-value-entity_id={@entity_id}
          phx-value-kind="internal"
          class={[
            "cursor-pointer rounded px-2 py-1.5 text-sm transition",
            if(@current_kind == :internal,
              do: "bg-orange-100 font-medium text-orange-800",
              else: "hover:bg-orange-100 hover:text-orange-800"
            )
          ]}
        >
          Wewnętrzna
        </li>
        <li
          :if={@tag_definitions != []}
          class="border-grey-200 mt-0.5 border-t pt-0.5"
          role="separator"
        >
        </li>
        <li :for={tag_def <- @tag_definitions}>
          <label class="flex cursor-pointer items-center gap-2 rounded px-2 py-1.5 transition hover:bg-orange-100 hover:text-orange-800">
            <input
              type="checkbox"
              checked={MapSet.member?(@current_project_ids, tag_def.id)}
              phx-click="toggle-project-tag"
              phx-value-entity_type={@entity_type}
              phx-value-entity_id={@entity_id}
              phx-value-tag_definition_id={tag_def.id}
              class="border-darkGrey size-4 rounded-[3px] border focus:ring-0"
              style={"color: #{tag_def.color}"}
            />
            <span
              class="inline-block size-2 shrink-0 rounded-full"
              style={"background-color: #{tag_def.color}"}
            >
            </span>
            <span class="text-darkGrey truncate text-sm">{tag_def.name}</span>
          </label>
        </li>
      </ul>
    </.popover>
    """
  end

  defp party_cell(assigns) do
    ~H"""
    {@party}
    <span :if={@description != "" and @description != nil} class="text-darkGrey text-sm opacity-50">
      {@description}
    </span>
    """
  end

  defp tag_pills(%{entity_tags: []} = assigns), do: ~H""

  defp tag_pills(assigns) do
    ~H"""
    <span class="inline-flex flex-wrap gap-1">
      <span
        :for={tag <- @entity_tags}
        class="inline-flex rounded-full px-2 py-0 text-[11px] font-medium whitespace-nowrap"
        style={tag_pill_style(tag)}
      >
        {tag_label(tag)}
      </span>
    </span>
    """
  end

  defp tag_label(%{kind: :company}), do: "Firma"
  defp tag_label(%{kind: :internal}), do: "Wewnętrzna"
  defp tag_label(%{kind: :project, tag_definition: %{name: name}}), do: name
  defp tag_label(%{kind: :project}), do: "Projekt"

  defp tag_pill_style(%{kind: :company}) do
    "background-color: #354E4E20; color: #354E4E"
  end

  defp tag_pill_style(%{kind: :internal}) do
    "background-color: #A22A2A20; color: #A22A2A"
  end

  defp tag_pill_style(%{kind: :project, tag_definition: %{color: color}}) do
    "background-color: #{color}20; color: #{color}"
  end

  defp tag_pill_style(_), do: "background-color: #6B728020; color: #6B7280"

  defp detect_current_kind([]), do: nil

  defp detect_current_kind(entity_tags) do
    case List.first(entity_tags) do
      %{kind: :company} -> :company
      %{kind: :internal} -> :internal
      %{kind: :project} -> :project
      _ -> nil
    end
  end

  defp detect_project_ids(entity_tags) do
    entity_tags
    |> Enum.filter(&(&1.kind == :project))
    |> MapSet.new(& &1.tag_definition_id)
  end
end
