defmodule FirmowidWeb.DesignSystem.Components.Alert do
  @moduledoc """
  Inline notice that stays on the page, as opposed to a transient toast.
  """

  use FirmowidUI, :html

  @tones ~w(neutral success danger)

  @doc """
  Renders an inline alert. `danger` is announced immediately (`role="alert"`);
  the other tones are polite status messages.
  """
  @spec alert(map()) :: Phoenix.LiveView.Rendered.t()
  attr :tone, :string, values: @tones, default: "neutral"
  attr :title, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true
  slot :actions

  def alert(assigns) do
    ~H"""
    <div
      role={if(@tone == "danger", do: "alert", else: "status")}
      class={["flex gap-3 rounded-lg p-4 text-sm/snug", alert_tone_styles(@tone), @class]}
      {@rest}
    >
      <Lucideicons.info :if={@tone == "neutral"} class="size-5 shrink-0 text-grey-700" />
      <Lucideicons.circle_check :if={@tone == "success"} class="size-5 shrink-0 text-moss-700" />
      <Lucideicons.triangle_alert :if={@tone == "danger"} class="size-5 shrink-0 text-brick-700" />
      <div class="flex min-w-0 flex-1 flex-col gap-1">
        <p :if={@title} class="font-medium">{@title}</p>
        <div>{render_slot(@inner_block)}</div>
        <div :if={@actions != []} class="mt-2 flex flex-wrap gap-2">{render_slot(@actions)}</div>
      </div>
    </div>
    """
  end

  defp alert_tone_styles("neutral"), do: "border border-grey-200 bg-white text-grey-900"
  defp alert_tone_styles("success"), do: "bg-moss-100 text-moss-900"
  defp alert_tone_styles("danger"), do: "bg-brick-100 text-brick-900"
end
