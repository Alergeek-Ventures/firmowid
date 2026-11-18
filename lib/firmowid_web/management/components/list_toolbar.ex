defmodule FirmowidWeb.Management.Components.ListToolbar do
  @moduledoc """
  The toolbar above the Team, Projects and Counterparties lists: the month, the list scope and
  an expanding search.

  The hosting LiveView handles the `change-month` and `search` events.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.Fields, only: [search_field: 1]
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.LiveView.Rendered

  @doc "Renders the month picker and the expanding search, with the slot between them."
  @spec month_and_search(map()) :: Rendered.t()
  attr :selected_date, Date, required: true
  attr :active_months, :list, required: true
  attr :search, :string, required: true
  attr :search_label, :string, required: true, doc: "the placeholder and label of the search"
  slot :inner_block, doc: "Controls between the month and the search, such as the list scope."

  def month_and_search(assigns) do
    ~H"""
    <form class="flex items-center gap-4 max-md:flex-wrap max-md:gap-3" phx-submit="search">
      <.month_picker
        id="month"
        show_on_mobile
        selected_date={@selected_date}
        active_months={@active_months}
        class="max-md:flex-1"
      />

      {render_slot(@inner_block)}

      <.expanding_search search={@search} search_label={@search_label} />
    </form>
    """
  end

  @doc """
  Renders Figma's "Wyszukiwarka rozwijana", for a list without a month. Place it inside a form
  with `phx-submit="search"`.
  """
  @spec expanding_search(map()) :: Rendered.t()
  attr :search, :string, required: true
  attr :search_label, :string, required: true, doc: "the placeholder and label of the search"

  def expanding_search(assigns) do
    ~H"""
    <%!-- Figma "Wyszukiwarka rozwijana": a square tertiary button that widens into the search
         field with focus, and narrows back when the field is left empty. The field itself is
         the button: collapsed, it takes the button's fill and its thicker magnifier, and a
         transparent button over it catches the click. The hook keeps the state, so the
         server's answers to typing do not collapse the field. --%>
    <div
      id="search-container"
      phx-hook=".ExpandingSearch"
      phx-update="ignore"
      data-expanded={to_string(@search != "")}
      class="group relative w-9 overflow-hidden rounded-sm transition-[width] duration-300 ease-out data-[expanded=true]:w-60 max-md:data-[expanded=true]:w-full data-[expanded=false]:[&_input]:border-transparent data-[expanded=false]:[&_input]:bg-grey-200 data-[expanded=false]:[&_input]:placeholder:text-transparent data-[expanded=false]:hover:[&_input]:bg-grey-300 data-[expanded=false]:[&_svg]:stroke-[2.4] data-[expanded=false]:[&_svg]:text-grey-900"
    >
      <.search_field
        name="szukaj"
        value={@search}
        placeholder={@search_label}
        size="medium"
        autocomplete="off"
        tabindex={if(@search == "", do: "-1")}
        phx-change="search"
        phx-debounce="300"
        class="w-60 max-md:w-full"
      />
      <.button
        type="button"
        variant="unstyled"
        data-expand
        class="absolute inset-0 cursor-pointer rounded-sm group-data-[expanded=true]:hidden"
      >
        <span class="sr-only">{@search_label}</span>
      </.button>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ExpandingSearch">
        export default {
          mounted() {
            const input = this.el.querySelector("input");
            this.el.querySelector("[data-expand]").addEventListener("click", () => {
              this.el.dataset.expanded = "true";
              input.tabIndex = 0;
              input.focus();
            });
            input.addEventListener("blur", () => {
              if (input.value !== "") return;
              this.el.dataset.expanded = "false";
              input.tabIndex = -1;
            });
          }
        }
      </script>
    </div>
    """
  end

  @doc "Renders Figma's segmented control: the scopes of one list, one of them active."
  @spec scope_switch(map()) :: Rendered.t()
  attr :label, :string, required: true

  slot :option, required: true do
    attr :patch, :string, doc: "the scope within the same LiveView"
    attr :navigate, :string, doc: "the scope served by another LiveView"
    attr :active, :boolean, required: true
    attr :count, :integer, doc: "Figma \"Licznik\": the things waiting in this scope"
  end

  def scope_switch(assigns) do
    ~H"""
    <nav
      aria-label={@label}
      class="flex h-9 items-center gap-0.5 overflow-hidden rounded-sm border border-grey-200 max-md:order-last max-md:w-full max-md:scrollbar-none max-md:overflow-x-auto"
    >
      <.link
        :for={option <- @option}
        kind="unstyled"
        patch={option[:patch]}
        navigate={option[:navigate]}
        aria-current={option.active && "page"}
        class={[
          "flex h-full shrink-0 items-center justify-center gap-1.5 rounded-[2px] px-3 text-sm/none font-medium whitespace-nowrap transition-colors max-md:flex-1",
          if(option.active,
            do: "bg-grey-200 text-grey-900",
            else: "text-grey-700 hover:text-grey-900"
          )
        ]}
      >
        {render_slot(option)}
        <span
          :if={option[:count]}
          class="flex h-4.5 min-w-4.5 items-center justify-center rounded-full bg-grey-700 px-1.25 text-caps-sm/none font-medium text-white tabular-nums"
        >
          {option[:count]}
        </span>
      </.link>
    </nav>
    """
  end
end
