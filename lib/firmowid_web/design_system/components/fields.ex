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
  Renders a search input with a leading magnifier icon in the small (32px) or big (44px) size.
  The placeholder doubles as the accessible name.

  `collapsible` shows only a magnifier button that expands the field (it starts expanded
  when there is a value); it needs an `id`. Use it in toolbars where search is secondary.
  """
  @spec search_field(map()) :: Rendered.t()
  attr :id, :string, default: nil
  attr :collapsible, :boolean, default: false
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, required: true
  attr :size, :string, values: ~w(small big), default: "big"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(form autofocus)

  def search_field(%{collapsible: true} = assigns) do
    ~H"""
    <div
      id={@id}
      data-expanded={to_string(@value not in [nil, ""])}
      class={[
        "group flex items-center rounded-lg bg-grey-200 data-[expanded=true]:focus-within:ring-2 data-[expanded=true]:focus-within:ring-grey-700",
        @class
      ]}
    >
      <input
        type="search"
        name={@name}
        value={@value}
        placeholder={@placeholder}
        aria-label={@placeholder}
        class={[
          "w-0 border-none bg-transparent px-0 text-sm text-grey-900 opacity-0 transition-[width,opacity,padding] duration-200 ease-out group-data-[expanded=true]:w-56 group-data-[expanded=true]:px-3 group-data-[expanded=true]:opacity-100 placeholder:text-grey-500 focus:ring-0",
          search_field_size_styles(@size)
        ]}
        {@rest}
      />
      <button
        type="button"
        aria-label={@placeholder}
        title={@placeholder}
        phx-click={
          JS.toggle_attribute({"data-expanded", "true", "false"}, to: "##{@id}")
          |> JS.focus(to: "##{@id} input")
        }
        class={[
          "inline-flex shrink-0 cursor-pointer items-center justify-center text-grey-900 transition-colors hover:bg-grey-300",
          search_toggle_size_styles(@size)
        ]}
      >
        <Lucideicons.search />
      </button>
    </div>
    """
  end

  def search_field(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <Lucideicons.search class="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-grey-600" />
      <input
        type="search"
        name={@name}
        value={@value}
        placeholder={@placeholder}
        aria-label={@placeholder}
        class={[
          "w-full rounded-lg border border-grey-200 bg-grey-50 pr-3 pl-9 text-sm text-grey-900 placeholder:text-grey-500 focus:border-grey-700 focus:ring-0",
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

  defp search_field_size_styles("small"), do: "h-8"
  defp search_field_size_styles("big"), do: "h-11"

  defp search_toggle_size_styles("small"), do: "size-8 rounded-md [&>svg]:size-4"
  defp search_toggle_size_styles("big"), do: "size-11 rounded-lg [&>svg]:size-5"
end
