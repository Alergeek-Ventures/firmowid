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
      <.button as="label" for="upload-input" variant="secondary">Upload</.button>
      <.button variant="unstyled" type="button" class="w-full text-left">Open row</.button>
  """
  @spec button(map()) :: Phoenix.LiveView.Rendered.t()
  attr :class, :any, default: nil, doc: "Additional classes merged into the component."

  attr :rest, :global, include: ~w(disabled form name value aria-label phx-click phx-disable-with for)

  attr :as, :string,
    default: "button",
    values: ["button", "label"],
    doc: "Underlying HTML element used to render the component."

  attr :accent, :any,
    default: nil,
    doc: ~s(Accent used by variants that support multiple colorways. Expected values: "orange" or "turquoise".)

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
      "unstyled",
      "plain",
      "icon",
      "special",
      "primary",
      "secondary",
      "tertiary",
      "outline",
      "ghost",
      "destructive",
      "success",
      "filter"
    ],
    doc: "Figma-aligned button variant."

  slot :inner_block, required: true

  def button(%{as: "button"} = assigns) do
    assigns = assign(assigns, :classes, button_classes(assigns))

    ~H"""
    <button
      type={@type}
      class={@classes}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  def button(%{as: "label"} = assigns) do
    assigns = assign(assigns, :classes, label_classes(assigns))

    ~H"""
    <label
      class={@classes}
      {@rest}
    >
      {render_slot(@inner_block)}
    </label>
    """
  end

  defp resolved_accent(%{accent: nil, variant: "primary"}), do: "orange"
  defp resolved_accent(%{accent: accent}), do: accent

  defp button_classes(%{variant: "unstyled", class: class}), do: class

  defp button_classes(%{variant: "filter", class: class}) do
    [
      ButtonStyles.variant_classes("filter", nil),
      class
    ]
  end

  defp button_classes(%{variant: "icon", class: class}) do
    [
      ButtonStyles.variant_classes("icon", nil),
      class
    ]
  end

  defp button_classes(assigns) do
    [
      "phx-click-loading:cursor-default phx-click-loading:opacity-75 phx-submit-loading:opacity-75 inline-flex cursor-pointer items-center justify-center border whitespace-nowrap transition duration-100 ease-out select-none disabled:pointer-events-none disabled:cursor-default",
      ButtonStyles.size_classes(assigns.size),
      ButtonStyles.variant_classes(assigns.variant, resolved_accent(assigns)),
      assigns.class
    ]
  end

  defp label_classes(%{variant: "unstyled", class: class}), do: class

  defp label_classes(%{variant: "filter", class: class}) do
    [
      ButtonStyles.variant_classes("filter", nil),
      class
    ]
  end

  defp label_classes(assigns) do
    [
      "phx-click-loading:cursor-default phx-click-loading:opacity-75 inline-flex cursor-pointer items-center justify-center border whitespace-nowrap transition duration-100 ease-out select-none",
      ButtonStyles.size_classes(assigns.size),
      ButtonStyles.variant_classes(assigns.variant, resolved_accent(assigns)),
      assigns.class
    ]
  end
end
