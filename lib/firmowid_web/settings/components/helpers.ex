defmodule FirmowidWeb.Settings.Components.Helpers do
  @moduledoc """
  Shared presentational helpers for settings components.
  """

  use FirmowidWeb, :html

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders a settings form field with the label above its control.
  """
  @spec settings_field(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :label_class, :any, default: nil
  slot :inner_block, required: true

  def settings_field(assigns) do
    ~H"""
    <label class={["flex flex-col gap-1", @class]}>
      <span class={["text-grey-700 text-sm leading-[1.35]", @label_class]}>{@label}</span>
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Renders a read-only settings value with the label above the displayed content.
  """
  @spec settings_display_field(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :label_class, :any, default: nil
  attr :value_class, :any, default: nil
  slot :inner_block, required: true

  def settings_display_field(assigns) do
    ~H"""
    <div class={["flex flex-col gap-1", @class]}>
      <div class={["text-grey-700 text-sm leading-[1.35]", @label_class]}>{@label}</div>
      <div class={["text-grey-900 text-base leading-[1.35]", @value_class]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
