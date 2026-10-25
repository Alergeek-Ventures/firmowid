defmodule FirmowidWeb.DesignSystem.Components.IconButton do
  @moduledoc """
  Square button that shows only an icon; its label is required and becomes the accessible name.
  """

  use FirmowidUI, :html

  alias FirmowidUI.Utilities.ButtonStyles

  @doc """
  Renders an icon-only button in the small (32px) or big (44px) control size.
  """
  @spec icon_button(map()) :: Phoenix.LiveView.Rendered.t()
  attr :label, :string, required: true, doc: "Accessible name, also shown as the native tooltip."
  attr :size, :string, values: ~w(small big), default: "small"
  attr :variant, :string, values: ~w(ghost outline secondary), default: "ghost"
  attr :type, :string, default: "button"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled form name value)
  slot :inner_block, required: true

  def icon_button(assigns) do
    ~H"""
    <button
      type={@type}
      aria-label={@label}
      title={@label}
      class={[
        "inline-flex shrink-0 cursor-pointer items-center justify-center border transition duration-100 ease-out select-none disabled:pointer-events-none disabled:opacity-50 phx-click-loading:opacity-75",
        icon_button_size_styles(@size),
        icon_button_variant_styles(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp icon_button_size_styles("small"), do: "size-8 rounded-md [&>svg]:size-4"
  defp icon_button_size_styles("big"), do: "size-11 rounded-lg [&>svg]:size-5"

  defp icon_button_variant_styles(variant), do: ButtonStyles.variant_classes(variant, nil)
end
