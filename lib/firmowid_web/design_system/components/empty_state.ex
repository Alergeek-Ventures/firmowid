defmodule FirmowidWeb.DesignSystem.Components.EmptyState do
  @moduledoc """
  Placeholder for a region with no data: what belongs here and the action that fills it.
  """

  use FirmowidUI, :html

  @doc """
  Renders an empty state inside a dashed placeholder.
  """
  @spec empty_state(map()) :: Phoenix.LiveView.Rendered.t()
  attr :title, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global
  slot :icon
  slot :inner_block, doc: "Optional description below the title."
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div
      class={[
        "flex flex-col items-center gap-3 rounded-lg border border-dashed border-grey-200 px-6 py-10 text-center",
        @class
      ]}
      {@rest}
    >
      <div :if={@icon != []} class="text-grey-500 [&>svg]:size-10">{render_slot(@icon)}</div>
      <p class="text-base font-medium text-grey-900">{@title}</p>
      <div :if={@inner_block != []} class="max-w-md text-sm/snug text-balance text-grey-600">
        {render_slot(@inner_block)}
      </div>
      <div :if={@action != []} class="mt-3 flex flex-wrap justify-center gap-2">
        {render_slot(@action)}
      </div>
    </div>
    """
  end
end
