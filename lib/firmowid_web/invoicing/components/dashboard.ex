defmodule FirmowidWeb.Invoicing.Components.Dashboard do
  @moduledoc """
  Four-column dashboard view for the invoicing landing page.

  Shows:
    - Nieopłacone faktury (unpaid invoices)
    - Transakcje do dopasowania (unmatched transactions)
    - Dopasowane (matched entities)
    - Sugestie (connection suggestions: bank, KSeF)
  """
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Invoicing.Components.DashboardTiles

  attr :unpaid_invoices, :list, default: []
  attr :unpaid_invoices_count, :integer, default: 0
  attr :unmatched_transactions, :list, default: []
  attr :unmatched_transactions_count, :integer, default: 0
  attr :matched_entries, :list, default: []
  attr :matched_entries_count, :integer, default: 0
  attr :suggestions, :list, default: []
  attr :suggestions_count, :integer, default: 0
  attr :month, :any, required: true

  def dashboard(assigns) do
    ~H"""
    <div class="grid grid-cols-1 items-stretch gap-4 md:grid-cols-2 xl:grid-cols-4">
      <.column
        title="Nieopłacone faktury"
        count={@unpaid_invoices_count}
        variant={:orange}
        see_all_url={
          ~p"/fakturowanie?month=#{Date.to_iso8601(@month)}&filter=invoices&subfilter=nieoplacone&view=list"
        }
      >
        <%= for invoice <- @unpaid_invoices do %>
          <DashboardTiles.tile entry={invoice} type={:unpaid_invoice} />
        <% end %>
        <.zero_state :if={@unpaid_invoices == []} message="Brak nieopłaconych faktur." />
      </.column>

      <.column
        title="Transakcje do dopasowania"
        count={@unmatched_transactions_count}
        variant={:orange}
        see_all_url={
          ~p"/fakturowanie?month=#{Date.to_iso8601(@month)}&filter=transactions&subfilter=bez_dokumentu&view=list"
        }
      >
        <%= for transaction <- @unmatched_transactions do %>
          <DashboardTiles.tile entry={transaction} type={:unmatched_transaction} />
        <% end %>
        <.zero_state :if={@unmatched_transactions == []} message="Brak transakcji bez dokumentu." />
      </.column>

      <.column
        title="Dopasowane"
        count={@matched_entries_count}
        variant={:turquoise}
      >
        <%= for entry <- @matched_entries do %>
          <DashboardTiles.tile entry={entry} type={:matched} />
        <% end %>
        <.zero_state :if={@matched_entries == []} message="Brak dopasowanych pozycji." />
        <%!-- TODO: add activity log view and restore a dedicated CTA for matched entries. --%>
      </.column>

      <.column title="Sugestie" count={@suggestions_count} variant={:grey}>
        <%= for suggestion <- @suggestions do %>
          <DashboardTiles.tile entry={suggestion} type={:suggestion} />
        <% end %>
        <%= if @suggestions == [] do %>
          <p class="text-darkGrey px-4 py-3 text-sm">
            Na ten moment Firmowid nie ma żadnych sugestii.
          </p>
        <% end %>
      </.column>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :count, :integer, default: 0
  attr :variant, :atom, values: [:orange, :turquoise, :grey], default: :orange
  attr :see_all_url, :string, default: nil
  slot :inner_block, required: true

  defp column(assigns) do
    {column_classes, header_classes, title_text_class, count_classes} =
      case assigns.variant do
        :orange ->
          {"bg-orange-100 rounded-lg p-3", "bg-orange-200 rounded", "text-orangeText", "bg-orange-100 text-orangeText"}

        :turquoise ->
          {"bg-[#EBF0F0] rounded-lg p-3", "bg-turquoise-200 rounded", "text-turquoise-700",
           "bg-turquoise-100 text-turquoise-700"}

        :grey ->
          {"bg-grey-200/30 rounded-lg p-3", "bg-grey-200 rounded", "text-darkGrey", "bg-grey-200 text-darkGrey"}
      end

    assigns =
      assigns
      |> assign(:column_classes, column_classes)
      |> assign(:header_classes, header_classes)
      |> assign(:title_text_class, title_text_class)
      |> assign(:count_classes, count_classes)

    ~H"""
    <div class={[
      "relative flex h-full min-h-0 flex-col",
      @column_classes
    ]}>
      <div class={[
        "mb-3 flex items-center justify-between rounded px-3 py-2 text-base",
        @header_classes
      ]}>
        <h2 class={[
          "leading-none font-medium",
          @title_text_class
        ]}>
          {@title}
        </h2>
        <span class={[
          "rounded px-3 py-2 text-sm leading-none font-medium",
          @count_classes
        ]}>
          {@count}
        </span>
      </div>
      <div class="flex min-h-0 flex-1 flex-col gap-2">
        {render_slot(@inner_block)}
      </div>
      <.link
        :if={@see_all_url}
        kind="unstyled"
        navigate={@see_all_url}
        class={[
          "mt-auto block pt-3 text-center text-base font-medium transition-colors duration-200 hover:underline",
          @title_text_class
        ]}
      >
        Zobacz wszystkie
      </.link>
    </div>
    """
  end

  attr :message, :string, required: true

  defp zero_state(assigns) do
    ~H"""
    <p class="text-darkGrey px-4 py-3 text-sm">
      {@message}
    </p>
    """
  end
end
