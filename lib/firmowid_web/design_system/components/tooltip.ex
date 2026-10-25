defmodule FirmowidWeb.DesignSystem.Components.Tooltip do
  @moduledoc """
  Tooltip on the shared Tippy hook with one delay and placement convention.
  """

  use FirmowidUI, :html

  @doc """
  Wraps content with a tooltip shown on hover and on keyboard focus. Do not put
  essential information only in a tooltip; it supplements a visible label.
  """
  @spec tooltip(map()) :: Phoenix.LiveView.Rendered.t()
  attr :id, :string, required: true
  attr :text, :string, required: true
  attr :placement, :string, values: ~w(top bottom left right), default: "top"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def tooltip(assigns) do
    ~H"""
    <span
      id={@id}
      phx-hook="Tippy"
      data-tippy-content={@text}
      data-tippy-placement={@placement}
      data-tippy-delay="[300, 0]"
      class={["inline-flex", @class]}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end
end
