defmodule FirmowidWeb.DesignSystem.Components.Filters do
  @moduledoc """
  List filters in the invoicing style: uppercase scope tabs and rounded sub-filter pills.
  """

  use FirmowidUI, :html

  alias Phoenix.LiveView.Rendered

  @link_attrs [:navigate, :patch, :active, :count, :class, :__slot__, :inner_block]

  @doc """
  Renders the scope tabs of a list (for example active and archived records). Each tab
  is a link, so the selected scope lives in the URL. A tab may show a `count` badge
  for records that ask for action. Extra slot attributes (`id`, hooks, data
  attributes) are passed to the link.
  """
  @spec filter_tabs(map()) :: Rendered.t()
  attr :label, :string, required: true, doc: "Accessible name of the tab navigation."
  attr :class, :any, default: nil

  slot :tab,
    required: true,
    validate_attrs: false,
    doc: "Attributes: `navigate` or `patch`, `active`, `count`, `class`; any other attribute goes to the link."

  def filter_tabs(assigns) do
    ~H"""
    <nav
      aria-label={@label}
      class={[
        "flex items-center gap-4 max-md:grid max-md:w-full max-md:grid-cols-2 max-md:gap-2",
        @class
      ]}
    >
      <.link
        :for={tab <- @tab}
        navigate={tab[:navigate]}
        patch={tab[:patch]}
        aria-current={tab[:active] && "page"}
        class={tab_styles(tab)}
        {extra_link_attrs(tab)}
      >
        {render_slot(tab)}
        <span
          :if={tab[:count] not in [nil, 0]}
          class="pointer-events-none absolute -top-3 left-full flex -translate-x-3 items-center justify-center rounded-full border-2 border-grey-100 bg-rust-200 px-2 text-rust-700 max-md:right-0 max-md:left-auto max-md:translate-x-0"
        >
          {tab[:count]}
        </span>
      </.link>
    </nav>
    """
  end

  @doc """
  Renders sub-filter pills that narrow a list, prefixed with a "Filters:" label. Pills
  are links (`navigate` or `patch`) or buttons with `phx-click`; clicking an active
  pill is expected to clear it. With `divider`, a vertical rule separates the pills
  from preceding tabs on wide screens.
  """
  @spec filter_pills(map()) :: Rendered.t()
  attr :divider, :boolean, default: false
  attr :class, :any, default: nil

  attr :label, :any, default: :default, doc: "Visible label before the pills; `nil` hides it."

  slot :pill,
    required: true,
    validate_attrs: false,
    doc:
      "Attributes: `navigate` or `patch` for a link, otherwise a button; `active`; any other attribute (`phx-click`, `phx-value-*`, `phx-target`) goes to the element."

  def filter_pills(assigns) do
    assigns = update(assigns, :label, &if(&1 == :default, do: gettext("Filters:"), else: &1))

    ~H"""
    <div class={["flex items-center gap-6 max-md:w-full", @class]}>
      <div :if={@divider} class="mx-2 h-7 w-px bg-grey-200 max-md:hidden"></div>
      <div role="group" aria-label={gettext("Filters")} class="flex items-center gap-3 max-md:w-full">
        <span :if={@label} class="text-sm font-normal text-grey-700/70">{@label}</span>
        <div class="flex flex-wrap items-center gap-2 max-md:flex-1">
          <%= for pill <- @pill do %>
            <.link
              :if={pill[:navigate] || pill[:patch]}
              navigate={pill[:navigate]}
              patch={pill[:patch]}
              aria-current={pill[:active] && "true"}
              class={pill_styles(pill[:active])}
              {extra_link_attrs(pill)}
            >
              {render_slot(pill)}
            </.link>
            <button
              :if={!(pill[:navigate] || pill[:patch])}
              type="button"
              aria-pressed={to_string(pill[:active] == true)}
              class={pill_styles(pill[:active])}
              {extra_link_attrs(pill)}
            >
              {render_slot(pill)}
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp extra_link_attrs(entry), do: Map.drop(entry, @link_attrs)

  defp tab_styles(tab) do
    [
      "relative inline-flex items-center justify-center rounded-lg px-3 py-1 text-center text-sm/6 font-normal uppercase transition-colors",
      if(tab[:active],
        do: "bg-grey-700 text-white",
        else: "bg-grey-100 text-grey-700 hover:bg-grey-200"
      ),
      tab[:class]
    ]
  end

  defp pill_styles(active?) do
    [
      "inline-flex h-8 cursor-pointer items-center justify-center gap-1.5 rounded-full border px-4 py-1.5 text-sm leading-none font-medium whitespace-nowrap transition-colors max-md:flex-1 [&>svg]:size-4",
      if(active?,
        do: "border-grey-700 bg-grey-700 text-white",
        else: "border-grey-200 bg-grey-100 text-grey-700 hover:bg-grey-200"
      )
    ]
  end
end
