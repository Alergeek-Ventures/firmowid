defmodule FirmowidWeb.DesignSystem.Components.Fields do
  @moduledoc """
  Layout pieces around form controls and read-only values: a labelled row and a search field.
  """

  use FirmowidUI, :html

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders a label with its value or control. `stacked` puts the label above;
  `inline` puts a right-aligned label beside the value (detail and settings panels).
  Pass `for` when the content is a form control so the label targets it.
  """
  @spec field_row(map()) :: Rendered.t()
  attr :label, :string, required: true
  attr :for, :string, default: nil
  attr :layout, :string, values: ~w(stacked inline), default: "stacked"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def field_row(assigns) do
    ~H"""
    <div class={[field_row_layout_styles(@layout), @class]}>
      <label :if={@for} for={@for} class={field_row_label_styles(@layout)}>{@label}</label>
      <span :if={!@for} class={field_row_label_styles(@layout)}>{@label}</span>
      <div class="min-w-0 text-base/snug text-grey-900">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  @doc """
  Renders a search input with a leading magnifier icon in the small (32px) or big (40px) size.
  The placeholder doubles as the accessible name.
  """
  @spec search_field(map()) :: Rendered.t()
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, required: true
  attr :size, :string, values: ~w(small big), default: "big"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(form autofocus autocomplete maxlength)

  def search_field(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <Lucideicons.search class={[
        "pointer-events-none absolute top-1/2 -translate-y-1/2 text-grey-500",
        search_field_icon_styles(@size)
      ]} />
      <input
        type="search"
        name={@name}
        value={@value}
        placeholder={@placeholder}
        aria-label={@placeholder}
        class={[
          "w-full rounded-sm border border-grey-200 bg-grey-100 text-sm text-grey-700 transition-colors placeholder:text-grey-400 hover:placeholder:text-grey-500 focus:border-teal-300 focus:shadow-[inset_0_0_0_1px_var(--color-teal-300)] focus:ring-0 focus:outline-none",
          search_field_size_styles(@size)
        ]}
        {@rest}
      />
    </div>
    """
  end

  defp field_row_layout_styles("stacked"), do: "flex flex-col gap-1"
  defp field_row_layout_styles("inline"), do: "grid grid-cols-2 items-baseline gap-x-5"

  defp field_row_label_styles("stacked"), do: "text-sm/snug text-grey-700"
  defp field_row_label_styles("inline"), do: "text-right text-sm/snug text-grey-700"

  # Figma "Search bar": the magnifier sits 6px (8px big) from the edge, 8px before the text.
  defp search_field_size_styles("small"), do: "h-8 pr-1 pl-8.5"
  defp search_field_size_styles("big"), do: "h-10 pr-2 pl-10"

  defp search_field_icon_styles("small"), do: "left-1.5 size-5"
  defp search_field_icon_styles("big"), do: "left-2 size-6"
end
