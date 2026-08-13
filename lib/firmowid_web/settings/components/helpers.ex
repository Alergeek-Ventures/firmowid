defmodule FirmowidWeb.Settings.Components.Helpers do
  @moduledoc """
  Shared presentational helpers for settings components.
  """

  use FirmowidWeb, :html

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders a settings form field.

  With `:stacked` (default), the label is shown above the control.
  With `:row`, the label is shown to the left — matching `settings_display_field`.

  Pass `:for` with the control's `id` so clicking the label focuses the input.
  """
  @spec settings_field(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :label_class, :any, default: nil
  attr :block_class, :any, default: nil
  attr :for, :any, default: nil
  attr :layout, :atom, default: :stacked, values: [:stacked, :row]
  slot :inner_block, required: true

  def settings_field(%{layout: :row} = assigns) do
    ~H"""
    <div class={["grid grid-cols-2 items-center gap-x-5", @class]}>
      <label for={@for} class={["text-grey-700 text-right text-sm leading-[1.35]", @label_class]}>
        {@label}
      </label>
      <div class={["min-w-0", @block_class]}>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  def settings_field(assigns) do
    ~H"""
    <label for={@for} class={["flex flex-col gap-1", @class]}>
      <span class={["text-grey-700 text-sm leading-[1.35]", @label_class]}>{@label}</span>
      {render_slot(@inner_block)}
    </label>
    """
  end

  @doc """
  Renders a read-only settings value with the label next to the displayed content.

  `label` defaults to an empty string so content-only rows (for example action
  buttons) keep alignment with the value column of sibling rows.
  """
  @spec settings_display_field(map()) :: Rendered.t()
  attr :label, :string, default: ""
  attr :class, :any, default: nil
  attr :label_class, :any, default: nil
  attr :value_class, :any, default: nil
  slot :inner_block, required: true

  def settings_display_field(assigns) do
    ~H"""
    <div class={["grid grid-cols-2 items-baseline gap-x-5", @class]}>
      <div class={["text-grey-700 text-right text-sm leading-[1.35]", @label_class]}>
        {@label}
      </div>
      <div class={["text-grey-900 text-base leading-[1.35]", @value_class]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
