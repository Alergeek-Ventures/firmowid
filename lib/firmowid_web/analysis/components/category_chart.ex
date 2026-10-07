defmodule FirmowidWeb.Analysis.Components.CategoryChart do
  @moduledoc """
  Server-rendered pie chart and accessible legend for monthly analysis categories.
  Decimal amounts remain authoritative; percentages are only a visual projection.
  """
  use FirmowidWeb, :html

  alias Firmowid.Ash.Analysis.CategoryTotals

  @palette ~w(#0072B2 #E69F00 #009E73 #CC79A7 #D55E00 #56B4E9 #6F4C9B #B6A800 #E5383B #00A6A6 #845B32 #F285B5)

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :categories, :list, required: true
  attr :colors, :map, required: true
  attr :section, :string, required: true
  attr :active, :boolean, default: false

  @doc "Renders a pie chart with amounts and percentage shares in its legend."
  @spec chart(map()) :: Phoenix.LiveView.Rendered.t()
  def chart(assigns) do
    categories =
      assigns.categories
      |> Enum.map(&Map.put(&1, :color, Map.fetch!(assigns.colors, &1.key)))
      |> Enum.sort(fn left, right ->
        case Decimal.compare(left.amount, right.amount) do
          :eq -> left.key <= right.key
          order -> order == :gt
        end
      end)

    total = Enum.reduce(categories, Decimal.new(0), &Decimal.add(&1.amount, &2))

    assigns =
      assigns
      |> assign(:categories, categories)
      |> assign(:total, total)
      |> assign(:gradient, gradient(categories, total))
      |> assign(:boundaries, boundaries(categories, total))

    ~H"""
    <section id={@id} class="border-grey-200 rounded-xl border bg-white p-6 sm:p-8">
      <h2 class="text-darkGrey text-lg font-medium">{@title}</h2>
      <p id={@id <> "-total"} class="text-grey-900 mt-1 text-3xl font-semibold tabular-nums">
        {Money.new(:PLN, @total)}
      </p>
      <div class="mt-8 flex flex-col items-center gap-8 xl:flex-row xl:items-start">
        <div
          class="bg-grey-100 size-56 shrink-0 rounded-full"
          style={@gradient}
          aria-hidden="true"
        >
          <svg
            :if={length(@categories) > 1}
            viewBox="0 0 200 200"
            class="size-full rounded-full"
          >
            <line
              :for={{x, y} <- @boundaries}
              x1="100"
              y1="100"
              x2={x}
              y2={y}
              stroke="white"
              stroke-width="1.5"
            />
          </svg>
        </div>
        <%= if @categories == [] do %>
          <p id={@id <> "-empty"} class="text-darkGrey py-8 text-sm">
            {gettext("No entries for this month")}
          </p>
        <% else %>
          <ul id={@id <> "-legend"} class="w-full min-w-0 space-y-4">
            <li :for={category <- @categories} class="flex items-start gap-3">
              <span
                class="mt-1 size-3 shrink-0 rounded-full"
                style={"background-color: #{safe_color(category.color)}"}
                aria-hidden="true"
              />
              <div class="min-w-0 flex-1">
                <span class="text-darkGrey block text-sm font-medium wrap-break-word">
                  {category_name(category)}
                </span>
                <div class="mt-1 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1 text-sm tabular-nums">
                  <span>{Money.new(:PLN, category.amount)}</span>
                  <span class="text-grey-600">{percentage(category.amount, @total)}</span>
                </div>
              </div>
            </li>
          </ul>
        <% end %>
      </div>
      <FirmowidWeb.DesignSystem.Components.Button.button
        id={@id <> "-entries"}
        variant="secondary"
        size="small"
        type="button"
        phx-click="select-section"
        phx-value-section={@section}
        aria-pressed={to_string(@active)}
        class="mt-8"
      >
        {gettext("Show entries")}
        <.icon name="hero-arrow-down-mini" class="size-4" />
      </FirmowidWeb.DesignSystem.Components.Button.button>
    </section>
    """
  end

  @doc """
  Assigns a contrasting chart palette across all project definitions, including
  projects absent from one chart. Both charts share this map, so colors do not
  change with amounts, the selected month or category filters.
  """
  @spec category_colors([map()]) :: %{CategoryTotals.category_key() => String.t()}
  def category_colors(tag_definitions) do
    tag_definitions
    |> Enum.sort_by(& &1.id)
    |> Enum.with_index()
    |> Map.new(fn {definition, index} ->
      {{:project, definition.id}, Enum.at(@palette, rem(index, length(@palette)))}
    end)
    |> Map.merge(%{company: "#334155", unassigned: "#CBD5E1"})
  end

  defp category_name(%{key: :company}), do: gettext("Company")
  defp category_name(%{key: :unassigned}), do: gettext("Unassigned")
  defp category_name(%{name: name}), do: name

  defp percentage(amount, total) do
    amount
    |> Decimal.div(total)
    |> Firmowid.Cldr.Number.to_string!(format: :percent, fractional_digits: 1)
  end

  @spec gradient([CategoryTotals.category()], Decimal.t()) :: String.t() | nil
  defp gradient([], _total), do: nil

  defp gradient(categories, total) do
    {stops, _amount} =
      Enum.map_reduce(categories, Decimal.new(0), fn category, accumulated ->
        next = Decimal.add(accumulated, category.amount)
        start = gradient_percentage(accumulated, total)
        finish = gradient_percentage(next, total)
        {"#{safe_color(category.color)} #{start}% #{finish}%", next}
      end)

    "background-image: conic-gradient(#{Enum.join(stops, ", ")})"
  end

  defp gradient_percentage(amount, total) do
    amount
    |> Decimal.div(total)
    |> Decimal.mult(100)
    |> Decimal.round(6)
    |> Decimal.to_string(:normal)
  end

  defp boundaries([], _total), do: []

  defp boundaries(categories, total) do
    {points, _amount} =
      Enum.map_reduce(categories, Decimal.new(0), fn category, accumulated ->
        angle = Decimal.to_float(Decimal.div(accumulated, total)) * 2 * :math.pi()
        point = {100 + 100 * :math.sin(angle), 100 - 100 * :math.cos(angle)}
        {point, Decimal.add(accumulated, category.amount)}
      end)

    points
  end

  defp safe_color(color) do
    if is_binary(color) and Regex.match?(~r/\A#[0-9a-fA-F]{6}\z/, color),
      do: color,
      else: "#94A3B8"
  end
end
