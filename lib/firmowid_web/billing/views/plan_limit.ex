defmodule FirmowidWeb.Billing.Views.PlanLimit do
  @moduledoc """
  The choice admins make when their company uses more than its plan includes:
  they tick what stays switched on within the current plan (see
  `Firmowid.Billing.PlanLimits`), or buy the cheapest plan that fits with a
  card saved at Tpay (see `Firmowid.Billing.Subscription`). Tpay brings them
  back to `CardReturn`. A company that already pays for a cheaper plan switches
  to it at once instead, paying the price difference with the saved card, once
  this month's payment has gone through.

  A page of its own, without the app navigation. From the decision day every
  page leads admins here (see `RequireOrganization`); before it, their inbox
  links here. Without a pending decision it leads into the app.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Organization.Components.OnboardingHeader
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Billing
  alias Firmowid.Billing.Month
  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.PlanLimits
  alias Firmowid.Core
  alias FirmowidUI.Components.Inputs
  alias FirmowidWeb.Billing.Utilities.Navigation
  alias FirmowidWeb.Billing.Utilities.Worksheet
  alias FirmowidWeb.Infrastructure.UserAuth
  alias FirmowidWeb.Settings.Utilities.Navigation, as: SettingsNavigation

  on_mount {FirmowidWeb.Infrastructure.Hooks.RequireAdmin, :default}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex w-full max-w-7xl flex-col gap-4 px-4 pb-8 sm:px-8 lg:px-20 lg:pb-10">
      <.onboarding_header exit_path={@exit_path} />
      <div class="mx-auto w-full max-w-2xl">
        <h1 class={heading_styles()}>
          {gettext("Your company uses more than the %{plan} plan includes.", plan: @plan_label)}
        </h1>
        <p class={lead_styles()}>
          {gettext(
            "Nothing is deleted. Whatever is switched off comes back once you buy a higher plan."
          )}
          <span :if={@exit_path}>
            {gettext("Everything works until %{date}; from that day a choice is needed.",
              date: format_date(@decision_on)
            )}
          </span>
        </p>

        <section
          id="plan-limit-upgrade"
          class="mt-8 rounded-2xl border border-grey-300 bg-white p-5 sm:p-6"
        >
          <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
            <h2 class="text-xl font-semibold text-grey-900">{Worksheet.plan_label(@fitting_plan)}</h2>
            <p :if={is_nil(@purchase)} class="text-[0.9375rem] font-medium text-grey-900">
              {gettext("%{price} PLN net / month", price: @fitting_rules.monthly_price_pln)}
            </p>
            <p
              :if={@purchase in [:upgrade, :upgrade_unsettled]}
              class="text-[0.9375rem] font-medium text-grey-900 tabular-nums"
            >
              {net_price_text(@fitting_rules, @subscription.billing_period)}
            </p>
          </div>
          <p class="mt-1.5 text-[0.9375rem]/relaxed text-grey-700">
            {gettext("This plan includes everything your company uses now.")}
          </p>
          <dl class="mt-3 divide-y divide-grey-200">
            <div
              :for={kind <- PlanCatalog.limited()}
              class="flex items-baseline justify-between gap-4 py-3"
            >
              <dt class="text-[0.9375rem] text-grey-700">{Worksheet.limited_label(kind)}</dt>
              <dd class="shrink-0 text-right text-[0.9375rem] font-medium text-grey-900">
                {format_limit(@fitting_rules.limits[kind])}
              </dd>
            </div>
          </dl>

          <.form
            :if={@purchase in [:available, :address_missing]}
            for={@period_form}
            id="plan-limit-buy"
            phx-change="period"
            phx-submit="buy"
            class="mt-7"
          >
            <fieldset>
              <legend class="text-sm text-grey-600">{gettext("Billing period")}</legend>
              <label
                :for={period <- [:monthly, :yearly]}
                id={"plan-limit-period-#{period}"}
                class="flex cursor-pointer items-baseline gap-3 py-2"
              >
                <input
                  type="radio"
                  name={@period_form[:billing_period].name}
                  value={period}
                  checked={period == @billing_period}
                  class="size-4 shrink-0 translate-y-0.5 border border-grey-700 text-grey-900 focus:ring-0 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-(--focus-ring)"
                />
                <span class={[
                  "flex-1 text-[0.9375rem]",
                  if(period == @billing_period, do: "text-grey-900", else: "text-grey-700")
                ]}>
                  {period_label(period)}
                </span>
                <span class="shrink-0 text-right text-[0.9375rem] font-medium text-grey-900 tabular-nums">
                  {net_price_text(@fitting_rules, period)}
                </span>
              </label>
            </fieldset>

            <p class="mt-3 text-[0.9375rem]/relaxed text-grey-700">
              {first_charge_text(@fitting_plan, @billing_period, @first_charge_on)}
            </p>

            <%= if @purchase == :available do %>
              <.button
                id="plan-limit-buy-submit"
                type="submit"
                class="mt-5 w-full"
                phx-disable-with={gettext("Opening the card page...")}
              >
                {gettext("Buy the %{plan} plan", plan: Worksheet.plan_label(@fitting_plan))}
              </.button>
              <p class="mt-2 text-sm text-grey-600">
                {if @free_month?,
                  do: gettext("Next you enter the card on Tpay's page. Nothing is charged today."),
                  else:
                    gettext(
                      "Next you enter the card on Tpay's page. The payment follows right after."
                    )}
              </p>
            <% else %>
              <.link
                id="plan-limit-address"
                kind="button"
                variant="primary"
                navigate={SettingsNavigation.canonical_path(:organization)}
                class="mt-5 w-full"
              >
                {gettext("Fill in the company address to buy")}
              </.link>
              <p class="mt-2 text-sm text-grey-600">
                {gettext("The plan's invoice needs it. Then come back here to buy.")}
              </p>
            <% end %>
          </.form>

          <p
            :if={@purchase == :upgrade_unsettled}
            id="plan-limit-switch-plan-waiting"
            class="mt-7 text-[0.9375rem]/relaxed text-grey-700"
          >
            {gettext("You can switch plans once this month's payment goes through.")}
          </p>

          <div :if={@purchase == :upgrade} id="plan-limit-switch-plan" class="mt-7">
            <p class="text-[0.9375rem]/relaxed text-grey-700">
              {upgrade_text(@fitting_plan, @subscription)}
            </p>
            <.button
              id="plan-limit-switch-plan-submit"
              type="button"
              phx-click="upgrade"
              class="mt-5 w-full"
              phx-disable-with={gettext("Switching the plan...")}
            >
              {gettext("Switch to the %{plan} plan", plan: Worksheet.plan_label(@fitting_plan))}
            </.button>
            <p class="mt-2 text-sm text-grey-600">
              {if upgrade_free?(@subscription),
                do: gettext("Nothing is charged today."),
                else: gettext("Charged to the card ending in %{tail}.", tail: @subscription.card_tail)}
            </p>
          </div>
        </section>

        <section id="plan-limit-keep" class="mt-8">
          <h2 class="text-xl font-semibold text-grey-900">
            {gettext("Stay on the %{plan} plan", plan: @plan_label)}
          </h2>
          <p class="mt-1.5 text-[0.9375rem]/relaxed text-grey-700">
            {gettext(
              "Tick what stays switched on. People switched off are archived and cannot sign in, projects are archived, and accounts in banks switched off stop synchronizing. Their history stays."
            )}
          </p>

          <.form for={%{}} id="plan-limit-form" phx-change="select" phx-submit="keep" class="mt-6">
            <fieldset :for={list <- @lists} id={"plan-limit-#{list.kind}"} class="mt-6 first:mt-0">
              <div class="flex items-baseline justify-between gap-4">
                <legend class="text-[1.0625rem] font-medium text-grey-900">
                  {Worksheet.limited_label(list.kind)}
                </legend>
                <p class={[
                  "text-sm tabular-nums",
                  if(selected_count(@selected, list) > list.limit,
                    do: "font-medium text-brick-700",
                    else: "text-grey-600"
                  )
                ]}>
                  {gettext("selected %{selected} of %{limit}",
                    selected: selected_count(@selected, list),
                    limit: list.limit
                  )}
                </p>
              </div>
              <ul class="mt-2 divide-y divide-grey-200 rounded-2xl border border-grey-300 bg-white px-5">
                <li :for={item <- list.items}>
                  <label class={[
                    "flex items-center gap-3 py-3.5",
                    if(disabled?(@selected, @locked, list, item.id),
                      do: "cursor-default",
                      else: "cursor-pointer"
                    )
                  ]}>
                    <input
                      type="checkbox"
                      name={"kept[#{list.kind}][]"}
                      value={item.id}
                      checked={MapSet.member?(@selected[list.kind], item.id)}
                      disabled={disabled?(@selected, @locked, list, item.id)}
                      class="size-4 shrink-0 rounded-[3px] border border-grey-700 text-grey-900 focus:ring-0 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-(--focus-ring) disabled:opacity-40"
                    />
                    <span class={[
                      "min-w-0 flex-1 text-[0.9375rem]",
                      if(MapSet.member?(@selected[list.kind], item.id),
                        do: "text-grey-900",
                        else: "text-grey-600"
                      )
                    ]}>
                      <span class="block truncate">{item_name(list.kind, item)}</span>
                      <span
                        :if={item_detail(list.kind, item)}
                        class="block truncate text-sm text-grey-600"
                      >
                        {item_detail(list.kind, item)}
                      </span>
                    </span>
                    <.badge :if={item.id == @owner_member_id}>{gettext("Owner")}</.badge>
                    <.badge :if={item.id == @own_member_id and item.id != @owner_member_id}>
                      {pgettext("plan limit member", "You")}
                    </.badge>
                  </label>
                </li>
              </ul>
            </fieldset>

            <p class="mt-6 text-[0.9375rem]/relaxed text-grey-700">
              {switch_off_summary(@lists, @selected)}
              <span :if={is_nil(@exit_path)}>
                {gettext(
                  "Without a choice, on %{date} we will switch off the newest items above the limit.",
                  date: format_date(PlanLimits.switch_off_on(@current_org))
                )}
              </span>
            </p>

            <.button
              id="plan-limit-submit"
              type="submit"
              variant="outline"
              class="mt-4 w-full"
              disabled={not fits?(@lists, @selected)}
              phx-disable-with={gettext("Saving...")}
            >
              {gettext("Save and switch off the rest")}
            </.button>
          </.form>
        </section>

        <%!-- While held here, the way to the user's other companies (see `Organization.Controllers.Switch`). --%>
        <.form
          :if={is_nil(@exit_path) and @other_organizations != []}
          for={%{}}
          id="plan-limit-switch"
          action={~p"/organizacja/przelacz"}
          class="mt-10 flex flex-wrap items-baseline gap-x-3 gap-y-1 text-[0.9375rem]/relaxed text-grey-700"
        >
          {gettext("Go to another company:")}
          <.button
            :for={organization <- @other_organizations}
            id={"plan-limit-switch-#{organization.id}"}
            type="submit"
            variant="unstyled"
            name="organizacja"
            value={organization.id}
            class="min-w-0 cursor-pointer truncate text-left text-grey-900 underline underline-offset-4 hover:text-black"
          >
            {organization.display_name}
          </.button>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: user, current_org: org, ash_scope: scope} = socket.assigns
    app_path = UserAuth.signed_in_path_for_user(user, scope.tenant)

    if is_nil(org.plan_limit_decision_on) do
      {:ok, push_navigate(socket, to: app_path)}
    else
      {:ok, mount_choice(socket, app_path)}
    end
  end

  defp mount_choice(socket, app_path) do
    %{current_user: user, current_org: org, ash_scope: scope} = socket.assigns
    usage = PlanLimits.usage(org)
    exceeded = PlanCatalog.exceeded(usage, org.billing_plan)
    limits = PlanCatalog.plan!(org.billing_plan).limits
    switched_on = PlanLimits.switched_on(org, scope)
    fitting_plan = PlanCatalog.fitting_plan(usage)

    owner_member_id = Enum.find_value(switched_on.users, &(&1.user_id == org.owner_id && &1.id))
    # The owner always stays, and a member cannot switch themselves off.
    locked = MapSet.new([owner_member_id, user.member.id])

    lists =
      for kind <- exceeded do
        %{kind: kind, items: switched_on[kind], limit: limits[kind]}
      end

    socket
    |> assign(
      page_title: gettext("Plan limit"),
      # A page of its own, without the app navigation.
      focused: true,
      no_padding: true,
      app_path: app_path,
      # Once the decision is due every page leads back here, so the way out is logging
      # out or another company.
      exit_path: if(not PlanLimits.decision_due?(org), do: app_path),
      other_organizations:
        Enum.filter(
          socket.assigns.organizations,
          &(&1.id != org.id and Core.usable_organization?(user, &1))
        ),
      decision_on: org.plan_limit_decision_on,
      billing_plan: org.billing_plan,
      plan_label: Worksheet.plan_label(org.billing_plan),
      fitting_plan: fitting_plan,
      fitting_rules: PlanCatalog.plan!(fitting_plan),
      owner_member_id: owner_member_id,
      own_member_id: user.member.id,
      locked: locked,
      lists: lists,
      selected: Map.new(lists, &{&1.kind, preselect(&1, locked)}),
      billing_period: :monthly,
      period_form: to_form(%{"billing_period" => "monthly"})
    )
    |> assign_purchase()
  end

  # What the upgrade section offers: nothing without the flag or for a plan granted by hand;
  # a switch to the fitting plan for a company that pays for a cheaper one; otherwise the
  # purchase, which needs the company address for the invoice and starts with the free month
  # while the company has not used it.
  defp assign_purchase(socket) do
    %{current_org: org, ash_scope: scope, fitting_plan: fitting_plan} = socket.assigns

    org = Ash.load!(org, [:plan_granted?, :free_month_available?], scope: scope)

    subscription =
      %{status: :active}
      |> Billing.list_subscriptions!(
        scope: scope,
        load: [
          :current_period_settled?,
          :current_period_free?,
          upgrade_price: %{plan: fitting_plan}
        ]
      )
      |> List.first()

    assign(socket,
      purchase: purchase_offer(org, subscription),
      subscription: subscription,
      free_month?: org.free_month_available?,
      # The month the card is saved is free; without it the card pays at once.
      first_charge_on: if(org.free_month_available?, do: Month.next())
    )
  end

  # The switch waits while the current period's payment is unsettled (see `Subscription` `:upgrade`).
  defp purchase_offer(_organization, %{current_period_settled?: true}), do: :upgrade
  defp purchase_offer(_organization, %{status: :active}), do: :upgrade_unsettled
  defp purchase_offer(%{plan_granted?: true}, nil), do: nil
  defp purchase_offer(%{address: address}, nil) when address in [nil, ""], do: :address_missing
  defp purchase_offer(_organization, nil), do: :available

  @impl true
  def handle_event("period", %{"billing_period" => period}, socket) do
    {:noreply, assign(socket, :billing_period, billing_period(period))}
  end

  def handle_event("buy", %{"billing_period" => period}, socket) do
    %{fitting_plan: plan, ash_scope: scope} = socket.assigns

    if socket.assigns.purchase == :available do
      case Billing.start_subscription(%{plan: plan, billing_period: billing_period(period)},
             scope: scope
           ) do
        {:ok, subscription} ->
          {:noreply, redirect(socket, external: subscription.__metadata__.card_page_url)}

        # A refused purchase, such as a used free month.
        {:error, error} ->
          {:noreply, refused(socket, error)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("upgrade", _params, socket) do
    %{fitting_plan: plan, subscription: subscription, ash_scope: scope} = socket.assigns

    if socket.assigns.purchase == :upgrade do
      case Billing.upgrade_subscription(subscription, plan, scope: scope) do
        {:ok, subscription} -> {:noreply, upgraded(socket, plan, subscription)}
        # A refused upgrade, such as a month whose payment has not gone through.
        {:error, error} -> {:noreply, refused(socket, error)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("select", params, socket) do
    {:noreply, assign(socket, :selected, selected_from(params, socket.assigns))}
  end

  def handle_event("keep", params, socket) do
    %{current_org: org, ash_scope: scope} = socket.assigns
    selected = selected_from(params, socket.assigns)
    kept = Map.new(selected, fn {kind, ids} -> {kind, MapSet.to_list(ids)} end)
    # The plan may have changed since the page opened, such as an upgrade Tpay confirmed late.
    org = Core.get_organization!(org.id, scope: scope)

    if org.billing_plan == socket.assigns.billing_plan do
      keep(socket, org, kept, selected, scope)
    else
      # What was ticked fits the old plan; `keep` would switch off the rest under the new one.
      {:noreply,
       socket
       |> LiveToast.put_toast(
         :info,
         gettext("Your plan has changed. Check what stays switched on again.")
       )
       |> push_navigate(to: Navigation.plan_limit_path())}
    end
  end

  defp keep(socket, org, kept, selected, scope) do
    case PlanLimits.keep(org, kept, scope) do
      {:ok, _organization} ->
        {:noreply,
         socket
         |> LiveToast.put_toast(
           :info,
           gettext("Saved. Whatever was switched off comes back with a higher plan.")
         )
         |> push_navigate(to: socket.assigns.app_path)}

      {:error, :over_limit} ->
        {:noreply,
         socket
         |> assign(:selected, selected)
         |> LiveToast.put_toast(:error, gettext("Tick no more than the plan includes."))}
    end
  end

  # An action refused with a reason the admin can act on; anything else, such as a Tpay failure,
  # raises and reaches Sentry.
  defp refused(socket, %Ash.Error.Invalid{errors: [%{message: message} = error | _rest]}) do
    LiveToast.put_toast(
      socket,
      :error,
      Inputs.translate_error({message, Map.get(error, :vars, [])})
    )
  end

  defp refused(_socket, error), do: raise(error)

  # The subscription as the upgrade left it: on the new plan once paid (or free), still on the
  # old one when the card was declined or Tpay has not decided yet.
  defp upgraded(socket, plan, %{plan: plan}) do
    socket
    |> LiveToast.put_toast(
      :info,
      gettext("You are on the %{plan} plan now.", plan: Worksheet.plan_label(plan))
    )
    |> push_navigate(to: socket.assigns.app_path)
  end

  defp upgraded(socket, _plan, %{__metadata__: %{upgrade_payment: %{status: :failed}}}) do
    LiveToast.put_toast(
      socket,
      :error,
      gettext("The payment did not go through. Your plan has not changed.")
    )
  end

  defp upgraded(socket, _plan, _pending) do
    LiveToast.put_toast(
      socket,
      :info,
      gettext("Tpay is still confirming the payment. The plan changes once it goes through.")
    )
  end

  # Disabled boxes are not submitted, so the locked members are added back.
  defp selected_from(params, %{lists: lists, locked: locked}) do
    kept = Map.get(params, "kept", %{})

    Map.new(lists, fn list ->
      ids = MapSet.new(Map.get(kept, Atom.to_string(list.kind), []))

      {list.kind, if(list.kind == :users, do: MapSet.union(ids, locked_in(list, locked)), else: ids)}
    end)
  end

  # The locked members first, then the oldest, as many as the plan includes.
  defp preselect(list, locked) do
    locked = locked_in(list, locked)

    list.items
    |> Enum.reject(&MapSet.member?(locked, &1.id))
    |> Enum.take(max(list.limit - MapSet.size(locked), 0))
    |> MapSet.new(& &1.id)
    |> MapSet.union(locked)
  end

  defp locked_in(%{kind: :users, items: members}, locked),
    do: members |> MapSet.new(& &1.id) |> MapSet.intersection(locked)

  defp locked_in(_list, _locked), do: MapSet.new()

  defp disabled?(selected, locked, list, id) do
    cond do
      list.kind == :users and MapSet.member?(locked, id) -> true
      MapSet.member?(selected[list.kind], id) -> false
      true -> selected_count(selected, list) >= list.limit
    end
  end

  defp selected_count(selected, list), do: MapSet.size(selected[list.kind])

  defp fits?(lists, selected), do: Enum.all?(lists, &(selected_count(selected, &1) <= &1.limit))

  defp switch_off_summary(lists, selected) do
    parts =
      for list <- lists, count = length(list.items) - selected_count(selected, list), count > 0 do
        switched_off_label(list.kind, count)
      end

    case parts do
      [] -> gettext("Nothing will be switched off.")
      parts -> gettext("Switched off after saving: %{items}.", items: Enum.join(parts, ", "))
    end
  end

  defp switched_off_label(:users, count), do: ngettext("%{count} person", "%{count} people", count)

  defp switched_off_label(:bank_institutions, count), do: ngettext("%{count} bank", "%{count} banks", count)

  defp switched_off_label(:active_projects, count), do: ngettext("%{count} project", "%{count} projects", count)

  defp format_limit(:unlimited), do: gettext("unlimited")
  defp format_limit(limit), do: Integer.to_string(limit)

  defp item_name(:users, member), do: member.display_name
  defp item_name(:bank_institutions, bank), do: bank.name
  defp item_name(:active_projects, project), do: project.name

  defp item_detail(:bank_institutions, bank), do: ngettext("%{count} account", "%{count} accounts", length(bank.accounts))

  defp item_detail(_kind, _item), do: nil

  defp format_date(date), do: Firmowid.Cldr.Date.to_string!(date, format: :long)

  defp billing_period("monthly"), do: :monthly
  defp billing_period("yearly"), do: :yearly

  defp period_label(:monthly), do: pgettext("billing period", "Monthly")
  defp period_label(:yearly), do: pgettext("billing period", "Yearly")

  defp net_price_text(rules, :monthly),
    do: gettext("%{price} + VAT / month", price: format_money(rules.monthly_price_pln))

  defp net_price_text(rules, :yearly), do: gettext("%{price} + VAT / year", price: format_money(rules.yearly_price_pln))

  # The first purchase is free until the day before its first charge.
  defp first_charge_text(plan, :monthly, %Date{} = first_charge_on) do
    gettext(
      "Free until %{last_day}. Then %{amount} gross every month, first on %{date}.",
      last_day: format_date(Date.add(first_charge_on, -1)),
      amount: format_money(PlanCatalog.gross_price_pln(plan, :monthly)),
      date: format_date(first_charge_on)
    )
  end

  defp first_charge_text(plan, :yearly, %Date{} = first_charge_on) do
    gettext(
      "Free until %{last_day}. Then %{amount} gross once a year, first on %{date}.",
      last_day: format_date(Date.add(first_charge_on, -1)),
      amount: format_money(PlanCatalog.gross_price_pln(plan, :yearly)),
      date: format_date(first_charge_on)
    )
  end

  # A returning company pays the current period as soon as the card is saved.
  defp first_charge_text(plan, :monthly, nil = _first_charge_on) do
    gettext("You pay %{amount} gross now for this month, then every month on the 1st.",
      amount: format_money(PlanCatalog.gross_price_pln(plan, :monthly))
    )
  end

  defp first_charge_text(plan, :yearly, nil = _first_charge_on) do
    gettext("You pay %{amount} gross now for a year, until %{last_day}, then once a year.",
      amount: format_money(PlanCatalog.gross_price_pln(plan, :yearly)),
      last_day: format_date(Date.shift(Month.current(), month: 12, day: -1))
    )
  end

  # The subscription's `:upgrade_price` is loaded for the fitting plan.
  defp upgrade_free?(subscription), do: Decimal.eq?(subscription.upgrade_price.gross_amount, 0)

  # The free period's wording follows the fact, not the price: an ended period awaiting its
  # renewal also costs nothing to switch, but it is not free.
  defp upgrade_text(plan, subscription) do
    price = format_money(PlanCatalog.gross_price_pln(plan, subscription.billing_period))
    next_charge_on = format_date(subscription.next_charge_on)

    cond do
      subscription.current_period_free? and subscription.billing_period == :monthly ->
        gettext(
          "Still free until %{last_day}, so the switch costs nothing now. Then %{price} gross every month, from %{date}.",
          last_day: format_date(subscription.current_period_end),
          price: price,
          date: next_charge_on
        )

      subscription.current_period_free? ->
        gettext(
          "Still free until %{last_day}, so the switch costs nothing now. Then %{price} gross once a year, from %{date}.",
          last_day: format_date(subscription.current_period_end),
          price: price,
          date: next_charge_on
        )

      subscription.billing_period == :monthly ->
        gettext(
          "You pay %{amount} gross now, the difference for this month. Then %{price} gross every month, from %{date}.",
          amount: format_money(subscription.upgrade_price.gross_amount),
          price: price,
          date: next_charge_on
        )

      true ->
        gettext(
          "You pay %{amount} gross now, the difference until %{last_day}. Then %{price} gross once a year, from %{date}.",
          amount: format_money(subscription.upgrade_price.gross_amount),
          last_day: format_date(subscription.current_period_end),
          price: price,
          date: next_charge_on
        )
    end
  end

  defp format_money(amount), do: :PLN |> Money.new(amount) |> Money.to_string!(no_fraction_if_integer: true)

  defp heading_styles,
    do: "text-2xl/tight font-semibold tracking-tight text-balance text-grey-900 sm:text-[2.625rem]/[1.1]"

  defp lead_styles, do: "mt-4 text-[1.0625rem]/relaxed text-grey-700"
end
