defmodule FirmowidWeb.DesignSystem.Components.Badge do
  @moduledoc """
  Status badge: a 24px tag with a pastel tint and deep text, one tone per meaning.
  """

  use FirmowidUI, :html

  @tones ~w(neutral success danger cost sales)

  @doc """
  Renders a status badge. `cost` and `sales` follow the ledger side; `success` and
  `danger` mark outcomes; everything else is `neutral`.
  """
  @spec badge(map()) :: Phoenix.LiveView.Rendered.t()
  attr :tone, :string, values: @tones, default: "neutral"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex h-6 shrink-0 items-center gap-1 rounded-md px-2 text-xs font-medium whitespace-nowrap [&>svg]:size-3.5",
        badge_tone_styles(@tone),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_tone_styles("neutral"), do: "bg-grey-200 text-grey-800"
  defp badge_tone_styles("success"), do: "bg-moss-200 text-moss-900"
  defp badge_tone_styles("danger"), do: "bg-brick-200 text-brick-800"
  defp badge_tone_styles("cost"), do: "bg-rust-200 text-rust-900"
  defp badge_tone_styles("sales"), do: "bg-teal-200 text-teal-900"
end
