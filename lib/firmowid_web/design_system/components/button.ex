defmodule FirmowidWeb.DesignSystem.Components.Button do
  @moduledoc """
  App-owned button primitive for the design system.

  This component is the replacement target for legacy button usages from
  `CoreComponents`. Its API is aligned with the Figma button taxonomy and keeps
  styling logic private to the component.
  """

  use FirmowidWeb, :html

  alias FirmowidWeb.DesignSystem.Utilities.ButtonStyles

  @doc """
  Renders a design-system button.

  ## Examples

      <.button variant="primary">Save</.button>
      <.button variant="outline" size="small" type="button">Cancel</.button>
      <.button variant="primary" accent="turquoise">Continue</.button>
  """
  @spec button(map()) :: Phoenix.LiveView.Rendered.t()
  attr :class, :any, default: nil, doc: "Additional classes merged into the component."

  attr :rest, :global, include: ~w(disabled form name value aria-label phx-click phx-disable-with)

  attr :accent, :string,
    default: "orange",
    values: ["orange", "turquoise"],
    doc: "Accent used by variants that support multiple colorways."

  attr :size, :string,
    default: "big",
    values: ["big", "small"],
    doc: "Figma-aligned size modifier."

  attr :type, :string,
    default: "submit",
    values: ["submit", "button", "reset"],
    doc: "Native HTML button type."

  attr :variant, :string,
    default: "primary",
    values: [
      "special",
      "primary",
      "secondary",
      "tertiary",
      "outline",
      "ghost",
      "destructive",
      "success"
    ],
    doc: "Figma-aligned button variant."

  slot :inner_block, required: true

  def button(assigns) do
    assigns =
      assigns
      |> assign(:size_classes, ButtonStyles.size_classes(assigns.size))
      |> assign(:variant_classes, ButtonStyles.variant_classes(assigns.variant, assigns.accent))

    ~H"""
    <button
      type={@type}
      class={[
        "phx-click-loading:cursor-default phx-click-loading:opacity-75 phx-submit-loading:opacity-75 inline-flex cursor-pointer items-center justify-center border whitespace-nowrap transition duration-100 ease-out select-none disabled:pointer-events-none disabled:cursor-default",
        @size_classes,
        @variant_classes,
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end
end
