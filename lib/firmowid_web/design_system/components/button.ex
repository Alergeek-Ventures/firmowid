defmodule FirmowidWeb.DesignSystem.Components.Button do
  @moduledoc """
  App-owned button primitive for the design system.

  This component is the replacement target for legacy button usages from
  `CoreComponents`. Its API is aligned with the Figma button taxonomy and keeps
  styling logic private to the component.
  """

  use FirmowidWeb, :html

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
      |> assign(:size_classes, size_classes(assigns.size))
      |> assign(:variant_classes, variant_classes(assigns.variant, assigns.accent))

    ~H"""
    <button
      type={@type}
      class={[
        "inline-flex items-center justify-center whitespace-nowrap select-none border transition duration-100 ease-out cursor-pointer disabled:pointer-events-none disabled:cursor-default phx-submit-loading:opacity-75 phx-click-loading:opacity-75 phx-click-loading:cursor-default",
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

  defp size_classes("big") do
    "h-11 gap-2.5 rounded-lg px-2.75 py-2 text-base/tight font-medium [&>svg]:size-6"
  end

  defp size_classes("small") do
    "rounded-md px-2 py-1.5 text-sm/tight font-medium gap-1.5 [&>svg]:size-4"
  end

  defp variant_classes("special", _accent) do
    [
      "border-transparent",
      "bg-black text-white",
      "hover:bg-orange-700 active:bg-orange-800",
      "disabled:bg-grey-400 disabled:text-grey-400"
    ]
  end

  defp variant_classes("primary", "orange") do
    [
      "border-transparent",
      "bg-orange-700 text-white",
      "hover:bg-orange-800 active:bg-orange-900",
      "disabled:bg-orange-400"
    ]
  end

  defp variant_classes("primary", "turquoise") do
    [
      "border-transparent",
      "bg-turquoise-700 text-white",
      "hover:bg-turquoise-800 active:bg-turquoise-900",
      "disabled:bg-turquoise-400"
    ]
  end

  defp variant_classes("secondary", _accent) do
    [
      "border-transparent",
      "bg-grey-200 text-grey-900",
      "hover:bg-grey-300 active:bg-grey-400",
      "disabled:bg-grey-100 disabled:text-grey-600"
    ]
  end

  defp variant_classes("tertiary", _accent) do
    [
      "border-transparent",
      "bg-grey-700 text-white",
      "hover:bg-grey-800 active:bg-grey-900",
      "disabled:bg-grey-600 disabled:text-grey-300"
    ]
  end

  defp variant_classes("outline", _accent) do
    [
      "border-grey-200 text-grey-900",
      "hover:bg-grey-200 active:bg-grey-300",
      "disabled:text-grey-600"
    ]
  end

  defp variant_classes("ghost", _accent) do
    [
      "border-transparent text-grey-900",
      "hover:bg-grey-200 active:bg-grey-700 active:text-white",
      "disabled:text-grey-600"
    ]
  end

  defp variant_classes("destructive", _accent) do
    [
      "border-transparent",
      "bg-redText text-white",
      "hover:bg-red-700 active:bg-red-800",
      "disabled:bg-red-300 disabled:text-white"
    ]
  end

  defp variant_classes("success", _accent) do
    [
      "border-transparent",
      "bg-blueText text-white",
      "hover:bg-blue-700 active:bg-blue-800",
      "disabled:bg-blue-300 disabled:text-white"
    ]
  end
end
