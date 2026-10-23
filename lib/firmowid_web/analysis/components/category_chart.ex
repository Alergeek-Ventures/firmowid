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
    unrealized = Enum.find(categories, &(&1.key == :unrealized))

    assigns =
      assigns
      |> assign(:total, total)
      |> assign(
        :realized_total,
        Decimal.sub(total, if(unrealized, do: unrealized.amount, else: 0))
      )
      |> assign(:unrealized, unrealized)
      |> assign(:slices, slices(categories, total))
      |> assign(:legend, legend(categories, total))

    ~H"""
    <section id={@id} class="flex flex-col rounded-xl border border-grey-200 bg-white p-6 sm:p-8">
      <h2 class="text-lg font-medium text-darkGrey">{@title}</h2>
      <p id={@id <> "-total"} class="mt-1 text-3xl font-semibold text-grey-900 tabular-nums">
        {Money.new(:PLN, @realized_total)}
      </p>
      <p class="mt-1 h-5 text-sm text-darkGrey tabular-nums">
        <span :if={@unrealized} id={@id <> "-unrealized"}>
          {gettext("+ %{amount} unrealized", amount: Money.new(:PLN, @unrealized.amount))}
        </span>
      </p>
      <div class="mt-8 flex flex-col items-center gap-8 xl:flex-row">
        <svg viewBox="0 0 200 200" class="size-56 shrink-0" role="img" aria-label={@title}>
          <circle :if={@slices == []} cx="100" cy="100" r="100" class="fill-grey-100" />
          <%= for slice <- @slices do %>
            <circle
              :if={slice.full}
              id={"#{@id}-slice-#{slice.index}"}
              cx="100"
              cy="100"
              r="100"
              fill={slice.color}
              phx-hook=".ChartTooltip"
              data-items={slice.tooltip}
              class="transition-opacity hover:opacity-80"
            />
            <path
              :if={not slice.full}
              id={"#{@id}-slice-#{slice.index}"}
              d={slice.path}
              fill={slice.color}
              stroke="white"
              stroke-width="1.5"
              stroke-linejoin="round"
              phx-hook=".ChartTooltip"
              data-items={slice.tooltip}
              class="transition-opacity hover:opacity-80"
            />
          <% end %>
        </svg>
        <%= if @legend == [] do %>
          <p id={@id <> "-empty"} class="h-56 py-8 text-sm text-darkGrey">
            {gettext("No entries for this month")}
          </p>
        <% else %>
          <ul id={@id <> "-legend"} class="flex h-56 w-full min-w-0 flex-col justify-center gap-5">
            <li
              :for={{row, index} <- Enum.with_index(@legend)}
              id={"#{@id}-legend-#{index}"}
              phx-hook=".ChartTooltip"
              data-items={row[:details]}
              class="flex items-center gap-3 text-sm"
            >
              <span
                class="size-3 shrink-0 rounded-full"
                style={"background-color: #{safe_color(row.color)}"}
                aria-hidden="true"
              />
              <span class="min-w-0 flex-1 truncate font-medium text-darkGrey">{row.name}</span>
              <span class="w-10 text-right text-grey-600 tabular-nums">
                {percentage(row.amount, @total)}
              </span>
              <span class="w-24 text-right tabular-nums">
                {Money.to_string!(Money.new(:PLN, row.amount), fractional_digits: 0)}
              </span>
            </li>
          </ul>
        <% end %>
      </div>
      <div class="mt-auto flex justify-end pt-8">
        <FirmowidUI.Components.Button.button
          id={@id <> "-entries"}
          variant="secondary"
          size="small"
          type="button"
          phx-click="select-section"
          phx-value-section={@section}
          aria-pressed={to_string(@active)}
          class={[@active && "invisible"]}
        >
          {gettext("Show entries")}
          <.icon name="hero-arrow-down-mini" class="size-4" />
        </FirmowidUI.Components.Button.button>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ChartTooltip">
        import tippy from "tippy.js";

        const node = (tag, className, text) => {
          const element = document.createElement(tag);
          element.className = className;
          if (text) element.textContent = text;
          return element;
        };

        const bar = (color) => {
          const element = node("span", "h-3.5 w-1 shrink-0 rounded-full");
          element.style.backgroundColor = color;
          return element;
        };

        const card = (className) =>
          node("div", `rounded-md bg-white text-left shadow-lg ${className}`);

        const single = ({name, color, amount, share}) => {
          const root = card("flex w-56 items-center gap-3 border-l-6 px-3 py-2 text-sm text-grey-900");
          root.style.borderLeftColor = color;
          const label = node("div", "flex min-w-0 flex-1 flex-col gap-0.5");
          label.append(node("span", "truncate", name), node("span", "tabular-nums", share));
          root.append(label, node("span", "shrink-0 text-lg font-semibold tabular-nums", amount));
          return root;
        };

        const list = (items) => {
          const root = card("flex flex-col gap-1.5 px-3 py-2 text-xs text-grey-900");
          items.forEach(({name, color, amount, share}) => {
            const row = node("div", "flex items-center gap-2");
            row.append(bar(color), node("span", "flex-1", name), node("span", "w-9 text-right tabular-nums", share), node("span", "min-w-16 text-right text-sm font-semibold tabular-nums", amount));
            root.append(row);
          });
          return root;
        };

        export default {
          mounted() { this.mount(); },
          updated() { this.mount(); },
          destroyed() { this.el._tippy?.destroy(); },
          mount() {
            this.el._tippy?.destroy();
            if (!this.el.dataset.items) return;
            const items = JSON.parse(this.el.dataset.items);
            const one = items.length === 1;
            tippy(this.el, {content: one ? single(items[0]) : list(items), placement: one ? "top" : "bottom", maxWidth: 320, theme: "chart", arrow: false});
          },
        };
      </script>
    </section>
    """
  end

  @doc """
  Assigns a contrasting chart palette across all project definitions, including
  projects absent from one chart. Both charts share this map, so colors do not
  change with amounts, the selected month or category filters.
  """
  @spec category_colors([map()]) :: %{(CategoryTotals.category_key() | :unrealized) => String.t()}
  def category_colors(tag_definitions) do
    tag_definitions
    |> Enum.sort_by(& &1.id)
    |> Enum.with_index()
    |> Map.new(fn {definition, index} ->
      {{:project, definition.id}, Enum.at(@palette, rem(index, length(@palette)))}
    end)
    |> Map.merge(%{
      company: "#334155",
      taxes: "#111827",
      unassigned: "#CBD5E1",
      unrealized: "#F4A9A8"
    })
  end

  defp category_name(%{key: :company}), do: gettext("Company")
  defp category_name(%{key: :taxes}), do: gettext("Taxes")
  defp category_name(%{key: :unassigned}), do: gettext("Unassigned")
  defp category_name(%{key: :unrealized}), do: gettext("Unrealized")
  defp category_name(%{name: name}), do: name

  defp percentage(amount, total) do
    amount
    |> Decimal.div(total)
    |> Firmowid.Cldr.Number.to_string!(format: :percent, fractional_digits: 0)
  end

  # Up to four categories by name; more show the three largest and an "Other" row
  # whose tooltip lists the grouped categories.
  defp legend(categories, total) do
    case Enum.split(categories, 3) do
      {top, [_, _ | _] = rest} ->
        other = %{
          name: gettext("Other"),
          color: "#94A3B8",
          amount: Enum.reduce(rest, Decimal.new(0), &Decimal.add(&1.amount, &2)),
          details: tooltip_items(rest, total)
        }

        Enum.map(top, &legend_row/1) ++ [other]

      _four_or_fewer ->
        Enum.map(categories, &legend_row/1)
    end
  end

  defp legend_row(category), do: %{name: category_name(category), color: category.color, amount: category.amount}

  defp slices(categories, total) do
    {slices, _amount} =
      categories
      |> Enum.with_index()
      |> Enum.map_reduce(Decimal.new(0), fn {category, index}, accumulated ->
        next = Decimal.add(accumulated, category.amount)
        start = fraction(accumulated, total)
        finish = fraction(next, total)

        slice = %{
          index: index,
          color: safe_color(category.color),
          full: length(categories) == 1,
          path: arc_path(start, finish),
          tooltip: tooltip_items([category], total)
        }

        {slice, next}
      end)

    slices
  end

  defp tooltip_items(categories, total) do
    categories
    |> Enum.map(fn category ->
      %{
        name: category_name(category),
        color: safe_color(category.color),
        amount: Money.to_string!(Money.new(:PLN, category.amount), fractional_digits: 0),
        share: percentage(category.amount, total)
      }
    end)
    |> Jason.encode!()
  end

  defp fraction(amount, total), do: amount |> Decimal.div(total) |> Decimal.to_float()

  defp arc_path(start, finish) do
    {x1, y1} = point(start)
    {x2, y2} = point(finish)
    large_arc = if finish - start > 0.5, do: 1, else: 0

    "M100 100 L#{coordinate(x1)} #{coordinate(y1)} A100 100 0 #{large_arc} 1 #{coordinate(x2)} #{coordinate(y2)} Z"
  end

  defp point(fraction) do
    angle = fraction * 2 * :math.pi()
    {100 + 100 * :math.sin(angle), 100 - 100 * :math.cos(angle)}
  end

  defp coordinate(value), do: :erlang.float_to_binary(value, decimals: 3)

  defp safe_color(color) do
    if is_binary(color) and Regex.match?(~r/\A#[0-9a-fA-F]{6}\z/, color),
      do: color,
      else: "#94A3B8"
  end
end
