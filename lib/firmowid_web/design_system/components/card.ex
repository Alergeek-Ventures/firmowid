defmodule FirmowidWeb.DesignSystem.Components.Card do
  @moduledoc """
  The flat-by-default exception: a raised white card for one self-contained record or settings group.
  """

  use FirmowidUI, :html

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders a card. Do not wrap lists, tables or forms in cards, and never nest them.
  """
  @spec card(map()) :: Rendered.t()
  attr :class, :any, default: ""
  attr :gap_size, :string, default: "6"
  attr :dimmed, :boolean, default: false
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section class={[
      "relative flex flex-col rounded-md bg-white p-6 text-black shadow-card",
      @gap_size && "gap-y-#{@gap_size}",
      @class
    ]}>
      <div :if={@dimmed} class="absolute inset-0 z-10 rounded-md bg-white/60"></div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc "Renders a card title with optional actions beside it."
  @spec card_header(map()) :: Rendered.t()
  slot :inner_block, required: true
  slot :actions

  def card_header(assigns) do
    ~H"""
    <div class="flex min-h-8.5 flex-row items-center gap-2">
      <h3 class="text-base/tight font-medium text-grey-900">
        {render_slot(@inner_block)}
      </h3>
      <div :if={Enum.any?(@actions)} class="flex items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end
end
