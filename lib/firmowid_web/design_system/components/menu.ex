defmodule FirmowidWeb.DesignSystem.Components.Menu do
  @moduledoc """
  Action menu opened from a trigger (by default a "more" icon button), built on the
  design-system popover: it opens 4px under the trigger, traps focus and closes on
  Escape or a click outside.

  Its dropdown variant lists the options of a select field: `dropdown_panel_styles/0`
  for the panel and `dropdown_option/1` for each option.

  The trigger darkens while the nearest `group` around it is hovered, so a list
  row marks itself `group` once to light up its menu.
  """

  use FirmowidUI, :html

  import FirmowidWeb.DesignSystem.Components.CoreComponents, only: [popover: 1, show_popover: 1]
  import FirmowidWeb.DesignSystem.Components.IconButton
  import FirmowidWeb.DesignSystem.Components.Tooltip

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders a menu. Put `menu_item/1` entries in the inner block.
  """
  @spec menu(map()) :: Rendered.t()
  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "Accessible name of the trigger and the menu."
  attr :placement, :string, default: "bottom-end"
  attr :class, :any, default: nil

  attr :panel_class, :any,
    default: nil,
    doc: "Extra classes of the menu panel, for example its width."

  attr :trigger_class, :any,
    default: nil,
    doc: "Extra classes of the trigger, for example a larger size for a custom trigger."

  attr :trigger_variant, :string,
    values: ~w(menu bare),
    default: "menu",
    doc: "`bare` leaves the trigger's colours to `trigger_class`."

  attr :tooltip, :string,
    default: nil,
    doc: "Shown beside the trigger (the light hint, on its left) instead of the native tooltip."

  slot :trigger, doc: "Custom trigger content; defaults to a vertical ellipsis icon."
  slot :inner_block, required: true

  def menu(assigns) do
    ~H"""
    <div class={["inline-flex", @class]}>
      <.tooltip
        :if={@tooltip}
        id={"#{@id}-tooltip"}
        text={@tooltip}
        placement="left"
        variant="hint"
        hide_on_click
      >
        <.menu_trigger
          id={@id}
          label={@label}
          class={@trigger_class}
          variant={@trigger_variant}
          trigger={@trigger}
          native_title={false}
        />
      </.tooltip>
      <.menu_trigger
        :if={!@tooltip}
        id={@id}
        label={@label}
        class={@trigger_class}
        variant={@trigger_variant}
        trigger={@trigger}
      />
      <.popover
        id={"#{@id}-menu"}
        reference_id={"#{@id}-trigger"}
        placement={@placement}
        data-offset="4"
      >
        <%!-- Dropdown entrance (DESIGN.md, Motion): it unfolds from the trigger's corner. --%>
        <div
          role="menu"
          aria-label={@label}
          class={[
            "flex min-w-48 flex-col rounded-sm border border-grey-200 bg-white p-1 shadow-small transition-[opacity,scale] duration-150 ease-out motion-reduce:transition-none starting:scale-95 starting:opacity-0",
            if(String.ends_with?(@placement, "-start"),
              do: "origin-top-left",
              else: "origin-top-right"
            ),
            @panel_class
          ]}
        >
          {render_slot(@inner_block)}
        </div>
      </.popover>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :variant, :string, required: true
  attr :native_title, :boolean, default: true
  attr :trigger, :list, required: true

  defp menu_trigger(assigns) do
    ~H"""
    <.icon_button
      id={"#{@id}-trigger"}
      label={@label}
      variant={@variant}
      native_title={@native_title}
      class={@class}
      aria-haspopup="menu"
      aria-expanded="false"
      phx-click={show_popover("#{@id}-menu")}
    >
      <%= if @trigger != [] do %>
        {render_slot(@trigger)}
      <% else %>
        <Lucideicons.ellipsis_vertical />
      <% end %>
    </.icon_button>
    """
  end

  @doc """
  Renders a menu entry: a link when `navigate` or `patch` is given, otherwise a button
  (pass `phx-click` and friends through `rest`). `danger` marks destructive actions.
  """
  @spec menu_item(map()) :: Rendered.t()
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :tone, :string, values: ~w(default danger), default: "default"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled)
  slot :inner_block, required: true

  def menu_item(%{navigate: nil, patch: nil} = assigns) do
    ~H"""
    <button
      type="button"
      role="menuitem"
      class={[menu_item_base_styles(), menu_item_tone_styles(@tone), @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  def menu_item(assigns) do
    ~H"""
    <.link
      role="menuitem"
      navigate={@navigate}
      patch={@patch}
      class={[menu_item_base_styles(), menu_item_tone_styles(@tone), @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Classes of a dropdown panel: field paper (grey-50) with the overlay shadow and the
  dropdown entrance. The caller sets the display (`flex flex-col`, or `hidden` toggled
  to flex), the width (the field's) and the 4px gap under the field.
  """
  @spec dropdown_panel_styles() :: String.t()
  def dropdown_panel_styles do
    "rounded-sm border border-grey-200 bg-grey-50 p-1 shadow-small transition-[opacity,scale] duration-150 ease-out motion-reduce:transition-none starting:scale-95 starting:opacity-0"
  end

  @doc """
  Renders an option of a dropdown: a button (pass `phx-click` and friends through
  `rest`) with a check on the right while it is `selected`.
  """
  @spec dropdown_option(map()) :: Rendered.t()
  attr :selected, :boolean, required: true
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def dropdown_option(assigns) do
    ~H"""
    <button
      type="button"
      role="option"
      aria-selected={to_string(@selected)}
      class={[
        "group/option justify-between",
        menu_item_base_styles(),
        menu_item_tone_styles("default"),
        @class
      ]}
      {@rest}
    >
      <span class="min-w-0 truncate">{render_slot(@inner_block)}</span>
      <%!-- The check from the design, not Lucide's; shown through aria-selected, which a
      client-side pick may switch without the server. --%>
      <svg
        viewBox="0 0 16 16"
        fill="none"
        stroke="currentColor"
        stroke-width="1.33"
        stroke-linecap="round"
        stroke-linejoin="round"
        aria-hidden="true"
        class="hidden group-aria-selected/option:block"
      >
        <path d="M3 8.5L7 12.5L13 3.5" />
      </svg>
    </button>
    """
  end

  defp menu_item_base_styles,
    do:
      "flex min-h-9 w-full cursor-pointer items-center gap-2 rounded-sm px-3 text-left text-sm/[1.35] whitespace-nowrap disabled:pointer-events-none disabled:opacity-50 [&>svg]:size-4 [&>svg]:shrink-0"

  defp menu_item_tone_styles("default"), do: "text-grey-900 hover:bg-grey-200"
  defp menu_item_tone_styles("danger"), do: "text-brick-700 hover:bg-brick-100"
end
