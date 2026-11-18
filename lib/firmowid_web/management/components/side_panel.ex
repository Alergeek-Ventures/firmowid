defmodule FirmowidWeb.Management.Components.SidePanel do
  @moduledoc """
  The cards of Figma's "Panel boczny", beside the Projects and Counterparties lists on wide
  screens: a list in numbers and a titled card with a hint.
  """

  use FirmowidWeb, :html

  alias Phoenix.LiveView.Rendered

  @doc "Renders a list in numbers: a caps title over label and value rows."
  @spec summary_card(map()) :: Rendered.t()
  attr :title, :string, required: true
  attr :rows, :list, required: true, doc: "`{label, value}` pairs"

  def summary_card(assigns) do
    ~H"""
    <section class="flex flex-col gap-4 rounded-sm bg-white p-5">
      <h2 class="text-caps-sm/[normal] font-medium text-grey-600 uppercase">{@title}</h2>
      <dl class="flex flex-col gap-2">
        <div :for={{label, value} <- @rows} class="flex items-baseline justify-between gap-3 text-sm">
          <dt class="truncate leading-[1.35] text-grey-700">{label}</dt>
          <dd class="shrink-0 leading-[normal] font-medium text-grey-900 tabular-nums">{value}</dd>
        </div>
      </dl>
    </section>
    """
  end

  @doc "Renders a card with a caps title, an optional count beside it, and its content."
  @spec panel_card(map()) :: Rendered.t()
  attr :title, :string, required: true
  attr :count, :integer, default: nil
  slot :inner_block, required: true

  def panel_card(assigns) do
    ~H"""
    <section class="flex flex-col gap-4 rounded-sm bg-white p-5">
      <header class="flex items-center justify-between gap-3 text-grey-600">
        <h2 class="text-caps-sm/[normal] font-medium uppercase">{@title}</h2>
        <span :if={@count} class="text-sm/[1.35] tabular-nums">{@count}</span>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end
end
