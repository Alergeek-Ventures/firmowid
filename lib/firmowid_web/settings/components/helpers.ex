defmodule FirmowidWeb.Settings.Components.Helpers do
  @moduledoc """
  Shared presentational helpers for settings components.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.Settings.Components.EditButton

  alias Phoenix.LiveView.Rendered

  @doc "Renders a settings section with its title and, when given an `action`, its edit button."
  @spec settings_section(map()) :: Rendered.t()
  attr :title, :string, required: true
  attr :action, :any, default: nil
  attr :action_label, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def settings_section(assigns) do
    ~H"""
    <section class={["space-y-4", @class]}>
      <div class="flex min-h-8 items-center gap-1">
        <h2 class="text-base leading-none font-medium text-grey-900">{@title}</h2>

        <span
          :if={@action}
          id={"settings-#{@action}-tooltip"}
          phx-hook="Tippy"
          data-tippy-content={@action_label || gettext("Edit %{section}", section: @title)}
          data-tippy-delay="100"
          data-tippy-theme="small"
        >
          <.edit_button
            type="button"
            phx-click={@action}
            aria-label={@action_label || gettext("Edit %{section}", section: @title)}
          />
        </span>
      </div>

      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc "Renders a read-only value of a settings section."
  @spec detail_row(map()) :: Rendered.t()
  attr :label, :string, required: true
  slot :inner_block, required: true

  def detail_row(assigns) do
    ~H"""
    <.settings_display_field label={@label} class="justify-center" value_class="break-words">
      {render_slot(@inner_block)}
    </.settings_display_field>
    """
  end

  @doc "Renders a form input with its label to the left."
  @spec row_input(map()) :: Rendered.t()
  attr :field, :map, required: true
  attr :label, :string, required: true
  attr :type, :string, required: true
  attr :label_class, :string, default: nil

  def row_input(assigns) do
    ~H"""
    <.settings_field label={@label} layout={:row} for={@field.id} label_class={@label_class}>
      <.input field={@field} type={@type} input_class="w-full" />
    </.settings_field>
    """
  end

  @doc "Shows a missing value as a dash."
  @spec present(term()) :: String.t()
  def present(nil), do: "—"
  def present(""), do: "—"
  def present(value), do: to_string(value)

  @doc "Returns the uppercase first letter of a name, for an avatar without a picture."
  @spec initial(term()) :: String.t()
  def initial(name) do
    name
    |> to_string()
    |> String.slice(0, 1)
    |> String.upcase()
  end

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
      <label for={@for} class={["text-right text-sm/snug text-grey-700", @label_class]}>
        {@label}
      </label>
      <div class={["min-w-0", @block_class]}>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  def settings_field(assigns) do
    ~H"""
    <label for={@for} class={["flex flex-col gap-1", @class]}>
      <span class={["text-sm/snug text-grey-700", @label_class]}>{@label}</span>
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
      <div class={["text-right text-sm/snug text-grey-700", @label_class]}>
        {@label}
      </div>
      <div class={["text-base/snug text-grey-900", @value_class]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
