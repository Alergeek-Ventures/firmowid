defmodule FirmowidWeb.Billing.Views.PlanLimit do
  @moduledoc """
  The choice admins make when their company uses more than its plan includes:
  they tick what stays switched on within the current plan (see
  `Firmowid.Billing.PlanLimits`). The cheapest plan that fits is shown for
  information; buying it comes with card payments.

  A page of its own, without the app navigation. From the decision day every
  page leads admins here (see `RequireOrganization`); before it, their inbox
  links here. Without a pending decision it leads into the app.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidWeb.Organization.Components.OnboardingHeader

  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.PlanLimits
  alias Firmowid.Core
  alias FirmowidWeb.Billing.Utilities.Worksheet
  alias FirmowidWeb.Infrastructure.UserAuth

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
            <p class="text-[0.9375rem] font-medium text-grey-900">
              {gettext("%{price} PLN net / month", price: @fitting_rules.monthly_price_pln)}
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

    assign(socket,
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
      plan_label: Worksheet.plan_label(org.billing_plan),
      fitting_plan: fitting_plan,
      fitting_rules: PlanCatalog.plan!(fitting_plan),
      owner_member_id: owner_member_id,
      own_member_id: user.member.id,
      locked: locked,
      lists: lists,
      selected: Map.new(lists, &{&1.kind, preselect(&1, locked)})
    )
  end

  @impl true
  def handle_event("select", params, socket) do
    {:noreply, assign(socket, :selected, selected_from(params, socket.assigns))}
  end

  def handle_event("keep", params, socket) do
    %{current_org: org, ash_scope: scope} = socket.assigns
    selected = selected_from(params, socket.assigns)
    kept = Map.new(selected, fn {kind, ids} -> {kind, MapSet.to_list(ids)} end)

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

  defp heading_styles,
    do: "text-2xl/tight font-semibold tracking-tight text-balance text-grey-900 sm:text-[2.625rem]/[1.1]"

  defp lead_styles, do: "mt-4 text-[1.0625rem]/relaxed text-grey-700"
end
