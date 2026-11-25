defmodule FirmowidWeb.Inbox.Components.Queue do
  @moduledoc """
  Inbox building blocks: queue rows grouped by tier, the member's session, who
  works today and the month in numbers.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidUI.Utilities.ButtonStyles
  alias FirmowidWeb.Inbox.Utilities.Queue
  alias FirmowidWeb.Invoicing.Components.CostInvoiceUpload

  @doc """
  A queue item, a row of its group's card: the tile coloured by its kind, the title
  linking to the item's page, one meta line and its actions. The tile puts the
  item aside (`snooze_menu/1`), except for urgent items, which keep the solid
  black button; leave requests decide in place.
  """
  attr :item, :map, required: true
  attr :fresh, :boolean, default: false, doc: "arrived while the page was open; it lights up once"

  attr :today, Date,
    required: true,
    doc: "the organization's today, for the days the menu puts it aside until"

  def item_row(assigns) do
    assigns = assign(assigns, :decisions, Map.get(assigns.item, :decisions, []))

    ~H"""
    <%!-- On phones a row that can be put aside slides left under the finger
         (the inbox's `.SwipeRows`) and shows the action that does it. --%>
    <article
      id={"item-#{@item.id}"}
      data-swipe={@item.tier != :urgent}
      class={[
        "group flex items-center gap-4 border-b border-grey-100 px-5 py-4 last:border-b-0 max-md:relative max-md:flex-wrap max-md:items-start max-md:gap-3 max-md:px-4 max-md:py-3",
        @item.tier != :urgent && "max-md:touch-pan-y",
        @fresh && "motion-safe:animate-arrive"
      ]}
    >
      <%!-- Level with the text's top, as next to a two-line text, however long it runs. --%>
      <span
        :if={@item.tier == :urgent}
        class={[
          "mt-0.5 flex size-10 shrink-0 items-center justify-center self-start rounded-sm max-md:mt-0",
          icon_styles(@item)
        ]}
      >
        <Lucideicons.render! name={@item.icon} class="size-6" aria-hidden="true" />
      </span>
      <.snooze_menu :if={@item.tier != :urgent} item={@item} today={@today} />
      <%!-- On phones the tile opens the same sheet as the swipe: a dropdown would run under the
           rows below and out of the list. --%>
      <.button
        :if={@item.tier != :urgent}
        id={"item-#{@item.id}-snooze-phone"}
        type="button"
        variant="unstyled"
        aria-label={gettext("Put aside")}
        phx-click={show_snooze_sheet(@item.id)}
        class={[
          "relative z-10 flex size-10 shrink-0 cursor-pointer items-center justify-center self-start rounded-sm md:hidden",
          icon_styles(@item)
        ]}
      >
        <Lucideicons.render! name={@item.icon} class="size-6" aria-hidden="true" />
      </.button>
      <div class="flex min-w-0 flex-1 flex-col gap-1 max-md:gap-0.5">
        <h3 class="text-base/[normal] font-medium text-black max-md:leading-[1.4]">
          <%!-- On phones the whole row opens the item, as the chevron says. --%>
          <.link
            :if={Map.has_key?(@item, :href)}
            kind="unstyled"
            navigate={@item.href}
            class="decoration-from-font underline-offset-auto hover:underline focus-visible:underline max-md:after:absolute max-md:after:inset-0"
          >
            <.item_title item={@item} />
          </.link>
          <.item_title :if={!Map.has_key?(@item, :href)} item={@item} />
        </h3>
        <.meta_line item={@item} />
      </div>
      <div
        :if={Map.has_key?(@item, :amount)}
        class="flex shrink-0 flex-col items-end gap-1 whitespace-nowrap max-md:gap-0.5"
      >
        <p class="text-base/[normal] font-medium text-black max-md:leading-[1.4]">{@item.amount}</p>
        <p class="text-sm/[1.35] text-brick-700 max-md:text-xs/[1.4] max-md:font-medium">
          {ngettext("%{count} day late", "%{count} days late", @item.days_late)}
        </p>
      </div>
      <.figma_icon
        :if={Map.has_key?(@item, :href) and not Map.has_key?(@item, :amount)}
        name="chevron_right"
        class="mt-0.5 size-5 text-black md:hidden"
      />
      <%!-- On phones the actions wrap under the text, as wide as it and 48px tall. --%>
      <div
        :if={@item.tier == :urgent or @decisions != []}
        class="flex shrink-0 flex-wrap items-center gap-2 max-md:relative max-md:z-10 max-md:w-full max-md:flex-nowrap max-md:pr-8 max-md:pl-13"
      >
        <.link
          :if={@item.tier == :urgent}
          kind="button"
          navigate={@item.href}
          size="small"
          variant="special"
          class={phone_action_styles()}
        >
          {@item.action}
        </.link>
        <%!-- Holds the ✕'s place when an item cannot be rejected, so the buttons line up across rows;
        on phones the actions sit right-aligned on their own line, where it would only crowd them. --%>
        <span
          :if={@item.tier != :urgent and length(@decisions) == 1}
          class="w-8 shrink-0 max-md:hidden"
          aria-hidden="true"
        ></span>
        <%= for decision <- Enum.sort_by(@decisions, & &1.show_label?), @item.tier != :urgent do %>
          <.icon_button
            :if={!decision.show_label?}
            id={"item-#{@item.id}-#{decision.action}"}
            label={decision.label}
            variant="tertiary"
            class="w-8 max-md:hidden"
            phx-click={leave(@item.id, "decide_item", %{decision: decision.action})}
          >
            <Lucideicons.render! name={decision.icon} aria-hidden="true" />
          </.icon_button>
          <%!-- On phones the icon-only decision is named, outlined beside the other one. --%>
          <.button
            :if={!decision.show_label?}
            id={"item-#{@item.id}-#{decision.action}-phone"}
            type="button"
            size="small"
            variant="outline"
            class={["md:hidden", phone_action_styles()]}
            phx-click={leave(@item.id, "decide_item", %{decision: decision.action})}
          >
            <Lucideicons.render! name={decision.icon} aria-hidden="true" />{decision.label}
          </.button>
          <.button
            :if={decision.show_label?}
            id={"item-#{@item.id}-#{decision.action}"}
            type="button"
            size="small"
            variant="tertiary"
            class={phone_action_styles()}
            phx-click={leave(@item.id, "decide_item", %{decision: decision.action})}
          >
            <Lucideicons.render! name={decision.icon} aria-hidden="true" />{decision.label}
          </.button>
        <% end %>
      </div>
      <%!-- Figma "Akcja / Odłóż": just past the row's right edge, where the card clips it,
           so it slides in with the row. --%>
      <.button
        :if={@item.tier != :urgent}
        id={"item-#{@item.id}-swipe-action"}
        type="button"
        variant="unstyled"
        data-swipe-action
        tabindex="-1"
        phx-click={show_snooze_sheet(@item.id)}
        class="absolute inset-y-0 left-full flex w-22 cursor-pointer flex-col items-center justify-center gap-1 bg-grey-700 text-xs/[normal] font-medium text-white md:hidden"
      >
        <.figma_icon name="history" class="size-6" />{gettext("Put aside")}
      </.button>
    </article>
    """
  end

  # Figma "Decyzja": on phones the actions share the row equally, as Mobile (48px) buttons.
  defp phone_size_styles, do: ButtonStyles.phone_size_classes()

  defp phone_action_styles, do: [phone_size_styles(), "max-md:min-w-0 max-md:flex-1"]

  attr :item, :map, required: true

  defp item_title(assigns) do
    ~H"""
    {@item.title}<span :if={Map.has_key?(@item, :date_range)}>,
    <span class="whitespace-nowrap">{@item.date_range}</span></span>
    """
  end

  # Hands `event` for the item to the card's SmoothHeight hook
  # (`inbox:leave`): the row dissolves first, then the hook sends the event and
  # the rows under it glide up once the answer takes it off.
  defp leave(id, event, value \\ %{}) do
    JS.dispatch("inbox:leave",
      to: "#item-#{id}",
      detail: %{event: event, value: Map.put(value, :id, id)}
    )
  end

  attr :item, :map, required: true

  # One line under the title that never wraps: the person or counterparty, then
  # the context. Next to an amount the name gives way and the due date stays;
  # elsewhere the context is what ends with an ellipsis.
  defp meta_line(assigns) do
    ~H"""
    <p class="flex min-w-0 gap-x-1.5 text-sm/[1.35] whitespace-nowrap text-grey-600 max-md:block max-md:leading-[1.4] max-md:whitespace-normal">
      <span
        :if={@item.person}
        class={[
          "truncate font-medium text-black max-md:font-normal max-md:whitespace-normal",
          if(Map.has_key?(@item, :amount), do: "min-w-0", else: "max-w-2/3 shrink-0")
        ]}
        title={@item.person}
      >
        {@item.person}
      </span>
      <span :if={@item.person} class="shrink-0" aria-hidden="true">·</span>
      <span class={[
        "max-md:whitespace-normal",
        if(Map.has_key?(@item, :amount), do: "shrink-0", else: "min-w-0 truncate")
      ]}>
        {@item.context}
      </span>
    </p>
    """
  end

  attr :item, :map, required: true
  attr :today, Date, required: true

  # The item's tile puts it aside for the whole company
  # (`Firmowid.Core.InboxSnooze`): while the row is hovered it shows a clock,
  # and hovered itself it darkens a step and names what it does. Each option
  # shows the day the item comes back.
  defp snooze_menu(assigns) do
    ~H"""
    <.menu
      id={"item-#{@item.id}-snooze"}
      label={gettext("Put aside")}
      tooltip={gettext("Put aside")}
      placement="bottom-start"
      panel_class="w-70"
      class="mt-0.5 shrink-0 self-start max-md:hidden"
      trigger_variant="bare"
      trigger_class={["size-10!", icon_styles(@item), tile_hover_styles(@item)]}
    >
      <:trigger>
        <span class="relative size-6" aria-hidden="true">
          <Lucideicons.render!
            name={@item.icon}
            class="size-6 transition-opacity duration-100 group-hover:opacity-0 group-has-aria-expanded:opacity-0"
          />
          <Lucideicons.history class="absolute inset-0 size-6 opacity-0 transition-opacity duration-100 group-hover:opacity-100 group-has-aria-expanded:opacity-100" />
        </span>
      </:trigger>
      <p
        class="px-3 pt-2 pb-1 text-caps-sm/[normal] font-medium text-grey-600 uppercase"
        aria-hidden="true"
      >
        {gettext("Put aside until")}
      </p>
      <.menu_item
        :for={{days, label} <- snooze_options()}
        class="justify-between gap-4"
        phx-click={leave(@item.id, "snooze_item", %{days: to_string(days)})}
      >
        <span class="text-black">{label}</span>
        <span class="text-grey-600">{Queue.short_date(Date.add(@today, days), @today)}</span>
      </.menu_item>
      <div class="pt-1 pb-0.75" role="separator">
        <div class="h-px bg-grey-200"></div>
      </div>
      <.menu_item
        tone="danger"
        class="flex-col items-start gap-y-1 py-2"
        phx-click={leave(@item.id, "snooze_item")}
      >
        <span>{gettext("Remove notification")}</span>
        <span class="text-sm/[1.35] whitespace-normal text-grey-600">{hide_for_good_note(@item)}</span>
      </.menu_item>
    </.menu>
    """
  end

  defp snooze_options, do: [{7, gettext("In a week")}, {30, gettext("In a month")}, {90, gettext("In 3 months")}]

  defp hide_for_good_note(%{days_late: _}),
    do: gettext("It will not come back to the inbox, even if the invoice is still overdue.")

  defp hide_for_good_note(_item), do: gettext("It will not come back to the inbox.")

  @doc """
  The page title: how many items wait and, after a slash, how many the company
  put aside until a day. Both are buttons that switch the page between the
  queue and the list of items put aside (`put_aside_list/1`): the one shown is
  dark, the other grey, and "put aside" unfolds after its count while the clock
  turns back.
  """
  attr :greeting, :string, required: true
  attr :put_aside, :integer, required: true, doc: "items put aside until a day"
  attr :showing_put_aside, :boolean, required: true

  def title(assigns) do
    ~H"""
    <%!-- On phones the title stays on one line beside its buttons: a long one ("Wszystko
         załatwione") shrinks from 40px until it fits (`.FitTitle`),
         centred in the 52px line a 40px title takes, as in Figma. --%>
    <h1
      id="inbox-title"
      phx-hook=".FitTitle"
      class="flex flex-wrap items-baseline gap-x-1 text-3xl/[normal] font-bold max-md:h-13 max-md:min-w-0 max-md:flex-nowrap max-md:items-center max-md:whitespace-nowrap"
    >
      <.button
        id="inbox-title-queue"
        type="button"
        variant="unstyled"
        phx-click="show_queue"
        disabled={!@showing_put_aside}
        class={
          [
            "transition-colors duration-300 ease-out disabled:cursor-default motion-reduce:transition-none",
            # On phones the put-aside button shows which list is open, so the title stays black.
            if(@showing_put_aside,
              do: "cursor-pointer text-grey-400 hover:text-grey-500 max-md:text-black",
              else: "text-black"
            )
          ]
        }
      >
        {@greeting}
      </.button>
      <.button
        :if={@put_aside > 0}
        id="inbox-put-aside-toggle"
        type="button"
        variant="unstyled"
        phx-click={if @showing_put_aside, do: "show_queue", else: "show_put_aside"}
        aria-pressed={to_string(@showing_put_aside)}
        aria-label={
          ngettext("Show %{count} item put aside", "Show %{count} items put aside", @put_aside)
        }
        class={[
          "flex cursor-pointer items-center transition-colors duration-300 ease-out motion-reduce:transition-none max-md:hidden",
          if(@showing_put_aside, do: "text-grey-900", else: "text-grey-400 hover:text-grey-500")
        ]}
      >
        <span class="pr-2.5 text-grey-400" aria-hidden="true">/</span>
        <span class="tabular-nums">{@put_aside}</span>
        <%!-- Unfolds from no width; the grid track eases between 0fr and 1fr. --%>
        <span class={[
          "grid transition-[grid-template-columns,opacity] duration-300 ease-out motion-reduce:transition-none",
          if(@showing_put_aside, do: "grid-cols-[1fr] opacity-100", else: "grid-cols-[0fr] opacity-0")
        ]}>
          <span class="overflow-hidden">
            <span class="block pr-0.5 pl-2.5 whitespace-nowrap">
              {ngettext("put aside", "put aside", @put_aside)}
            </span>
          </span>
        </span>
        <Lucideicons.history
          class={[
            "ml-1 size-11 shrink-0 self-center transition-transform duration-500 ease-out motion-reduce:transition-none",
            @showing_put_aside && "-rotate-360"
          ]}
          aria-hidden="true"
        />
      </.button>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".FitTitle">
        // Below the md breakpoint, scales the title's font down so its text
        // fits the width left beside the buttons; on wider screens it wraps.
        const PHONE = "(max-width: 47.99rem)"

        export default {
          mounted() {
            this.onResize = () => this.fit()
            window.addEventListener("resize", this.onResize)
            this.fit()
            // Text set in a font that is still loading measures narrower.
            document.fonts.ready.then(() => this.fit())
          },
          updated() { this.fit() },
          destroyed() { window.removeEventListener("resize", this.onResize) },
          fit() {
            this.el.style.removeProperty("font-size")
            if (!window.matchMedia(PHONE).matches) return
            const overflow = this.el.scrollWidth / this.el.clientWidth
            if (overflow <= 1) return
            const size = parseFloat(getComputedStyle(this.el).fontSize)
            this.el.style.fontSize = `${Math.floor((size / overflow) * 10) / 10}px`
          }
        }
      </script>
    </h1>
    """
  end

  @doc """
  On phones, in place of the title's "/ 2": the clock of the items put aside
  with their count on it, a 48px button that switches between the queue and their list.
  """
  attr :count, :integer, required: true
  attr :showing_put_aside, :boolean, required: true

  def put_aside_button(assigns) do
    ~H"""
    <.button
      id="inbox-put-aside-phone"
      type="button"
      variant="unstyled"
      phx-click={if @showing_put_aside, do: "show_queue", else: "show_put_aside"}
      aria-pressed={to_string(@showing_put_aside)}
      aria-label={ngettext("Show %{count} item put aside", "Show %{count} items put aside", @count)}
      class="relative flex size-12 shrink-0 cursor-pointer items-center justify-center rounded-sm text-black aria-pressed:bg-grey-200 md:hidden"
    >
      <.figma_icon name="history" class="size-6" />
      <span
        class="absolute top-1.5 left-6.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-grey-200 px-1 text-caps-sm/none font-medium text-grey-700 tabular-nums"
        aria-hidden="true"
      >
        {@count}
      </span>
    </.button>
    """
  end

  @doc """
  The inbox search folded into a 32px magnifier button. Focused or holding a
  query it unfolds to 240px; emptied and left, it folds back.
  """
  attr :id, :string, required: true
  attr :query, :string, required: true
  attr :placeholder, :string, required: true

  def folding_search(assigns) do
    ~H"""
    <form
      id={"#{@id}-form"}
      phx-change="search"
      phx-submit="search"
      phx-hook=".FoldingSearch"
      class={
        [
          # On phones a 48px magnifier that, open, covers the whole header band in the page's grey,
          # edge to edge, with a way out on the right.
          "group/search relative w-8 min-w-8 shrink transition-[width] duration-200 ease-out focus-within:w-60 has-[input:not(:placeholder-shown)]:w-60 motion-reduce:transition-none max-md:size-12 max-md:min-w-12 max-md:focus-within:absolute max-md:focus-within:inset-y-0 max-md:focus-within:-right-1 max-md:focus-within:-left-4 max-md:focus-within:z-10 max-md:focus-within:flex max-md:focus-within:size-auto max-md:focus-within:items-end max-md:focus-within:gap-1 max-md:focus-within:bg-grey-100 max-md:focus-within:pr-1 max-md:focus-within:pl-4 max-md:has-[input:not(:placeholder-shown)]:absolute max-md:has-[input:not(:placeholder-shown)]:inset-y-0 max-md:has-[input:not(:placeholder-shown)]:-right-1 max-md:has-[input:not(:placeholder-shown)]:-left-4 max-md:has-[input:not(:placeholder-shown)]:z-10 max-md:has-[input:not(:placeholder-shown)]:flex max-md:has-[input:not(:placeholder-shown)]:size-auto max-md:has-[input:not(:placeholder-shown)]:items-end max-md:has-[input:not(:placeholder-shown)]:gap-1 max-md:has-[input:not(:placeholder-shown)]:bg-grey-100 max-md:has-[input:not(:placeholder-shown)]:pr-1 max-md:has-[input:not(:placeholder-shown)]:pl-4"
        ]
      }
    >
      <div class="relative w-full max-md:min-w-0 max-md:flex-1">
        <FirmowidWeb.DesignSystem.Components.Fields.search_icon class="pointer-events-none absolute top-1/2 left-2 size-4 -translate-y-1/2 text-grey-900 transition-all duration-200 ease-out group-focus-within/search:left-1.5 group-focus-within/search:size-5 group-focus-within/search:text-grey-500 group-has-[input:not(:placeholder-shown)]/search:left-1.5 group-has-[input:not(:placeholder-shown)]/search:size-5 group-has-[input:not(:placeholder-shown)]/search:text-grey-500 motion-reduce:transition-none max-md:hidden" />
        <%!-- On phones the Figma set's magnifier, 24px, a step smaller and lighter once open. --%>
        <.figma_icon
          name="search"
          class="pointer-events-none absolute top-1/2 left-3 size-6 -translate-y-1/2 text-grey-900 transition-all duration-200 ease-out group-focus-within/search:size-5 group-focus-within/search:text-grey-500 group-has-[input:not(:placeholder-shown)]/search:size-5 group-has-[input:not(:placeholder-shown)]/search:text-grey-500 motion-reduce:transition-none md:hidden"
        />
        <input
          id={@id}
          type="search"
          name="q"
          value={@query}
          placeholder={@placeholder}
          aria-label={@placeholder}
          autocomplete="off"
          phx-debounce="200"
          class="h-8 w-full cursor-pointer rounded-sm border border-transparent bg-grey-200 px-0 text-sm text-grey-700 transition-colors duration-200 not-placeholder-shown:cursor-text not-placeholder-shown:bg-grey-100 not-placeholder-shown:pr-1 not-placeholder-shown:pl-8.5 placeholder:text-transparent focus:cursor-text focus:border-teal-300 focus:bg-grey-100 focus:pr-1 focus:pl-8.5 focus:shadow-[inset_0_0_0_1px_var(--color-teal-300)] focus:ring-0 focus:outline-none focus:placeholder:text-grey-400 max-md:h-12 max-md:text-base max-md:not-placeholder-shown:bg-white max-md:not-placeholder-shown:pl-10 max-md:focus:bg-white max-md:focus:pl-10 [&::-webkit-search-cancel-button]:hidden [&:not(:focus):not(:placeholder-shown)]:border-grey-200 max-md:[&:placeholder-shown:not(:focus)]:bg-transparent [&:placeholder-shown:not(:focus):hover]:bg-grey-300"
        />
      </div>
      <%!-- Phones only: clears the search and folds it back to the magnifier. --%>
      <.button
        type="button"
        variant="unstyled"
        data-search-close
        aria-label={gettext("Close")}
        class="hidden size-12 shrink-0 cursor-pointer items-center justify-center rounded-sm text-black max-md:group-focus-within/search:flex max-md:group-has-[input:not(:placeholder-shown)]/search:flex"
      >
        <.figma_icon name="close" class="size-6" />
      </.button>
    </form>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".FoldingSearch">
      // The close button clears the query, telling the server, and gives up the focus, which folds the
      // field. Pressing it must not take the focus first: the field would fold before the click lands.
      export default {
        mounted() {
          const input = this.el.querySelector("input")
          const close = () => {
            if (input.value !== "") {
              input.value = ""
              input.dispatchEvent(new Event("input", {bubbles: true}))
            }
            input.blur()
          }
          this.el.addEventListener("pointerdown", (e) => {
            if (e.target.closest("[data-search-close]")) e.preventDefault()
          })
          this.el.addEventListener("click", (e) => {
            if (e.target.closest("[data-search-close]")) close()
          })
          input.addEventListener("keydown", (e) => {
            if (e.key === "Escape") close()
          })
        }
      }
    </script>
    """
  end

  @doc """
  Items the company put aside until a day, in place of the queue: each says
  when it comes back and can be brought back right away or removed for good.
  """
  attr :entries, :list,
    required: true,
    doc: "`{item, snooze}` pairs from `Queue.split_put_aside/2` that come back on their own"

  attr :today, Date, required: true
  attr :timezone, :string, required: true
  attr :class, :any, default: nil

  def put_aside_list(assigns) do
    ~H"""
    <section id="inbox-put-aside" class={["flex flex-col gap-3", @class]}>
      <div class="flex items-baseline gap-2">
        <h2 class="text-caps-sm/none font-medium text-grey-900 uppercase">
          {pgettext("inbox section", "Put aside")}
        </h2>
        <span class="flex h-4.5 min-w-4.5 shrink-0 items-center justify-center rounded-full bg-grey-200 px-1.5 text-caps-sm font-semibold text-grey-700 tabular-nums">
          {length(@entries)}
        </span>
        <p class="truncate text-sm/[1.35] text-grey-600 max-md:hidden">
          {gettext("They will come back to the inbox on their own, on the chosen day.")}
        </p>
      </div>
      <%!-- On phones edge to edge, as the queue's lists. --%>
      <ul class="overflow-hidden rounded-sm bg-white max-md:-mx-4 max-md:rounded-none max-md:border-y max-md:border-grey-200">
        <li
          :for={{item, snooze} <- @entries}
          id={"put-aside-#{item.id}"}
          class="flex items-center gap-4 border-b border-grey-100 px-5 py-4 last:border-b-0 max-md:flex-wrap max-md:items-start max-md:gap-3 max-md:px-4 max-md:py-3"
        >
          <span class={[
            "flex size-10 shrink-0 items-center justify-center rounded-sm",
            icon_styles(item)
          ]}>
            <Lucideicons.render! name={item.icon} class="size-6" aria-hidden="true" />
          </span>
          <div class="flex min-w-0 flex-1 flex-col gap-1 max-md:basis-[calc(100%-3.25rem)] max-md:gap-0.5">
            <p class="truncate text-base/[normal] font-medium text-black max-md:leading-[1.4] max-md:whitespace-normal">
              {item.title}<span :if={Map.has_key?(item, :date_range)}>, {item.date_range}</span>
            </p>
            <.meta_line item={Map.update!(item, :context, &(Map.get(item, :amount) || &1))} />
          </div>
          <p class="shrink-0 text-sm/[1.35] whitespace-nowrap text-grey-600 max-md:-mt-2.5 max-md:basis-full max-md:pl-13 max-md:leading-[1.4]">
            {gettext("comes back %{date}",
              date:
                snooze.until
                |> DateTime.shift_zone!(@timezone)
                |> DateTime.to_date()
                |> Queue.short_date(@today)
            )}
          </p>
          <div class="flex shrink-0 items-center gap-2 max-md:w-full max-md:pl-13">
            <.icon_button
              id={"put-aside-#{item.id}-remove"}
              label={gettext("Remove notification")}
              variant="destructive"
              class={["w-8 max-md:w-12", phone_size_styles()]}
              phx-click="remove_item"
              phx-value-id={item.id}
            >
              <Lucideicons.trash_2 aria-hidden="true" />
            </.icon_button>
            <.button
              id={"put-aside-#{item.id}-restore"}
              type="button"
              size="small"
              variant="tertiary"
              class={phone_action_styles()}
              phx-click="restore_item"
              phx-value-id={item.id}
            >
              {gettext("Bring back")}
            </.button>
          </div>
        </li>
      </ul>
    </section>
    """
  end

  defp icon_styles(%{tier: :urgent}), do: "bg-brick-200 text-brick-700"
  defp icon_styles(%{tier: :info}), do: "bg-teal-200 text-teal-700"
  defp icon_styles(%{tier: :books, side: :cost}), do: "bg-rust-200 text-rust-700"
  defp icon_styles(%{tier: :books, side: :sales}), do: "bg-teal-200 text-teal-700"
  defp icon_styles(_item), do: "bg-grey-100 text-grey-900"

  # A tile that puts its item aside darkens a step while its row is hovered
  # and another under the pointer, keeping the colour of its ledger side.
  defp tile_hover_styles(%{tier: :info}), do: tile_hover_styles("teal")
  defp tile_hover_styles(%{tier: :books, side: :cost}), do: tile_hover_styles("rust")
  defp tile_hover_styles(%{tier: :books, side: :sales}), do: tile_hover_styles("teal")

  defp tile_hover_styles(%{}), do: "group-hover:bg-grey-200 hover:bg-grey-300! aria-expanded:bg-grey-300!"

  defp tile_hover_styles("teal"), do: "group-hover:bg-teal-300 hover:bg-teal-400! aria-expanded:bg-teal-400!"

  defp tile_hover_styles("rust"), do: "group-hover:bg-rust-300 hover:bg-rust-400! aria-expanded:bg-rust-400!"

  @doc """
  On phones, the ways to put an item aside in a sheet from the bottom (Figma
  "Bottom sheet / Odłóż sprawę"), opened by the action its row shows when
  swiped. The same options as the tile's menu (`snooze_menu/1`).
  """
  attr :item, :map, required: true
  attr :today, Date, required: true

  def snooze_sheet(assigns) do
    ~H"""
    <div
      id={"item-#{@item.id}-sheet"}
      class="fixed inset-0 z-50 hidden md:hidden"
      phx-window-keydown={cancel_snooze_sheet(@item.id)}
      phx-key="escape"
    >
      <div
        id={"item-#{@item.id}-sheet-bg"}
        class="absolute inset-0 bg-black/60"
        phx-click={cancel_snooze_sheet(@item.id)}
        aria-hidden="true"
      >
      </div>
      <div
        id={"item-#{@item.id}-sheet-panel"}
        role="dialog"
        aria-modal="true"
        aria-labelledby={"item-#{@item.id}-sheet-title"}
        class="absolute inset-x-0 bottom-0 flex flex-col rounded-t-sm bg-white pt-2 pb-[calc(2rem+env(safe-area-inset-bottom))] after:absolute after:inset-x-0 after:top-full after:h-[50vh] after:bg-white"
      >
        <div class="flex justify-center pb-2" aria-hidden="true">
          <div class="h-1 w-8 rounded-[2px] bg-grey-300"></div>
        </div>
        <div class="flex flex-col gap-0.5 px-4 pt-2 pb-4 leading-[1.4]">
          <h2 id={"item-#{@item.id}-sheet-title"} class="text-h5 font-medium text-grey-900">
            {gettext("Put the item aside")}
          </h2>
          <p class="truncate text-sm text-grey-600">
            {@item.title}<span :if={@item.person}> · {@item.person}</span>
          </p>
        </div>
        <p class="px-4 pb-1 text-caps-sm/[1.6] font-medium text-grey-700 uppercase" aria-hidden="true">
          {gettext("Put aside until")}
        </p>
        <.button
          :for={{days, label} <- snooze_options()}
          type="button"
          variant="unstyled"
          phx-click={
            leave(@item.id, "snooze_item", %{days: to_string(days)}) |> hide_snooze_sheet(@item.id)
          }
          class="flex h-12 cursor-pointer items-center gap-3 border-t border-grey-100 px-4 text-left active:bg-grey-50"
        >
          <span class="min-w-0 flex-1 text-base/[normal] text-grey-900">{label}</span>
          <span class="shrink-0 text-sm/[normal] whitespace-nowrap text-grey-600">
            {Queue.short_date(Date.add(@today, days), @today)}
          </span>
        </.button>
        <.button
          type="button"
          variant="unstyled"
          phx-click={leave(@item.id, "snooze_item") |> hide_snooze_sheet(@item.id)}
          class="flex cursor-pointer flex-col items-start gap-0.5 border-t border-grey-100 px-4 py-3 text-left leading-[1.4] active:bg-grey-50"
        >
          <span class="text-base font-medium text-brick-700">{gettext("Remove notification")}</span>
          <span class="text-sm text-grey-600">{hide_for_good_note(@item)}</span>
        </.button>
      </div>
    </div>
    """
  end

  defp show_snooze_sheet(id) do
    [to: "#item-#{id}-sheet"]
    |> JS.show()
    |> JS.show(
      to: "#item-#{id}-sheet-bg",
      time: 250,
      transition: {"transition-opacity ease-out duration-250", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "#item-#{id}-sheet-panel",
      time: 300,
      display: "flex",
      transition:
        {"transition-transform ease-[cubic-bezier(0.23,1,0.32,1)] duration-300 motion-reduce:transition-none",
         "translate-y-full", "translate-y-0"}
    )
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "#item-#{id}-sheet-panel")
  end

  # Closes the sheet; the row that was swiped to open it leaves with the choice.
  defp hide_snooze_sheet(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "#item-#{id}-sheet-bg",
      time: 200,
      transition: {"transition-opacity ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "#item-#{id}-sheet-panel",
      time: 200,
      transition:
        {"transition-transform ease-in duration-200 motion-reduce:transition-none", "translate-y-0", "translate-y-full"}
    )
    |> JS.hide(to: "#item-#{id}-sheet", time: 200, transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
  end

  # Closed without a choice, the swiped row slides back.
  defp cancel_snooze_sheet(id) do
    id |> hide_snooze_sheet() |> JS.dispatch("inbox:close-swipe", to: "#item-#{id}")
  end

  @doc "Header of a queue group: its name, how many items it has and why it matters."
  attr :tier, :atom, required: true
  attr :count, :integer, required: true

  def tier_header(assigns) do
    ~H"""
    <div class="flex items-baseline gap-2 max-md:flex-wrap max-md:items-center max-md:gap-y-0.5">
      <h2 class={[
        "text-caps-sm/none font-medium uppercase max-md:leading-[1.6]",
        header_styles(@tier)
      ]}>
        {Queue.tier_label(@tier)}
      </h2>
      <span class={[
        "flex size-4.5 shrink-0 items-center justify-center rounded-full text-caps-sm font-semibold tabular-nums max-md:font-medium",
        badge_styles(@tier)
      ]}>
        {@count}
      </span>
      <%!-- On phones the hint takes a line of its own under the name; the team's
           requests go without one, as in Figma "DO AKCEPTACJI". --%>
      <p class={[
        "truncate text-sm/[1.35] text-grey-600 max-md:w-full max-md:leading-[normal] max-md:whitespace-normal",
        @tier == :people && "max-md:hidden"
      ]}>
        {Queue.tier_hint(@tier)}
      </p>
    </div>
    """
  end

  # Urgent groups stand out in brick; the rare KSeF sync group in calm teal.
  defp header_styles(:urgent), do: "text-brick-700"
  defp header_styles(:info), do: "text-teal-700"
  defp header_styles(_tier), do: "text-grey-900 max-md:text-grey-700"

  defp badge_styles(:urgent), do: "bg-brick-200 text-brick-700"
  defp badge_styles(:info), do: "bg-teal-200 text-teal-700"
  defp badge_styles(_tier), do: "bg-grey-200 text-grey-700"

  @doc "Shown in place of the queue when nothing waits."
  attr :class, :any, default: nil

  def all_done(assigns) do
    ~H"""
    <%!-- On phones (Figma "Pusta skrzynka") a 222px card, its content centred: the Figma set's check,
         16px above two 20px lines, 2px apart, the first grey-900. --%>
    <.empty_state
      size="small"
      title={gettext("Nothing is waiting for your decision.")}
      class={[
        "max-md:h-55.5 max-md:flex-none max-md:justify-center max-md:gap-4 max-md:px-6 max-md:py-10 max-md:**:leading-5 max-md:[&>div:nth-child(2)>p]:text-grey-900",
        @class
      ]}
    >
      <:icon>
        <Lucideicons.circle_check_big class="text-moss-700 max-md:hidden" aria-hidden="true" />
        <.figma_icon name="circle_check" class="size-6 text-grey-900 md:hidden" />
      </:icon>
      {gettext("New items will show up here on their own.")}
    </.empty_state>
    """
  end

  @doc """
  The actions the organization does most often, as small outlined buttons
  with an icon and the action's name. A button opens its page; the upload
  button opens the file picker and sends the chosen files at once.
  """
  attr :shortcuts, :list, required: true, doc: "from `FirmowidWeb.Inbox.Utilities.Shortcuts`"

  attr :upload, :any,
    required: true,
    doc: "the cost invoice upload, or nil for a member who may not add them"

  attr :uploading, :integer, default: 0, doc: "files of the upload still being sent"
  attr :processing, :integer, default: 0, doc: "cost invoice files still being read"

  def shortcuts(assigns) do
    ~H"""
    <section id="inbox-shortcuts" class="flex flex-col gap-3 max-md:gap-2">
      <div class="flex items-baseline gap-3">
        <h2 class="text-caps-sm/none font-medium text-grey-900 uppercase max-md:leading-[1.6] max-md:text-grey-700">
          {gettext("Shortcuts")}
        </h2>
        <p class="truncate text-sm/[1.35] text-grey-600 max-md:hidden">
          {gettext("What your company does most often.")}
        </p>
      </div>
      <%!-- On phones one row that scrolls sideways, from edge to edge. --%>
      <ul class="flex flex-wrap gap-2 max-md:-mx-4 max-md:scrollbar-none max-md:flex-nowrap max-md:overflow-x-auto max-md:px-4">
        <li :for={shortcut <- @shortcuts} class="shrink-0">
          <form
            :if={shortcut.target == :upload}
            id="inbox-upload-form"
            phx-change="upload"
            phx-submit="upload"
          >
            <.button
              as="label"
              id={"inbox-shortcut-#{shortcut.id}"}
              size="small"
              variant="outline"
              class={[
                "relative has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-(--focus-ring)",
                phone_size_styles()
              ]}
            >
              <.live_file_input upload={@upload} class="sr-only" />
              <Lucideicons.render! name={shortcut.icon} aria-hidden="true" />{shortcut.label}
              <CostInvoiceUpload.processing_badge
                id="inbox-upload-count-indicator"
                uploading={@uploading}
                processing={@processing}
              />
            </.button>
          </form>
          <.link
            :if={shortcut.target != :upload}
            kind="button"
            id={"inbox-shortcut-#{shortcut.id}"}
            navigate={elem(shortcut.target, 1)}
            size="small"
            variant="outline"
            class={phone_size_styles()}
          >
            <Lucideicons.render! name={shortcut.icon} aria-hidden="true" />{shortcut.label}
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  @doc """
  The member's session: the running one with a stop button and where it is
  worked from, or the last one to continue with a start button. Without any
  session yet, the way to Czasośledź. The time counts seconds live, in a
  lighter shade.

  The page renders it twice: large under the queue and compact for the side
  column. The `.SessionPlacement` hook of the inbox shows the compact one when
  the large one would not fit on the first screen.
  """
  attr :session, :any, required: true, doc: "the running `Firmowid.Timetracker.Session` or nil"

  attr :last_session, :any,
    required: true,
    doc: "the most recent `Firmowid.Timetracker.Session` or nil"

  attr :compact, :boolean, default: false

  def session_panel(assigns) do
    assigns =
      assign(
        assigns,
        :id,
        if(assigns.compact, do: "inbox-session-compact", else: "inbox-session")
      )

    ~H"""
    <section
      id={@id}
      class={[
        "relative flex-col overflow-hidden rounded-sm bg-white",
        if(@compact,
          do: "hidden gap-8 p-5 group-data-compact-session/columns:flex",
          else:
            "flex min-h-65 justify-between gap-5 p-6 group-data-compact-session/columns:hidden max-md:p-4"
        )
      ]}
    >
      <img
        :if={!@compact}
        src={~p"/images/figurine.png"}
        alt=""
        aria-hidden="true"
        class="pointer-events-none absolute -top-18 right-16.75 w-84.5 max-w-none opacity-5 select-none max-md:-right-24"
      />
      <div class="relative flex items-center justify-between gap-3">
        <h2 class="text-caps-sm font-medium text-grey-600 uppercase">{gettext("Your session")}</h2>
        <%!-- The compact card has no room for the badge; the switch takes its place. --%>
        <.workplace_switch :if={@compact && @session} id={@id} remote={@session.is_remote} />
        <span
          :if={!@compact && @session}
          class="inline-flex items-center gap-1.5 rounded-sm bg-moss-100 px-2 py-0.75 text-sm/[1.35] text-moss-800"
        >
          <span class="size-2 rounded-full bg-moss-700" aria-hidden="true"></span>
          {pgettext("session state", "Running")}
        </span>
      </div>
      <div class="relative flex flex-col gap-1">
        <span
          id={if @session, do: "#{@id}-timer", else: "#{@id}-idle"}
          phx-hook={@session && "Timer"}
          data-start_time={@session && DateTime.to_iso8601(@session.start_datetime)}
          class={[
            "leading-[normal] font-semibold tracking-[-0.02em] tabular-nums",
            if(@compact, do: "text-[2.5rem]", else: "text-[4rem]"),
            if(@session, do: "text-black", else: "text-grey-400")
          ]}
        >
          <span data-timer-main>00:00</span><span data-timer-seconds class="text-grey-200">:00</span>
        </span>
        <p class="truncate text-sm/[1.35] text-grey-600">
          <%= cond do %>
            <% @session -> %>
              {session_summary(@session)}
            <% @last_session -> %>
              {gettext("Continue: %{session}",
                session: session_summary(@last_session, with_workplace: true)
              )}
            <% true -> %>
              {gettext("You are not tracking time now.")}
          <% end %>
        </p>
      </div>
      <div class="relative flex flex-wrap items-center justify-between gap-3">
        <div class={["flex items-center gap-2", @compact && "w-full"]}>
          <.button
            :if={@session}
            type="button"
            size="small"
            variant="special"
            phx-click="stop_session"
          >
            <Lucideicons.square class="size-4" aria-hidden="true" />{pgettext("session", "Stop")}
          </.button>
          <.button
            :if={!@session && @last_session}
            type="button"
            size="small"
            variant="special"
            phx-click="start_session"
          >
            <Lucideicons.play class="size-4" aria-hidden="true" />{pgettext("session", "Start")}
          </.button>
          <.link
            kind="button"
            navigate={~p"/czasosledz"}
            size="small"
            variant="outline"
            class={[@compact && "flex-1"]}
          >
            {gettext("Open Time tracking")}
          </.link>
        </div>
        <.workplace_switch :if={!@compact && @session} id={@id} remote={@session.is_remote} />
      </div>
    </section>
    """
  end

  attr :id, :string, required: true, doc: "id of the session card the switch belongs to"
  attr :remote, :boolean, required: true

  # Where the running session is worked from; switching it saves at once.
  defp workplace_switch(assigns) do
    ~H"""
    <div
      role="group"
      aria-label={gettext("Workplace")}
      class="flex items-center gap-0.5 rounded-sm bg-grey-100 p-0.5"
    >
      <.button
        :for={
          {remote, label} <- [
            {false, pgettext("workplace", "In the office")},
            {true, pgettext("workplace", "Remotely")}
          ]
        }
        id={"#{@id}-#{if remote, do: "remote", else: "office"}"}
        type="button"
        variant="unstyled"
        aria-pressed={to_string(@remote == remote)}
        phx-click="set_workplace"
        phx-value-remote={to_string(remote)}
        class={[
          "flex cursor-pointer items-center gap-1.5 rounded-[3px] px-2.5 py-1 text-sm/[normal] font-medium transition-colors",
          if(@remote == remote,
            do: "bg-white text-black shadow-[0_1px_2px_0_rgb(0_0_0/0.08)]",
            else: "text-grey-600 hover:text-grey-900"
          )
        ]}
      >
        <.presence_dot status={if remote, do: :remote, else: :office} />{label}
      </.button>
    </div>
    """
  end

  # A running session shows its workplace on the switch; the last one names it,
  # since Start continues there.
  defp session_summary(session, opts \\ []) do
    parts = [session.title, session.project.name]

    if opts[:with_workplace],
      do:
        Enum.join(
          parts ++ [status_label(if(session.is_remote, do: :remote, else: :office))],
          " · "
        ),
      else: Enum.join(parts, " · ")
  end

  @doc """
  Who works today: a dot for the office, a ring for remote work, a grey dot
  for the others. The list stops where the queue or the first screen ends,
  whichever is lower; the rest folds into one row that unfolds in place. Until
  the page measures itself, only the people who do not work are folded.
  """
  attr :presence, :list,
    required: true,
    doc: "from `Firmowid.Timetracker.Session.team_presence/2`"

  attr :fit_to, :string,
    default: nil,
    doc: "id of the queue the list may grow along; nil fits the first screen only"

  def office_panel(assigns) do
    {working, absent} = Enum.split_with(assigns.presence, &(&1.status in [:office, :remote]))
    total = length(assigns.presence)

    assigns =
      assign(assigns,
        working: working,
        people: working ++ absent,
        absent_count: length(absent),
        absent_labels:
          Map.new(1..max(length(absent), 1)//1, fn n ->
            {n, ngettext("%{count} person is not working", "%{count} people are not working", n)}
          end),
        more_labels: Map.new(1..max(total, 1)//1, &{&1, gettext("Show %{count} more", count: &1)})
      )

    ~H"""
    <section
      id="inbox-presence"
      phx-hook=".PresenceFit"
      data-fit-to={@fit_to}
      data-absent-labels={JSON.encode!(@absent_labels)}
      data-more-labels={JSON.encode!(@more_labels)}
      data-collapse-label={gettext("Collapse")}
      class="flex flex-col gap-4 rounded-sm bg-white px-5 pt-5 pb-4 max-md:hidden"
    >
      <div class="flex items-center justify-between gap-2 text-grey-600">
        <h2 class="text-caps-sm font-medium uppercase">{gettext("Today at the company")}</h2>
        <span class="text-sm tabular-nums">
          <span aria-hidden="true">{length(@working)}/{length(@presence)}</span>
          <span class="sr-only">
            {gettext("%{working} of %{count} working",
              working: length(@working),
              count: length(@presence)
            )}
          </span>
        </span>
      </div>
      <div class="flex flex-col gap-3">
        <ul id="inbox-presence-people" class="flex flex-col gap-3">
          <li
            :for={person <- @people}
            data-person
            data-absent={person.status not in [:office, :remote]}
            hidden={person.status not in [:office, :remote]}
            class="flex items-center gap-2.5 text-sm"
          >
            <.presence_dot status={person.status} />
            <span class="min-w-0 flex-1 truncate text-black">{person_name(person)}</span>
            <span class="sr-only">{status_label(person.status)}</span>
          </li>
        </ul>
        <.button
          :if={@people != []}
          type="button"
          variant="unstyled"
          id="inbox-presence-fold"
          data-fold
          hidden={@absent_count == 0}
          aria-expanded="false"
          aria-controls="inbox-presence-people"
          class="group flex w-full cursor-pointer items-center gap-2.5 text-left text-sm text-grey-600 hover:text-grey-900"
        >
          <span data-fold-dot class="flex"><.presence_dot status={:away} /></span>
          <span data-fold-label class="min-w-0 flex-1">{Map.get(@absent_labels, @absent_count)}</span>
          <Lucideicons.chevron_down
            class="size-4 shrink-0 transition-transform group-aria-expanded:rotate-180"
            aria-hidden="true"
          />
        </.button>
      </div>
      <div class="h-px bg-grey-100"></div>
      <ul class="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-grey-600" aria-hidden="true">
        <li :for={status <- [:office, :remote, :away]} class="flex items-center gap-1.5">
          <.presence_dot status={status} />{status_label(status)}
        </li>
      </ul>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".PresenceFit">
        // Keeps the panel within the first screen, or along the queue when that
        // is longer, folding the people that do not fit. Stacked under the queue
        // on narrow screens, it folds only the people who do not work.
        const BOTTOM_GAP = 32

        export default {
          mounted() {
            this.expanded = false
            this.onClick = (e) => {
              if (!e.target.closest("[data-fold]")) return
              const rows = [...this.el.querySelectorAll("[data-person]")]
              const shown = new Set(rows.filter((row) => !row.hidden))
              const list = this.el.querySelector("#inbox-presence-people")
              const from = list.getBoundingClientRect().height
              this.expanded = !this.expanded
              this.fit()
              this.animate(list, from, rows.filter((row) => !row.hidden && !shown.has(row)))
            }
            this.onResize = () => this.fit()
            this.el.addEventListener("click", this.onClick)
            window.addEventListener("resize", this.onResize)
            const queue = this.queue()
            if (queue && window.ResizeObserver) {
              this.observer = new ResizeObserver(() => this.fit())
              this.observer.observe(queue)
            }
            this.fit()
            // The inbox holds its columns back until the people are folded:
            // with nothing waiting, the empty state stretches along this panel
            // and would jump once the fold changed its height.
            const columns = this.columns()
            if (columns) this.js().setAttribute(columns, "data-presence-fitted", "")
          },
          updated() { this.fit() },
          destroyed() {
            window.removeEventListener("resize", this.onResize)
            this.observer?.disconnect()
          },
          queue() {
            return this.el.dataset.fitTo && document.getElementById(this.el.dataset.fitTo)
          },
          columns() {
            return this.el.closest("#inbox-columns")
          },
          // The side column's height with the people folded: the inbox's empty
          // state ends there, so unfolding the people does not stretch it.
          rememberFoldedHeight() {
            const columns = this.columns()
            if (!columns) return
            const style = `--presence-folded-height: ${this.el.closest("aside").getBoundingClientRect().height}px`
            if (columns.getAttribute("style") !== style) this.js().setAttribute(columns, "style", style)
          },
          fit() {
            const rows = [...this.el.querySelectorAll("[data-person]")]
            const fold = this.el.querySelector("[data-fold]")
            if (!fold) return
            const working = rows.filter((row) => !row.hasAttribute("data-absent")).length
            // Works out the fold as if folded, then unfolds everyone again when expanded.
            const expanded = this.expanded
            this.expanded = false
            const stacked = this.el.closest("aside").getBoundingClientRect().top >
              this.el.closest("aside").previousElementSibling.getBoundingClientRect().bottom
            this.show(rows, fold, rows.length)
            if (stacked) {
              this.show(rows, fold, working)
            } else {
              const queue = this.queue()
              const queueBottom = queue ? queue.getBoundingClientRect().bottom + window.scrollY : 0
              const limit = Math.max(window.innerHeight, queueBottom) - BOTTOM_GAP
              let visible = rows.length
              while (visible > 0 && this.el.getBoundingClientRect().bottom + window.scrollY > limit) {
                this.show(rows, fold, --visible)
              }
            }
            this.rememberFoldedHeight()
            // With nobody left to fold there is nothing to collapse either.
            this.expanded = expanded && !fold.hidden
            if (this.expanded) {
              rows.forEach((row) => { row.hidden = false })
              fold.setAttribute("aria-expanded", "true")
              fold.querySelector("[data-fold-label]").textContent = this.el.dataset.collapseLabel
              fold.querySelector("[data-fold-dot]").hidden = true
            }
          },
          // Slides the list from its old height and fades the unfolded people in.
          animate(list, from, unfolded) {
            if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
            const to = list.getBoundingClientRect().height
            if (Math.abs(to - from) < 1) return
            const timing = { duration: 250, easing: "cubic-bezier(0.23, 1, 0.32, 1)" }
            list.animate([{ height: `${from}px`, overflow: "hidden" }, { height: `${to}px`, overflow: "hidden" }], timing)
            unfolded.forEach((row) => row.animate([{ opacity: 0 }, { opacity: 1 }], timing))
          },
          // Shows the first `visible` people and names the folded ones on the toggle.
          show(rows, fold, visible) {
            const folded = rows.slice(visible)
            rows.forEach((row, i) => { row.hidden = i >= visible })
            fold.hidden = folded.length === 0
            fold.setAttribute("aria-expanded", "false")
            if (!folded.length) return
            const onlyAbsent = folded.every((row) => row.hasAttribute("data-absent"))
            const labels = JSON.parse(this.el.dataset[onlyAbsent ? "absentLabels" : "moreLabels"])
            fold.querySelector("[data-fold-label]").textContent = labels[folded.length]
            fold.querySelector("[data-fold-dot]").hidden = !onlyAbsent
          }
        }
      </script>
    </section>
    """
  end

  @doc """
  Who works today, on phones in place of `office_panel/1` (Figma "Dziś w
  firmie (karta)"): one row with how many work and a legend of where,
  which unfolds the people in place.
  """
  attr :presence, :list,
    required: true,
    doc: "from `Firmowid.Timetracker.Session.team_presence/2`"

  def office_summary(assigns) do
    counts =
      Enum.frequencies_by(
        assigns.presence,
        &if(&1.status in [:office, :remote], do: &1.status, else: :away)
      )

    {working, absent} = Enum.split_with(assigns.presence, &(&1.status in [:office, :remote]))

    assigns =
      assign(assigns,
        people: working ++ absent,
        working: length(working),
        legend: for(status <- [:office, :remote, :away], counts[status], do: {status, counts[status]})
      )

    ~H"""
    <section id="inbox-presence-summary" class="flex flex-col gap-2 md:hidden">
      <h2 class="text-caps-sm/[1.6] font-medium text-grey-700 uppercase">
        {gettext("Today at the company")}
      </h2>
      <%!-- A card within the page's margins, as the month's tiles above it. --%>
      <div class="overflow-hidden rounded-sm bg-white">
        <.button
          type="button"
          variant="unstyled"
          id="inbox-presence-summary-toggle"
          aria-expanded="false"
          aria-controls="inbox-presence-summary-people"
          phx-click={
            JS.toggle_attribute({"hidden", ""}, to: "#inbox-presence-summary-people")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
          class="group flex w-full cursor-pointer items-center gap-3 px-4 py-3 text-left"
        >
          <span class="flex min-w-0 flex-1 flex-col gap-1">
            <span class="text-base/[1.4] font-medium text-grey-900">
              {ngettext(
                "%{working} of %{count} person working",
                "%{working} of %{count} people working",
                length(@presence),
                working: @working
              )}
            </span>
            <span class="flex flex-wrap gap-x-3 gap-y-1 text-sm/[normal] text-grey-600">
              <span :for={{status, count} <- @legend} class="flex items-center gap-1.5">
                <.presence_dot status={status} />{count} {status_label(status)}
              </span>
            </span>
          </span>
          <.figma_icon
            name="chevron_down"
            class="size-5 text-black transition-transform group-aria-expanded:rotate-180 motion-reduce:transition-none"
          />
        </.button>
        <ul
          id="inbox-presence-summary-people"
          hidden
          class="flex flex-col gap-3 border-t border-grey-100 px-4 py-3"
        >
          <li :for={person <- @people} class="flex items-center gap-2.5 text-sm">
            <.presence_dot status={person.status} />
            <span class="min-w-0 flex-1 truncate text-black">{person_name(person)}</span>
            <span class="sr-only">{status_label(person.status)}</span>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  @doc """
  Who works today, for the member's own layer: the first five working people
  with their avatars and where they work, the rest of them behind "show more",
  and the others folded into one row of avatars that unfolds in place.
  """
  attr :presence, :list,
    required: true,
    doc: "from `Firmowid.Timetracker.Session.team_presence/2`"

  def team_today(assigns) do
    {working, absent} = Enum.split_with(assigns.presence, &(&1.status in [:office, :remote]))
    assigns = assign(assigns, working: working, absent: absent, folded: 5)

    ~H"""
    <section id="inbox-team" class="flex flex-col gap-3.5 rounded-sm bg-white p-5">
      <div class="flex items-center justify-between gap-2">
        <h2 class="text-caps-sm font-medium text-grey-600 uppercase">
          {gettext("Today at the company")}
        </h2>
        <span class="text-sm/[1.35] text-grey-700 tabular-nums">
          {gettext("%{working} of %{count} working",
            working: length(@working),
            count: length(@presence)
          )}
        </span>
      </div>
      <ul :if={@working != []} id="inbox-team-working" class="flex flex-col gap-3">
        <li
          :for={{person, i} <- Enum.with_index(@working)}
          data-more={i >= @folded}
          hidden={i >= @folded}
          class="flex items-center gap-2.5"
        >
          <span class="relative shrink-0">
            <.initials person={person} class="size-8 bg-teal-200 text-teal-800" />
            <span class="absolute -right-0.5 -bottom-0.5 flex rounded-full bg-white p-px">
              <.presence_dot status={person.status} />
            </span>
          </span>
          <span class="min-w-0 flex-1 truncate text-sm/[normal] font-medium text-black">
            {person_name(person)}
          </span>
          <span class="sr-only">{status_label(person.status)}</span>
        </li>
      </ul>
      <.button
        :if={length(@working) > @folded}
        type="button"
        variant="unstyled"
        id="inbox-team-more"
        aria-expanded="false"
        aria-controls="inbox-team-working"
        phx-click={
          JS.toggle_attribute({"hidden", ""}, to: "#inbox-team-working [data-more]")
          |> JS.toggle_attribute({"aria-expanded", "true", "false"})
        }
        class="group flex w-full cursor-pointer items-center justify-between gap-2.5 text-left text-sm/[1.35] text-grey-700 hover:text-grey-900"
      >
        <span class="group-aria-expanded:hidden">
          {ngettext(
            "Show %{count} more person",
            "Show %{count} more people",
            length(@working) - @folded
          )}
        </span>
        <span class="hidden group-aria-expanded:inline">{gettext("Collapse")}</span>
        <Lucideicons.chevron_down
          class="size-4 shrink-0 transition-transform group-aria-expanded:rotate-180"
          aria-hidden="true"
        />
      </.button>
      <div :if={@working != [] and @absent != []} class="h-px bg-grey-100"></div>
      <div :if={@absent != []} class="flex flex-col gap-3">
        <.button
          type="button"
          variant="unstyled"
          id="inbox-team-fold"
          aria-expanded="false"
          aria-controls="inbox-team-absent"
          phx-click={
            JS.toggle_attribute({"hidden", ""}, to: "#inbox-team-absent")
            |> JS.toggle_attribute({"aria-expanded", "true", "false"})
          }
          class="group flex w-full cursor-pointer items-center gap-2.5 text-left text-sm/[1.35] text-grey-700 hover:text-grey-900"
        >
          <span class="isolate flex shrink-0 items-center" aria-hidden="true">
            <.initials
              :for={{person, i} <- Enum.with_index(Enum.take(@absent, 4))}
              person={person}
              class="-mr-1.5 size-7 border-2 border-white bg-grey-200 text-grey-700"
              style={"z-index: #{5 - i}"}
            />
            <span
              :if={length(@absent) > 4}
              class="flex size-7 items-center justify-center rounded-full border-2 border-white bg-grey-100 text-caps-sm font-semibold text-grey-700"
            >
              +{length(@absent) - 4}
            </span>
          </span>
          <span class="min-w-0 flex-1">
            {ngettext(
              "%{count} person is not working",
              "%{count} people are not working",
              length(@absent)
            )}
          </span>
          <Lucideicons.chevron_down
            class="size-4 shrink-0 transition-transform group-aria-expanded:rotate-180"
            aria-hidden="true"
          />
        </.button>
        <ul id="inbox-team-absent" hidden class="flex flex-col gap-3">
          <li :for={person <- @absent} class="flex items-center gap-2.5">
            <.initials person={person} class="size-7 bg-grey-200 text-grey-700" />
            <span class="min-w-0 flex-1 truncate text-sm/[normal] text-grey-700">
              {person_name(person)}
            </span>
            <span class="sr-only">{status_label(person.status)}</span>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  attr :person, :map, required: true
  attr :class, :any, default: nil
  attr :rest, :global

  defp initials(assigns) do
    ~H"""
    <span
      class={[
        "flex shrink-0 items-center justify-center rounded-full text-caps-sm font-semibold uppercase",
        @class
      ]}
      aria-hidden="true"
      {@rest}
    >
      {person_initials(@person)}
    </span>
    """
  end

  defp person_initials(%{name: name}) when is_binary(name) do
    name |> String.split() |> Enum.take(2) |> Enum.map_join(&String.first/1)
  end

  defp person_initials(_person), do: "?"

  attr :status, :atom, required: true

  defp presence_dot(assigns) do
    ~H"""
    <span class={["size-2 shrink-0 rounded-full", presence_dot_styles(@status)]}></span>
    """
  end

  defp presence_dot_styles(:office), do: "bg-moss-700"
  defp presence_dot_styles(:remote), do: "border-[1.5px] border-moss-700"
  defp presence_dot_styles(_absent), do: "bg-grey-300"

  defp person_name(person), do: person.name || pgettext("presence", "Unnamed member")

  defp status_label(:office), do: pgettext("presence", "in the office")
  defp status_label(:remote), do: pgettext("presence", "remotely")
  defp status_label(_absent), do: pgettext("presence", "not working")

  @doc """
  The member's recorded time this month, as one large figure next to the icon
  of the calendar season, in the season's colours.
  """
  attr :duration, :integer, required: true, doc: "session seconds from Session.month_duration/2"
  attr :today, Date, required: true

  def personal_month(assigns) do
    {icon, color, icon_color} = season(assigns.today)
    assigns = assign(assigns, icon: icon, color: color, icon_color: icon_color)

    ~H"""
    <section
      id="inbox-personal-month"
      class="relative flex flex-col gap-2 rounded-sm bg-white p-5 pr-18"
    >
      <h2 class={["text-caps-sm/[normal] font-medium uppercase", @color]}>
        {Firmowid.Cldr.Date.to_string!(@today, format: "LLLL")} · {gettext("Hours worked")}
      </h2>
      <p class="text-lg leading-[normal] font-medium text-black tabular-nums">
        {hours_and_minutes(@duration)}
      </p>
      <Lucideicons.render!
        name={@icon}
        class={["absolute top-1/2 right-5 size-10 -translate-y-1/2 stroke-[0.9]", @icon_color]}
        aria-hidden="true"
      />
    </section>
    """
  end

  # Calendar seasons as counted in Poland: spring from 21 March, summer from
  # 22 June, autumn from 23 September, winter from 22 December.
  defp season(%Date{month: month, day: day}) do
    case {month, day} do
      day_of_year when day_of_year >= {12, 22} or day_of_year < {3, 21} ->
        {"snowflake", "text-teal-700", "text-teal-700"}

      day_of_year when day_of_year < {6, 22} ->
        {"sprout", "text-moss-700", "text-moss-700"}

      day_of_year when day_of_year < {9, 23} ->
        {"sun", "text-rust-700", "text-rust-500"}

      _autumn ->
        {"leaf", "text-rust-700", "text-rust-700"}
    end
  end

  # Whole hours read better without "0 min".
  defp hours_and_minutes(seconds) do
    case {div(seconds, 3600), rem(div(seconds, 60), 60)} do
      {hours, 0} -> pgettext("duration", "%{hours} h", hours: hours)
      {hours, minutes} -> gettext("%{hours} h %{minutes} min", hours: hours, minutes: minutes)
    end
  end

  @doc "The month in numbers as quiet label and value rows, for a side column."
  attr :month, :list, required: true

  def month_list(assigns) do
    ~H"""
    <%!-- On phones (Figma "Ten miesiąc") each number is a tile of its own, two to a row. --%>
    <section class="flex flex-col gap-2.5 rounded-sm bg-white p-5 max-md:gap-2 max-md:rounded-none max-md:bg-transparent max-md:p-0">
      <h2 class="text-caps-sm font-medium text-grey-600 uppercase max-md:leading-[1.6] max-md:text-grey-700">
        {gettext("This month")}
      </h2>
      <dl class="flex flex-col gap-2.5 max-md:grid max-md:grid-cols-2 max-md:gap-2">
        <div
          :for={kpi <- @month}
          class="flex items-baseline justify-between gap-3 text-sm max-md:min-w-0 max-md:flex-col max-md:items-start max-md:justify-start max-md:gap-1 max-md:rounded-sm max-md:bg-white max-md:px-4 max-md:py-3"
        >
          <dt class="truncate text-grey-700 max-md:max-w-full max-md:leading-[normal] max-md:text-grey-600">
            {kpi.label}
          </dt>
          <dd class={[
            "shrink-0 font-medium tabular-nums max-md:text-lg/[1.4] max-md:font-semibold",
            if(kpi.side == :sales, do: "text-teal-700", else: "text-rust-700")
          ]}>
            {kpi.value}
          </dd>
        </div>
      </dl>
    </section>
    """
  end
end
