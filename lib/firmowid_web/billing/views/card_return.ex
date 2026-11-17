defmodule FirmowidWeb.Billing.Views.CardReturn do
  @moduledoc """
  Where Tpay brings an admin back from its card page after buying a plan on
  `PlanLimit`, and where an admin replaces the card of the company's plan.

  Tpay's redirect does not prove the card was saved; its notification does (see
  `Firmowid.Billing.Subscription` `:save_card`). So after a successful redirect
  the page waits for the subscription to become active and, for a company that
  has used its free month, for the first payment, then leads into the app. A
  declined first payment ends the subscription, and the page says so. After
  Tpay's error redirect it offers to try again.

  `?zmiana=tak` (the link in the declined payment email) opens Tpay's card page
  for a new card of the active subscription at once. Coming back, the page only
  says the new card is being saved: nothing waits for it, since the next charge
  is days away.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Link
  import FirmowidWeb.Organization.Components.OnboardingHeader
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Billing
  alias Firmowid.Billing.PlanLimits
  alias FirmowidWeb.Billing.Utilities.Navigation
  alias FirmowidWeb.Billing.Utilities.Worksheet
  alias FirmowidWeb.Infrastructure.UserAuth

  on_mount {FirmowidWeb.Infrastructure.Hooks.RequireAdmin, :default}

  # Tpay's notification usually comes within seconds of the redirect.
  @late_after to_timeout(second: 30)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex w-full max-w-7xl flex-col gap-4 px-4 pb-8 sm:px-8 lg:px-20 lg:pb-10">
      <.onboarding_header exit_path={@exit_path} />
      <div id="card-return" class="mx-auto w-full max-w-2xl" aria-live="polite">
        <%= case @state do %>
          <% :checking -> %>
            <h1 class={heading_styles()}>{gettext("Checking the card...")}</h1>
            <p class={lead_styles()}>
              {gettext("Tpay is confirming the card. It usually takes a few seconds.")}
            </p>
            <.purchase_line purchase={@purchase} />
          <% :late -> %>
            <h1 class={heading_styles()}>{gettext("The card is not confirmed yet")}</h1>
            <p class={lead_styles()}>
              {gettext(
                "We are still waiting for Tpay to confirm the card. This page moves on by itself once Tpay confirms it. You can also come back later."
              )}
            </p>
            <.purchase_line purchase={@purchase} />
          <% :charging -> %>
            <h1 class={heading_styles()}>{gettext("Taking the payment...")}</h1>
            <p class={lead_styles()}>
              {gettext(
                "The card is saved and Tpay is taking the payment. This page moves on by itself once Tpay answers."
              )}
            </p>
            <.purchase_line purchase={@purchase} />
          <% :declined -> %>
            <h1 class={heading_styles()}>{gettext("The payment did not go through")}</h1>
            <p class={lead_styles()}>
              {gettext("Your plan has not changed.")}
              {gettext("You can try again with the same or another card.")}
            </p>
            <.purchase_line purchase={@purchase} />
            <.link
              id="card-return-retry"
              kind="button"
              variant="primary"
              navigate={Navigation.plan_limit_path()}
              class="mt-8 w-full sm:w-auto sm:px-8"
            >
              {gettext("Try again")}
            </.link>
          <% :card_changing -> %>
            <h1 class={heading_styles()}>{gettext("Tpay is saving the new card")}</h1>
            <p class={lead_styles()}>
              {gettext(
                "The next payments use it once Tpay confirms it, which usually takes a few seconds."
              )}
            </p>
            <.link
              id="card-return-app"
              kind="button"
              variant="primary"
              navigate={@app_path}
              class="mt-8 w-full sm:w-auto sm:px-8"
            >
              {gettext("Go to the app")}
            </.link>
          <% :card_change_error -> %>
            <h1 class={heading_styles()}>{gettext("The card was not changed")}</h1>
            <p class={lead_styles()}>
              {gettext("The current card stays.")}
              {gettext("You can try again with another card.")}
            </p>
            <.link
              id="card-return-retry"
              kind="button"
              variant="primary"
              navigate={Navigation.card_change_path()}
              class="mt-8 w-full sm:w-auto sm:px-8"
            >
              {gettext("Try again")}
            </.link>
          <% :error -> %>
            <h1 class={heading_styles()}>{gettext("The card was not saved")}</h1>
            <p class={lead_styles()}>
              {gettext("Nothing was charged and your plan has not changed.")}
              {gettext("You can try again with the same or another card.")}
            </p>
            <.purchase_line purchase={@purchase} />
            <.link
              id="card-return-retry"
              kind="button"
              variant="primary"
              navigate={Navigation.plan_limit_path()}
              class="mt-8 w-full sm:w-auto sm:px-8"
            >
              {gettext("Try again")}
            </.link>
        <% end %>
      </div>
    </div>
    """
  end

  # What is being bought, quietly, so the wait is about something.
  attr :purchase, :map, default: nil

  defp purchase_line(assigns) do
    ~H"""
    <p :if={@purchase} class="mt-6 text-[0.9375rem] text-grey-600">
      {gettext("%{plan} plan · %{period}",
        plan: Worksheet.plan_label(@purchase.plan),
        period: period_label(@purchase.billing_period)
      )}
    </p>
    """
  end

  defp period_label(:monthly), do: pgettext("billing period", "Monthly")
  defp period_label(:yearly), do: pgettext("billing period", "Yearly")

  @impl true
  def mount(params, _session, socket) do
    %{current_user: user, current_org: org, ash_scope: scope} = socket.assigns
    app_path = UserAuth.signed_in_path_for_user(user, scope.tenant)

    socket =
      assign(socket,
        page_title: gettext("Card"),
        purchase: nil,
        # A page of its own, without the app navigation, like the plan limit page.
        focused: true,
        no_padding: true,
        app_path: app_path,
        exit_path: if(not PlanLimits.decision_due?(org), do: app_path)
      )

    # The `wynik` values Tpay's redirects carry are set in `Subscription.Changes.RequestCardPage`.
    case params do
      %{"zmiana" => "tak"} ->
        {:ok, change_card(socket, latest_subscription(scope))}

      %{"wynik" => "blad"} ->
        {:ok, assign(socket, state: :error, purchase: latest_subscription(scope))}

      %{"wynik" => "zmieniona"} ->
        {:ok, assign(socket, :state, :card_changing)}

      %{"wynik" => "niezmieniona"} ->
        {:ok, assign(socket, :state, :card_change_error)}

      _params ->
        {:ok, mount_checking(socket)}
    end
  end

  defp change_card(socket, subscription) do
    case subscription do
      %{status: :active} ->
        subscription =
          Billing.change_subscription_card!(subscription, scope: socket.assigns.ash_scope)

        redirect(socket, external: subscription.__metadata__.card_page_url)

      _no_active ->
        socket
        |> LiveToast.put_toast(
          :error,
          gettext("Your company has no paid plan whose card could change.")
        )
        |> push_navigate(to: socket.assigns.app_path)
    end
  end

  # The subscription bought last, with what the page tells about it.
  defp latest_subscription(scope) do
    %{}
    |> Billing.list_subscriptions!(
      scope: scope,
      query: [sort: [inserted_at: :desc], limit: 1],
      load: [:current_period_free?, :current_period_settled?]
    )
    |> List.first()
  end

  defp mount_checking(socket) do
    if connected?(socket) do
      # Subscribed before the first look, so a notification in between is not missed.
      Phoenix.PubSub.subscribe(Firmowid.PubSub, "subscription:#{socket.assigns.ash_scope.tenant}")
      Process.send_after(self(), :late, @late_after)
    end

    socket
    |> assign(:state, :checking)
    |> follow_purchase(latest_subscription(socket.assigns.ash_scope))
  end

  # The subscription or its first payment changed (see the `pub_sub` of `Subscription` and `Payment`).
  @impl true
  def handle_info(message, %{assigns: %{state: state}} = socket)
      when message in [:subscription_changed, :payment_recorded] and state in [:checking, :late, :charging] do
    {:noreply, follow_purchase(socket, latest_subscription(socket.assigns.ash_scope))}
  end

  def handle_info(:late, %{assigns: %{state: :checking}} = socket), do: {:noreply, assign(socket, :state, :late)}

  def handle_info(_message, socket), do: {:noreply, socket}

  # Leads into the app once the purchase's current period is paid or free; until then, the card
  # is being checked or the payment taken. A subscription ended by its declined first payment
  # shows the decline.
  defp follow_purchase(socket, %{status: :active, current_period_settled?: true} = subscription) do
    plan = Worksheet.plan_label(subscription.plan)
    date = Firmowid.Cldr.Date.to_string!(subscription.next_charge_on, format: :long)

    message =
      if subscription.current_period_free?,
        do: gettext("The %{plan} plan is on. First payment on %{date}.", plan: plan, date: date),
        else: gettext("The %{plan} plan is on. Next payment on %{date}.", plan: plan, date: date)

    socket
    |> LiveToast.put_toast(:info, message)
    |> push_navigate(to: socket.assigns.app_path)
  end

  defp follow_purchase(socket, %{status: :active} = subscription),
    do: assign(socket, state: :charging, purchase: subscription)

  defp follow_purchase(socket, %{status: :ended, end_reason: :payment_failed} = subscription),
    do: assign(socket, state: :declined, purchase: subscription)

  defp follow_purchase(socket, awaiting_card), do: assign(socket, :purchase, awaiting_card)

  defp heading_styles,
    do: "text-2xl/tight font-semibold tracking-tight text-balance text-grey-900 sm:text-[2.625rem]/[1.1]"

  defp lead_styles, do: "mt-4 text-[1.0625rem]/relaxed text-grey-700"
end
