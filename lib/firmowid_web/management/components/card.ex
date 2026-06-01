defmodule FirmowidWeb.Management.Components.Card do
  @moduledoc "Shared card components for the management section."
  use FirmowidWeb, :html

  attr :label, :string, required: true
  attr :class, :any, default: ""
  slot :inner_block

  def user_card_info(assigns) do
    ~H"""
    <div class={["space-y-1", @class]}>
      <div class="text-grey-700 text-sm/snug">{@label}</div>
      <div class="flex items-center gap-2 text-base/snug">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :class, :any, default: ""
  attr :gap_size, :string, default: "6"
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section class={[
      "flex flex-col rounded-md bg-white p-6 text-black shadow",
      @gap_size && "gap-y-#{@gap_size}",
      @class
    ]}>
      {render_slot(@inner_block)}
    </section>
    """
  end

  slot :inner_block

  def card_header(assigns) do
    ~H"""
    <h3 class="text-grey-900 text-base/tight font-medium">{render_slot(@inner_block)}</h3>
    """
  end
end
