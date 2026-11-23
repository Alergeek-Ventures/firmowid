defmodule FirmowidWeb.Analysis.Components.FirstReview do
  @moduledoc """
  The owner's first look at the analysis categories, over the whole screen like
  the company onboarding: the organization's categories as compartments sized by
  the period's money, then the counterparties whose category the classifier is
  unsure about, the largest first, one at a time, then what was checked.

  A compartment is solid where the category is certain or confirmed and hatched
  where only the classifier suggested it. The counterparty under review is the
  outlined segment in the compartment of its category; choosing one sends
  `confirm-category` (as the period details do), so it settles, solid, in the
  chosen compartment. Back, skip and next send `first-review-step` with an
  `index`, the intro sends `first-review-start` and closing sends
  `first-review-close`, so nothing changes without the owner's choice.
  """
  use FirmowidWeb, :html

  import FirmowidWeb.Analysis.Utilities.Amounts, only: [whole_money: 1]

  alias Firmowid.Analysis.CategoryReview
  alias FirmowidWeb.Analysis.Components.PeriodDetails
  alias FirmowidWeb.Analysis.Utilities.Industry

  @id "analysis-first-review"

  @doc "How many counterparties the review goes through at most."
  @spec size() :: pos_integer()
  def size, do: 6

  attr :review, :map, required: true, doc: "the period's `Analysis.get_category_review/2` result"

  attr :steps, :list,
    required: true,
    doc: "the `{side, key}` of the counterparties being reviewed, nil before the review starts"

  attr :index, :integer,
    required: true,
    doc: "the shown counterparty's index; the length of `steps` once done"

  attr :period, :string, required: true, doc: "the reviewed months, as the summary names them"

  @doc "Renders the first review over the whole screen."
  @spec review(map()) :: Phoenix.LiveView.Rendered.t()
  def review(assigns) do
    stage =
      cond do
        assigns.steps == nil -> :intro
        assigns.index < length(assigns.steps) -> :counterparty
        true -> :done
      end

    assigns = assign(assigns, id: @id, stage: stage)

    ~H"""
    <div
      id={@id}
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-mounted={JS.add_class("overflow-hidden", to: "body")}
      phx-remove={JS.remove_class("overflow-hidden", to: "body")}
      phx-window-keydown="first-review-close"
      phx-key="escape"
      class="fixed inset-0 z-50 overflow-y-auto overscroll-contain bg-grey-100"
    >
      <.focus_wrap
        id={"#{@id}-focus"}
        class="mx-auto flex min-h-full max-w-7xl flex-col px-4 pb-10 sm:px-8 lg:px-20"
      >
        <.top_bar id={@id} stage={@stage} steps={@steps} index={@index} />
        <.intro :if={@stage == :intro} id={@id} review={@review} period={@period} />
        <.counterparty
          :if={@stage == :counterparty}
          id={@id}
          review={@review}
          steps={@steps}
          index={@index}
          period={@period}
        />
        <.done :if={@stage == :done} id={@id} review={@review} steps={@steps} period={@period} />
      </.focus_wrap>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :stage, :atom, required: true
  attr :steps, :list, required: true
  attr :index, :integer, required: true

  # As the company onboarding's header: the way back (the wordmark without one), the progress, the way out.
  defp top_bar(assigns) do
    ~H"""
    <header class="sticky top-0 z-10 grid grid-cols-[1fr_auto_1fr] items-center gap-3 bg-grey-100 py-6 lg:py-8">
      <%= if @stage != :intro and @index > 0 do %>
        <FirmowidUI.Components.Button.button
          id={"#{@id}-back"}
          type="button"
          variant="unstyled"
          phx-click={JS.push("first-review-step", value: %{index: @index - 1})}
          class="group -ml-1 flex w-fit cursor-pointer items-center gap-1.5 rounded-lg px-1 py-2 text-[0.9375rem] font-medium text-grey-700 transition-colors hover:text-black max-sm:ml-0 max-sm:size-10.5 max-sm:justify-center max-sm:border max-sm:border-grey-300 max-sm:bg-white max-sm:p-0 max-sm:text-grey-900"
        >
          <Lucideicons.arrow_left
            class="size-4 transition-transform group-hover:-translate-x-0.5 max-sm:size-4.5"
            aria-hidden="true"
          />
          <span class="max-sm:sr-only">{gettext("Back")}</span>
        </FirmowidUI.Components.Button.button>
      <% else %>
        <span class="font-logo text-2xl font-bold tracking-tight text-grey-900 max-sm:hidden">
          Firmowid
        </span>
        <img src={~p"/images/logo-head.svg"} alt="Firmowid" class="size-9 sm:hidden" />
      <% end %>

      <p :if={@stage != :intro} class="flex items-center gap-1.5 text-sm text-grey-600 sm:gap-2">
        <span class="flex items-center gap-1.5 sm:gap-2" aria-hidden="true">
          <span
            :for={number <- 1..length(@steps)//1}
            class={["h-1 w-5 rounded-full sm:w-7", progress_styles(number <= @index + 1)]}
          ></span>
        </span>
        <span :if={@stage == :counterparty} class="ms-1 max-md:sr-only">
          {gettext("Counterparty %{position} of %{count}",
            position: @index + 1,
            count: length(@steps)
          )}
        </span>
      </p>

      <FirmowidUI.Components.Button.button
        id={"#{@id}-later"}
        type="button"
        variant="unstyled"
        phx-click="first-review-close"
        class="col-start-3 cursor-pointer justify-self-end rounded-lg px-1 py-2 text-[0.9375rem] font-medium whitespace-nowrap text-grey-700 underline underline-offset-4 hover:text-black"
      >
        {if @stage == :done, do: gettext("Close"), else: gettext("Finish later")}
      </FirmowidUI.Components.Button.button>
    </header>
    """
  end

  attr :id, :string, required: true
  attr :review, :map, required: true
  attr :period, :string, required: true

  # What the owner sees first: how Firmowid sorts the period's money, and what it doubts.
  defp intro(assigns) do
    assigns =
      assign(assigns,
        uncertain: length(CategoryReview.to_check(assigns.review, size())),
        classifying: assigns.review.unclassified != []
      )

    ~H"""
    <div
      id={"#{@id}-intro"}
      phx-mounted={JS.focus(to: "##{@id}-title")}
      class="grid items-start gap-10 motion-safe:animate-step-in lg:grid-cols-[minmax(0,26rem)_minmax(0,1fr)] lg:gap-20"
    >
      <section class="lg:sticky lg:top-28">
        <h2
          id={"#{@id}-title"}
          tabindex="-1"
          class="text-2xl/tight font-semibold tracking-tight text-balance text-grey-900 outline-none sm:text-[2.625rem]/[1.1]"
        >
          {gettext("This is how Firmowid sorts your money")}
        </h2>
        <p class="mt-4 text-[1.0625rem]/relaxed text-grey-700">
          {gettext("Industry: %{industry}.", industry: Industry.label(@review.industry))}
        </p>
        <p class="mt-4 text-[1.0625rem]/relaxed text-grey-700">
          <%= cond do %>
            <% @uncertain > 0 -> %>
              {gettext(
                "Firmowid sorts costs and income into categories, shown as these bars. Check the counterparties whose category it is unsure about."
              )}
            <% @classifying -> %>
              {gettext(
                "Firmowid is still choosing the categories. Once it is done, the counterparties it is least sure of will be here to check."
              )}
            <% true -> %>
              {gettext("No category of this period waits for your check.")}
          <% end %>
        </p>
        <FirmowidUI.Components.Button.button
          :if={@uncertain > 0}
          id={"#{@id}-start"}
          type="button"
          variant="special"
          phx-click="first-review-start"
          class="mt-8"
        >
          {gettext("Check counterparties")}
          <Lucideicons.arrow_right aria-hidden="true" />
        </FirmowidUI.Components.Button.button>
      </section>
      <div class="grid gap-12">
        <.legend />
        <.compartments
          :for={side <- [:expenses, :income]}
          id={"#{@id}-#{side}"}
          side={side}
          title={side_title(side, @period)}
          bins={bins(@review, side, nil)}
        />
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :review, :map, required: true
  attr :steps, :list, required: true
  attr :index, :integer, required: true
  attr :period, :string, required: true

  # One counterparty: what Firmowid knows and how sure it is, the categories to choose from,
  # and the compartments of its side with the counterparty where it lies now.
  defp counterparty(assigns) do
    step = Enum.at(assigns.steps, assigns.index)
    groups = groups(assigns.review, step)
    group = group(groups)
    amount = sum(groups)
    category = group.category || group.suggestion

    assigns =
      assign(assigns,
        group: group,
        amount: amount,
        step_id: "#{assigns.id}-step-#{assigns.index}",
        confirmed: group.status == :confirmed,
        # Two or more comparable categories are a real choice, not a suggestion to keep.
        hesitating: group.status != :confirmed and length(group.options) > 1,
        bins:
          bins(assigns.review, group.side, %{
            key: step,
            name: group.name,
            amount: amount,
            category: category,
            confirmed: group.status == :confirmed
          })
      )

    ~H"""
    <div
      id={@step_id}
      phx-mounted={JS.focus(to: "##{@step_id}-name")}
      class="grid items-start gap-10 motion-safe:animate-step-in lg:grid-cols-[minmax(0,26rem)_minmax(0,1fr)] lg:gap-20"
    >
      <section class="lg:sticky lg:top-28">
        <h2
          id={"#{@id}-title"}
          class="text-2xl/tight font-semibold tracking-tight wrap-anywhere text-grey-900 sm:text-[2.625rem]/[1.1]"
        >
          <span id={"#{@step_id}-name"} tabindex="-1" class="outline-none">{@group.name}</span>
        </h2>
        <p class="mt-3 text-[1.0625rem]/relaxed text-grey-700">
          <span class="font-medium text-grey-900 tabular-nums">{whole_money(@amount)}</span>
          · {reason(@group)}
        </p>
        <%= if @confirmed do %>
          <p class="mt-6 text-[1.0625rem]/relaxed text-grey-900">
            {gettext("Saved: %{category}. Future entries of this counterparty go there too.",
              category: PeriodDetails.category_label(@group.category)
            )}
          </p>
        <% else %>
          <p class="mt-6 text-xl/snug font-medium text-grey-900">
            <%= if @hesitating do %>
              {gettext("Firmowid hesitates. Which category fits?")}
            <% else %>
              {gettext("Firmowid suggests %{category}. Keep it?",
                category: PeriodDetails.category_label(@group.suggestion)
              )}
            <% end %>
          </p>
          <p class="mt-2 text-[0.9375rem]/relaxed text-grey-600">
            <span :if={!@hesitating}>{certainty(CategoryReview.certainty(@group.probability))}</span>
            {gettext("Your choice covers all entries of this counterparty, also future ones.")}
          </p>
        <% end %>
        <div :if={@hesitating} class="mt-8 grid gap-1.5">
          <FirmowidUI.Components.Button.button
            :for={option <- @group.options}
            id={"#{@id}-option-#{option}"}
            type="button"
            variant="unstyled"
            phx-click={choose(@group, option)}
            class="flex w-full cursor-pointer items-center rounded-xl border border-grey-300 bg-white px-4.5 py-3.5 text-start text-[0.9375rem] text-grey-900 transition-colors hover:border-black"
          >
            {PeriodDetails.category_label(option)}
          </FirmowidUI.Components.Button.button>
        </div>
        <div class={[
          "flex flex-wrap items-center gap-x-6 gap-y-3",
          if(@hesitating, do: "mt-4", else: "mt-8")
        ]}>
          <FirmowidUI.Components.Button.button
            :if={!@confirmed and !@hesitating}
            id={"#{@id}-keep"}
            type="button"
            variant="special"
            phx-click={choose(@group, @group.suggestion)}
          >
            {gettext("Yes, keep it")}
          </FirmowidUI.Components.Button.button>
          <FirmowidUI.Components.Button.button
            :if={@confirmed}
            id={"#{@id}-next"}
            type="button"
            variant="special"
            phx-click={JS.push("first-review-step", value: %{index: @index + 1})}
          >
            {gettext("Next")}
            <Lucideicons.arrow_right aria-hidden="true" />
          </FirmowidUI.Components.Button.button>
          <FirmowidUI.Components.Button.button
            :if={!@confirmed}
            id={"#{@id}-skip"}
            type="button"
            variant="unstyled"
            phx-click={JS.push("first-review-step", value: %{index: @index + 1})}
            class="group flex cursor-pointer items-center gap-1.5 py-2 text-[0.9375rem] font-medium text-grey-700 hover:text-black"
          >
            {gettext("Skip for now")}
            <Lucideicons.arrow_right
              class="size-4 transition-transform group-hover:translate-x-0.5"
              aria-hidden="true"
            />
          </FirmowidUI.Components.Button.button>
        </div>
      </section>
      <div class="grid gap-12">
        <.legend />
        <.compartments
          id={"#{@step_id}-compartments"}
          side={@group.side}
          title={side_title(@group.side, @period)}
          hint={gettext("Click a category to choose it.")}
          bins={@bins}
          choose={&choose(@group, &1)}
          choice_id={&"#{@step_id}-#{&1}"}
        />
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :review, :map, required: true
  attr :steps, :list, required: true
  attr :period, :string, required: true

  defp done(assigns) do
    checked = Enum.count(assigns.steps, &(group(groups(assigns.review, &1)).status == :confirmed))
    assigns = assign(assigns, checked: checked)

    ~H"""
    <div
      id={"#{@id}-done"}
      phx-mounted={JS.focus(to: "##{@id}-title")}
      class="grid items-start gap-10 motion-safe:animate-step-in lg:grid-cols-[minmax(0,26rem)_minmax(0,1fr)] lg:gap-20"
    >
      <section class="lg:sticky lg:top-28">
        <h2
          id={"#{@id}-title"}
          tabindex="-1"
          class="text-2xl/tight font-semibold tracking-tight text-balance text-grey-900 outline-none sm:text-[2.625rem]/[1.1]"
        >
          {gettext("Review finished")}
        </h2>
        <p class="mt-4 text-[1.0625rem]/relaxed text-grey-900">
          {gettext("Confirmed: %{checked} of %{count}", checked: @checked, count: length(@steps))}
        </p>
        <p class="mt-2 text-[1.0625rem]/relaxed text-grey-700">
          {gettext(
            "Skipped counterparties stay as they are; %{button} brings you back to them. You can change any category later in the analysis.",
            button: gettext("Check categories")
          )}
        </p>
        <FirmowidUI.Components.Button.button
          id={"#{@id}-close"}
          type="button"
          variant="special"
          phx-click="first-review-close"
          class="mt-8"
        >
          {gettext("Go to the analysis")}
        </FirmowidUI.Components.Button.button>
      </section>
      <div class="grid gap-12">
        <.legend />
        <.compartments
          :for={side <- [:expenses, :income]}
          id={"#{@id}-done-#{side}"}
          side={side}
          title={side_title(side, @period)}
          bins={bins(@review, side, nil)}
        />
      </div>
    </div>
    """
  end

  # What solid and hatched money mean, with a swatch of each.
  defp legend(assigns) do
    ~H"""
    <p class="flex flex-wrap items-center gap-x-6 gap-y-2 text-sm text-grey-700">
      <span class="flex items-center gap-2">
        <span class={["h-3 w-6 rounded-xs", solid_styles(:expenses)]} aria-hidden="true"></span>
        {gettext("Solid: confirmed or certain")}
      </span>
      <span class="flex items-center gap-2">
        <span class={["h-3 w-6 rounded-xs", hatched_styles(:expenses)]} aria-hidden="true"></span>
        {gettext("Hatched: suggested by Firmowid")}
      </span>
    </p>
    """
  end

  attr :id, :string, required: true
  attr :side, :atom, required: true
  attr :title, :string, required: true
  attr :bins, :list, required: true

  attr :choose, :any,
    default: nil,
    doc: "the JS command that puts the reviewed counterparty into a category; rows are buttons with it"

  attr :choice_id, :any, default: nil, doc: "the id of a category's row button"
  attr :hint, :string, default: nil, doc: "what to do with the compartments, under the title"

  # One bar per category, as wide as its money; the reviewed counterparty is the outlined segment.
  defp compartments(assigns) do
    widest = assigns.bins |> Enum.map(& &1.total) |> Enum.max(Decimal, fn -> Decimal.new(0) end)
    item = Enum.find_value(assigns.bins, & &1.item)
    assigns = assign(assigns, widest: widest, item: item)

    ~H"""
    <section id={@id} aria-labelledby={"#{@id}-title"}>
      <h3 id={"#{@id}-title"} class="text-sm font-medium text-grey-600">{@title}</h3>
      <p :if={@hint} class="mt-1 text-sm text-grey-600">{@hint}</p>
      <ul class="mt-3 grid gap-x-4 sm:grid-cols-[minmax(0,13rem)_minmax(0,1fr)_auto]">
        <li
          :for={bin <- @bins}
          id={"#{@id}-#{bin.key}"}
          class="sm:col-span-3 sm:grid sm:grid-cols-subgrid"
        >
          <%= if @choose do %>
            <FirmowidUI.Components.Button.button
              id={@choice_id.(bin.key)}
              type="button"
              variant="unstyled"
              aria-pressed={to_string(bin.item != nil and bin.item.confirmed)}
              phx-click={@choose.(bin.key)}
              class="group -mx-3 grid w-[calc(100%+1.5rem)] cursor-pointer grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-1.5 rounded-lg px-3 py-2 text-start text-sm transition-colors hover:bg-white sm:col-span-3 sm:w-auto sm:grid-cols-subgrid"
            >
              <.bin_row bin={bin} side={@side} widest={@widest} ghost={@item} choosing />
            </FirmowidUI.Components.Button.button>
          <% else %>
            <div class="grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-1.5 py-2 text-sm sm:col-span-3 sm:grid-cols-subgrid">
              <.bin_row bin={bin} side={@side} widest={@widest} />
            </div>
          <% end %>
        </li>
      </ul>
    </section>
    """
  end

  attr :bin, :map, required: true
  attr :side, :atom, required: true
  attr :widest, :any, required: true

  attr :ghost, :map,
    default: nil,
    doc: "the reviewed counterparty, whose dashed outline shows where it would go"

  attr :choosing, :boolean,
    default: false,
    doc: "whether the row is a choice, which keeps an empty bar for the outline"

  defp bin_row(assigns) do
    ~H"""
    <span class={["min-w-0", bin_label_styles(@bin, @choosing)]}>
      {PeriodDetails.category_label(@bin.key)}
      <span :if={@bin.item} class="block truncate text-xs font-normal text-grey-600">
        {whole_money(@bin.item.amount)} · {@bin.item.name}
      </span>
    </span>
    <span
      class={[
        "col-span-2 row-start-2 flex h-6 gap-0.5 sm:col-span-1 sm:row-start-auto sm:h-7",
        !@choosing and Decimal.eq?(@bin.total, 0) and "max-sm:hidden"
      ]}
      aria-hidden="true"
    >
      <span
        :if={Decimal.positive?(@bin.solid)}
        class={["h-full rounded-sm", solid_styles(@side)]}
        style={"width: #{share(@bin.solid, @widest)}%"}
      ></span>
      <span
        :if={Decimal.positive?(@bin.hatched)}
        class={["h-full rounded-sm", hatched_styles(@side)]}
        style={"width: #{share(@bin.hatched, @widest)}%"}
      ></span>
      <span
        :if={@bin.item}
        id={"analysis-first-review-item-#{@bin.key}-#{@bin.item.confirmed}"}
        class={[
          "h-full min-w-10 origin-left rounded-sm ring-2 ring-grey-900 transition-[scale] duration-500 ease-out motion-reduce:transition-none starting:scale-x-0",
          item_styles(@side, @bin.item.confirmed)
        ]}
        style={"width: #{share(@bin.item.amount, @widest)}%"}
      ></span>
      <span
        :if={@ghost && !@bin.item}
        class="hidden h-full min-w-10 rounded-sm border-2 border-dashed border-grey-500 group-hover:block group-focus-visible:block"
        style={"width: #{share(@ghost.amount, @widest)}%"}
      ></span>
    </span>
    <span class="col-start-2 row-start-1 text-end tabular-nums sm:col-start-auto sm:row-start-auto">
      {whole_money(@bin.total)}
    </span>
    """
  end

  # The categories of a side with their money: solid where certain or confirmed, hatched where
  # only suggested. The reviewed counterparty's money lies, as `item`, in the compartment of its
  # category, apart from the rest; `total` counts it in.
  defp bins(review, side, item) do
    groups =
      Enum.filter(review.groups, fn group ->
        group.side == side and (group.category || group.suggestion) != nil and
          (item == nil or {group.side, group.key} != item.key)
      end)

    for %{key: key} <- Map.fetch!(review, side).categories do
      in_bin = Enum.filter(groups, &((&1.category || &1.suggestion) == key))
      {hatched, solid} = Enum.split_with(in_bin, &(&1.source == :jev))
      item = if item && item.category == key, do: item

      %{
        key: key,
        solid: sum(solid),
        hatched: sum(hatched),
        item: item,
        total: Decimal.add(sum(in_bin), if(item, do: item.amount, else: 0))
      }
    end
  end

  defp sum(groups), do: Enum.reduce(groups, Decimal.new(0), &Decimal.add(&1.amount, &2))

  defp share(amount, widest) do
    if Decimal.positive?(widest),
      do:
        amount
        |> Decimal.mult(100)
        |> Decimal.div(widest)
        |> Decimal.round(2)
        |> Decimal.to_string(),
      else: "0"
  end

  # A counterparty's groups: one per suggested category, or one once the owner confirmed it.
  defp groups(review, {side, key}), do: Enum.filter(review.groups, &(&1.side == side and &1.key == key))

  # The counterparty as the owner left it: its confirmed group, else its least certain suggestion.
  defp group(groups) do
    Enum.find(groups, &(&1.status == :confirmed)) ||
      groups |> Enum.filter(& &1.probability) |> Enum.min_by(& &1.probability)
  end

  # Confirms the counterparty's category, as the period details do.
  defp choose(group, category) do
    JS.push("confirm-category",
      value: %{
        side: group.side,
        key: group.key,
        suggestion: to_string(group.suggestion),
        source: to_string(group.source),
        category: category
      }
    )
  end

  defp reason(%{reason: [line | _]}), do: gettext("From the document: %{text}", text: line)
  defp reason(_group), do: gettext("Chosen from the counterparty's name")

  # The classifier's probability in words, so the owner reads how sure it is without a number.
  defp certainty(:almost_sure), do: gettext("Firmowid is almost sure.")
  defp certainty(:fairly_sure), do: gettext("Firmowid is fairly sure.")
  defp certainty(:guessing), do: gettext("Firmowid is guessing.")

  defp side_title(:expenses, period), do: gettext("Costs · %{period}", period: period)
  defp side_title(:income, period), do: gettext("Income · %{period}", period: period)

  defp progress_styles(true), do: "bg-black"
  defp progress_styles(false), do: "bg-grey-200"

  defp bin_label_styles(%{item: %{}}, _choosing), do: "font-semibold text-grey-900"
  defp bin_label_styles(_bin, true), do: "text-grey-900"

  defp bin_label_styles(%{total: total}, false),
    do: if(Decimal.positive?(total), do: "text-grey-700", else: "text-grey-500")

  defp solid_styles(:expenses), do: "bg-rust-600"
  defp solid_styles(:income), do: "bg-teal-600"

  defp hatched_styles(:expenses),
    do: "bg-[repeating-linear-gradient(135deg,var(--color-rust-300)_0_4px,var(--color-rust-100)_4px_8px)]"

  defp hatched_styles(:income),
    do: "bg-[repeating-linear-gradient(135deg,var(--color-teal-300)_0_4px,var(--color-teal-100)_4px_8px)]"

  defp item_styles(:expenses, true), do: "bg-rust-800"
  defp item_styles(:income, true), do: "bg-teal-800"

  defp item_styles(:expenses, false),
    do: "bg-[repeating-linear-gradient(135deg,var(--color-rust-500)_0_4px,var(--color-rust-200)_4px_8px)]"

  defp item_styles(:income, false),
    do: "bg-[repeating-linear-gradient(135deg,var(--color-teal-500)_0_4px,var(--color-teal-200)_4px_8px)]"
end
