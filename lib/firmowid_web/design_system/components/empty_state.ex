defmodule FirmowidWeb.DesignSystem.Components.EmptyState do
  @moduledoc """
  Placeholder for a region with no data: what belongs here and the action that fills it.
  """

  use FirmowidUI, :html

  @doc """
  Renders an empty state inside a dashed placeholder. `big` suits a page or a
  section of its own; `small` (24px icon, 14px text) a panel or a list.
  """
  @spec empty_state(map()) :: Phoenix.LiveView.Rendered.t()
  attr :title, :string, required: true
  attr :size, :string, values: ~w(big small), default: "big"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :icon
  slot :inner_block, doc: "Optional description below the title."
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div
      class={[
        "flex flex-col items-center rounded-sm border border-dashed text-center",
        empty_state_size_styles(@size),
        @class
      ]}
      {@rest}
    >
      <div :if={@icon != []} class={empty_state_icon_styles(@size)}>{render_slot(@icon)}</div>
      <div class={["flex flex-col items-center", if(@size == "small", do: "gap-0.5", else: "gap-3")]}>
        <p class={empty_state_title_styles(@size)}>{@title}</p>
        <div :if={@inner_block != []} class="max-w-md text-sm/snug text-balance text-grey-600">
          {render_slot(@inner_block)}
        </div>
      </div>
      <div :if={@action != []} class="mt-3 flex flex-wrap justify-center gap-2">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  defp empty_state_size_styles("big"), do: "gap-3 border-grey-200 px-6 py-10"
  defp empty_state_size_styles("small"), do: "gap-2.5 border-grey-300 px-5 py-4"

  defp empty_state_icon_styles("big"), do: "flex text-grey-500 [&>svg]:size-10"
  defp empty_state_icon_styles("small"), do: "flex text-grey-600 [&>svg]:size-6"

  defp empty_state_title_styles("big"), do: "text-base font-medium text-grey-900"
  defp empty_state_title_styles("small"), do: "text-sm font-medium text-black"
end
