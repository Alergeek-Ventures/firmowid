defmodule FirmowidWeb.DesignSystem.Components.Menu do
  @moduledoc """
  Action menu opened from a trigger (by default a "more" icon button), built on the
  design-system popover: it positions with floating-ui, traps focus and closes on
  Escape or a click outside.
  """

  use FirmowidUI, :html

  import FirmowidWeb.DesignSystem.Components.CoreComponents, only: [popover: 1, show_popover: 1]
  import FirmowidWeb.DesignSystem.Components.IconButton

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders a menu. Put `menu_item/1` entries in the inner block.
  """
  @spec menu(map()) :: Rendered.t()
  attr :id, :string, required: true
  attr :label, :string, required: true, doc: "Accessible name of the trigger and the menu."
  attr :placement, :string, default: "bottom-end"
  attr :class, :any, default: nil
  slot :trigger, doc: "Custom trigger content; defaults to a vertical ellipsis icon."
  slot :inner_block, required: true

  def menu(assigns) do
    ~H"""
    <div class={["inline-flex", @class]}>
      <.icon_button
        id={"#{@id}-trigger"}
        label={@label}
        aria-haspopup="menu"
        phx-click={show_popover("#{@id}-menu")}
      >
        <%= if @trigger != [] do %>
          {render_slot(@trigger)}
        <% else %>
          <Lucideicons.ellipsis_vertical />
        <% end %>
      </.icon_button>
      <.popover id={"#{@id}-menu"} reference_id={"#{@id}-trigger"} placement={@placement}>
        <div
          role="menu"
          aria-label={@label}
          class="flex min-w-48 flex-col rounded-lg bg-white p-1 shadow-lg ring-1 ring-grey-700/10"
        >
          {render_slot(@inner_block)}
        </div>
      </.popover>
    </div>
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

  defp menu_item_base_styles,
    do:
      "flex min-h-9 w-full cursor-pointer items-center gap-2 rounded-md px-2.5 text-left text-sm whitespace-nowrap disabled:pointer-events-none disabled:opacity-50 [&>svg]:size-4 [&>svg]:shrink-0"

  defp menu_item_tone_styles("default"), do: "text-grey-900 hover:bg-grey-100"
  defp menu_item_tone_styles("danger"), do: "text-brick-700 hover:bg-brick-100"
end
