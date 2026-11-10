defmodule FirmowidWeb.Organization.Views.FirstSteps do
  @moduledoc """
  First steps of a just created company: connecting KSeF and the bank, then
  inviting the team.

  The company card shows a stamp per step, read from the data: the billing stamp
  from the organization, the KSeF stamp from the credential and the invoices it
  fetched, the bank stamp from the connected accounts. KSeF and the bank finish
  in the background, so the card follows their PubSub events and the owner can
  move on before they finish.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.KsefConnection
  import FirmowidUI.Components.Link
  import FirmowidWeb.Organization.Components.CompanyCard
  import FirmowidWeb.Organization.Components.OnboardingHeader
  import Phoenix.Component, except: [link: 1]

  alias Ash.Notifier.Notification
  alias Firmowid.Core
  alias Firmowid.Finances
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Ksef
  alias Firmowid.Ksef.Credential
  alias FirmowidUI.Ksef.Connection
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Infrastructure.UserAuth
  alias FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents
  alias FirmowidWeb.Organization.Utilities.Navigation, as: OrganizationNavigation
  alias Phoenix.Socket.Broadcast

  require Logger

  # KSeF reports no event when a fetch ends, so the page asks while one runs.
  @fetch_check_ms 3_000
  @connecting ~w(authenticating authenticating_epuap preparing_enrollment wait_for_certificate)a

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto flex max-w-7xl flex-col gap-4 px-4 pb-8 sm:px-8 lg:px-20 lg:pb-10">
      <.onboarding_header exit_path={@exit_path} back={back_path(@step)} step={step_number(@step)} />
      <div class="grid items-start gap-10 lg:grid-cols-[minmax(0,1fr)_26rem] lg:gap-16">
        <%!-- The card stays under the header while the steps beside it scroll. --%>
        <div class="order-2 lg:sticky lg:top-28 lg:order-1 lg:pt-2">
          <.company_card id="company-card" name={@current_org.name} rows={rows(@current_org)}>
            <:stamps :let={card}>
              <.stamp
                card={card}
                text={billing_stamp_text(@current_org.industry, @current_org.bills_hourly)}
                icon={billing_icon(@current_org.bills_hourly)}
                rotate={-9}
              />
              <%= case ksef_stamp(assigns) do %>
                <% :done -> %>
                  <.stamp
                    card={card}
                    text={gettext("KSEF · CONNECTED")}
                    icon={:plug}
                    rotate={6}
                    pressed={:ksef not in @stamped_on_arrival}
                  />
                <% {:pending, hint} -> %>
                  <.stamp_slot label="KSeF" hint={hint} state={:pending} />
                <% state -> %>
                  <.stamp_slot label="KSeF" hint={gettext("waiting for a stamp")} state={state} />
              <% end %>
              <%= case bank_stamp(assigns) do %>
                <% {:done, text} -> %>
                  <.stamp
                    card={card}
                    text={String.upcase(text)}
                    icon={:landmark}
                    rotate={-4}
                    pressed={:bank not in @stamped_on_arrival}
                  />
                <% :pending -> %>
                  <.stamp_slot label={gettext("Bank")} hint={gettext("connecting")} state={:pending} />
                <% state -> %>
                  <.stamp_slot
                    label={gettext("Bank")}
                    hint={gettext("waiting for a stamp")}
                    state={state}
                  />
              <% end %>
            </:stamps>
          </.company_card>
        </div>
        <section class="order-1 lg:order-2" aria-live="polite">
          <%!-- A new id per step makes the panel enter anew. --%>
          <div id={"step-#{@step}"} class="motion-safe:animate-step-in motion-reduce:animate-fade-in">
            <.step_panel {assigns} />
          </div>
        </section>
      </div>
    </div>
    """
  end

  # ── Step panels ──────────────────────────────────────────────────────

  defp step_panel(%{step: :ksef} = assigns) do
    ~H"""
    <%= cond do %>
      <% @ksef_auth_status == :working -> %>
        <h1 class={heading_styles()}>{gettext("KSeF is connected.")}</h1>
        <.fetch_progress fetching?={@ksef_fetching?} invoices={@invoice_count} />
        <.primary_link
          id="ksef-next"
          patch={OrganizationNavigation.first_steps_path(:bank)}
          title={gettext("Next: connect the bank")}
          hint={
            (@ksef_fetching? && gettext("Fetching continues in the background")) ||
              gettext("Step %{number} of %{total}", number: 5, total: 5)
          }
        />
      <% @ksef_auth_status in @connecting -> %>
        <h1 class={heading_styles()}>{gettext("Connecting to KSeF.")}</h1>
        <p class={lead_styles()}>
          {gettext(
            "You do not have to wait. Go on to the bank, and the stamp will appear by itself once the invoices arrive."
          )}
        </p>
        <ol class="mt-6 grid gap-3.5 text-[0.9375rem]">
          <.timeline_item state={:done} title={gettext("Authorization request sent")} />
          <.timeline_item
            state={:running}
            title={gettext("KSeF is issuing a certificate for Firmowid")}
          />
          <.timeline_item
            state={:waiting}
            title={gettext("Cost and sales invoices from the last 30 days")}
          />
        </ol>
        <.primary_link
          id="ksef-next"
          patch={OrganizationNavigation.first_steps_path(:bank)}
          title={gettext("Next: connect the bank")}
          hint={gettext("Connecting continues in the background")}
        />
      <% true -> %>
        <h1 class={heading_styles()}>{gettext("Without KSeF your invoice stays a draft.")}</h1>
        <p class={lead_styles()}>
          {gettext(
            "Cost invoices from the last 30 days will arrive by themselves, and you will send sales invoices in one click."
          )}
        </p>
        <div id="ksef-connection" class="mt-6 rounded-xl bg-white p-5">
          <.ksef_connection
            ksef_credential={@ksef_credential}
            ksef_auth_method={@ksef_auth_method}
            ksef_auth_status={@ksef_auth_status}
            ksef_failure={@ksef_failure}
            uploads={@uploads}
            allow_token?={false}
            details={:inline}
            intro?={false}
          />
        </div>
    <% end %>
    <.link
      :if={@ksef_auth_status not in [:working | @connecting]}
      kind="unstyled"
      patch={OrganizationNavigation.first_steps_path(:bank)}
      class="mt-6 inline-block text-[0.9375rem] text-grey-700 underline underline-offset-4"
    >
      {gettext("I will do it later. The stamp will wait.")}
    </.link>
    """
  end

  defp step_panel(%{step: :bank} = assigns) do
    ~H"""
    <p
      :if={@ksef_auth_status == :working and @ksef_fetching?}
      class="mb-6 flex w-fit items-center gap-2.5 rounded-full border border-moss-300 bg-moss-100 py-1.5 pr-3.5 pl-2.5 text-sm font-medium text-moss-800"
    >
      <span class="size-3.5 rounded-full border-2 border-moss-300 border-t-moss-800 motion-safe:animate-spin"></span>
      {ngettext(
        "KSeF: %{count} invoice so far, fetching more",
        "KSeF: %{count} invoices so far, fetching more",
        @invoice_count
      )}
    </p>
    <%= if @bank_accounts != [] or @bank_pending? do %>
      <h1 class={heading_styles()}>
        <%= cond do %>
          <% bank_synced?(@bank_accounts) -> %>
            {gettext("The bank is connected.")}
          <% @bank_accounts != [] -> %>
            {gettext("The account has been added.")}
          <% true -> %>
            {gettext("Waiting for the bank's consent.")}
        <% end %>
      </h1>
      <p class={lead_styles()}>
        <%= cond do %>
          <% bank_synced?(@bank_accounts) -> %>
            {gettext("Transfers will be matched with invoices automatically.")}
          <% @bank_accounts != [] -> %>
            {gettext("You can connect the bank at any time in the settings.")}
          <% true -> %>
            {gettext(
              "The bank confirms the consent within a minute or two. The stamp will appear by itself."
            )}
        <% end %>
      </p>
      <.primary_link
        id="bank-next"
        patch={OrganizationNavigation.first_steps_path(:plan)}
        title={gettext("Next: your plan")}
        hint={gettext("See what the Free plan includes")}
      />
    <% else %>
      <h1 class={heading_styles()}>{gettext("Connect the company bank account.")}</h1>
      <p class={lead_styles()}>
        {gettext(
          "We will check which invoices are already paid and which are waiting for a transfer."
        )}
      </p>
      <p class="mt-5 flex items-center gap-2.5 rounded-xl bg-moss-100 px-4 py-3 text-[0.9375rem] font-medium text-moss-800">
        <Lucideicons.shield_check class="size-5 shrink-0" aria-hidden="true" />
        {gettext("Read-only access. We see transfers, but we cannot make any payment.")}
      </p>
      <.form for={%{}} id="bank-search" phx-change="search_banks" class="mt-6">
        <label class="flex h-13 items-center gap-3 rounded-xl border border-grey-300 bg-white px-4 focus-within:border-black">
          <Lucideicons.search class="size-5 text-grey-900" aria-hidden="true" />
          <span class="sr-only">{gettext("Search for your bank")}</span>
          <input
            name="query"
            value={@bank_query}
            phx-debounce="150"
            placeholder={gettext("Search for your bank")}
            autocomplete="off"
            class="w-full border-0 bg-transparent p-0 text-[1.0625rem] text-grey-900 placeholder:text-grey-500 focus:ring-0"
          />
        </label>
      </.form>
      <%!-- Room for the full list, so the page does not jump while searching. --%>
      <div
        id="bank-results"
        class="mt-3 grid min-h-78 auto-rows-[3.5rem] grid-cols-2 content-start gap-2"
      >
        <p
          :if={visible_institutions(@institutions, @bank_query) == [] and @institutions != []}
          class="col-span-2 py-4 text-center text-[0.9375rem] text-grey-600"
        >
          {gettext("We cannot find this bank.")}
        </p>
        <.button
          :for={institution <- visible_institutions(@institutions, @bank_query)}
          id={"institution-#{institution.id}"}
          type="button"
          variant="unstyled"
          phx-click="connect_bank"
          phx-value-id={institution.id}
          phx-value-days={institution.transaction_total_days}
          phx-disable-with
          class="flex min-w-0 items-center gap-2.5 rounded-xl border border-grey-200 bg-white px-3.5 text-left text-[0.9375rem]/tight font-medium text-grey-900 hover:border-black"
        >
          <img src={institution.logo} alt="" class="size-5 shrink-0 object-contain" />
          <%!-- Two lines, so banks sharing a first word stay apart on a phone. --%>
          <span class="line-clamp-2">{institution.name}</span>
        </.button>
      </div>

      <.link
        kind="unstyled"
        patch={OrganizationNavigation.first_steps_path(:plan)}
        class="mt-6 inline-block text-[0.9375rem] text-grey-700 underline underline-offset-4"
      >
        {gettext("Skip for now")}
      </.link>
    <% end %>
    """
  end

  defp step_panel(%{step: :plan} = assigns) do
    ~H"""
    <h1 class={heading_styles()}>{gettext("You start for free.")}</h1>
    <p class={lead_styles()}>
      {gettext("The Free plan needs no card and does not run out after a trial.")}
    </p>
    <dl class="mt-6 divide-y divide-grey-200 rounded-2xl border border-grey-300 bg-white px-5">
      <div
        :for={{label, value} <- free_plan_limits()}
        class="flex items-baseline justify-between gap-4 py-3.5"
      >
        <dt class="text-[0.9375rem] text-grey-700">{label}</dt>
        <dd class="shrink-0 text-right text-[0.9375rem] font-medium text-grey-900">{value}</dd>
      </div>
    </dl>

    <h2 class="mt-8 text-[1.0625rem] font-medium text-grey-900">
      {gettext("When will you need a paid plan?")}
    </h2>
    <p class="mt-1.5 text-[0.9375rem]/relaxed text-grey-700">
      {gettext(
        "Only when the company outgrows the Free plan: a third person on the team, a second bank account or a fourth project. We will write to you as soon as you start going over the limits."
      )}
    </p>

    <.primary_link
      id="plan-next"
      patch={OrganizationNavigation.first_steps_path(:gotowe)}
      title={gettext("Continue")}
      hint={gettext("One last question")}
    />
    """
  end

  defp step_panel(%{step: :gotowe} = assigns) do
    ~H"""
    <p
      :if={all_stamped?(assigns)}
      class="mb-6 flex w-fit items-center gap-2 rounded-full border border-moss-300 bg-moss-100 px-3 py-1 text-sm font-medium text-moss-800"
    >
      <Lucideicons.check class="size-4" aria-hidden="true" />
      {gettext("All stamps are in place")}
    </p>
    <h1 class={heading_styles()}>
      {(all_stamped?(assigns) && gettext("The company is ready to work.")) ||
        gettext("The company is almost ready.")}
    </h1>
    <p class={lead_styles()}>
      <span :if={@ksef_auth_status == :working}>
        {ngettext(
          "%{count} cost invoice arrived from KSeF, and new ones will keep arriving.",
          "%{count} cost invoices arrived from KSeF, and new ones will keep arriving.",
          @invoice_count
        )}
      </span>
      <span :if={bank_synced?(@bank_accounts)}>{gettext("Transfers will be matched with invoices.")}</span>
      {connect_later_hint(@ksef_auth_status == :working, bank_synced?(@bank_accounts))}
    </p>
    <.form for={%{}} id="finish-form" phx-submit="finish" class="mt-8">
      <fieldset>
        <legend class="text-[1.0625rem] font-medium text-grey-900">
          {gettext("How did you hear about Firmowid?")}
        </legend>
        <p class="mt-1 text-sm text-grey-600">{gettext("Optional, but it helps us a lot.")}</p>
        <div class="mt-3 flex flex-wrap gap-2">
          <label
            :for={{label, source} <- heard_from_options()}
            class="cursor-pointer rounded-full border border-grey-300 bg-white px-3.5 py-1.5 text-sm text-grey-900 transition-colors hover:border-grey-500 has-checked:border-black has-checked:bg-black has-checked:text-white has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-black"
          >
            <input type="radio" name="heard_from" value={source} class="sr-only" />
            {label}
          </label>
        </div>
      </fieldset>

      <.button
        id="go-to-app"
        type="submit"
        variant="unstyled"
        class="mt-8 flex w-full items-center gap-4 rounded-xl bg-black px-5.5 py-4 text-left text-white shadow-[0_18px_36px_-20px_rgba(0,0,0,.6)] transition-colors hover:bg-grey-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-black"
      >
        <span class="flex-1">
          <span class="block text-lg font-medium">{gettext("Go to Firmowid")}</span>
          <span class="block text-sm text-white/65">{gettext("Everything you set up is waiting there")}</span>
        </span>
        <Lucideicons.arrow_right class="size-5" aria-hidden="true" />
      </.button>
    </.form>
    """
  end

  # The Free plan as the pricing page offers it.
  defp free_plan_limits do
    [
      {gettext("Invoices and KSeF"), gettext("unlimited")},
      {gettext("Users"), "2"},
      {gettext("Bank accounts with transfer matching"), "1"},
      {gettext("Time tracking"), gettext("up to 3 projects")},
      {gettext("Document OCR"), gettext("10 credits / month")}
    ]
  end

  defp heard_from_options do
    [
      {gettext("Search engine"), :search},
      {gettext("ChatGPT or another AI"), :ai_assistant},
      {gettext("A friend"), :recommendation},
      {gettext("My accountant"), :accountant},
      {gettext("Social media"), :social_media},
      {gettext("Somewhere else"), :other}
    ]
  end

  # ── Building blocks ──────────────────────────────────────────────────

  defp heading_styles,
    do: "text-2xl/tight font-semibold tracking-tight text-balance text-grey-900 sm:text-[2.625rem]/[1.1]"

  defp lead_styles, do: "mt-4 text-[1.0625rem]/relaxed text-grey-700"

  # KSeF has no way back: the company is already created by then.
  defp back_path(:ksef), do: nil
  defp back_path(:bank), do: OrganizationNavigation.first_steps_path(:ksef)
  defp back_path(:plan), do: OrganizationNavigation.first_steps_path(:bank)
  defp back_path(:gotowe), do: OrganizationNavigation.first_steps_path(:plan)

  defp step_number(:ksef), do: 4
  defp step_number(:bank), do: 5
  defp step_number(_plan_or_gotowe), do: :done

  attr :fetching?, :boolean, required: true
  attr :invoices, :integer, required: true

  defp fetch_progress(assigns) do
    ~H"""
    <ol class="mt-6 grid gap-3.5 text-[0.9375rem]">
      <.timeline_item state={:done} title={gettext("KSeF issued a certificate for Firmowid")} />
      <.timeline_item
        state={(@fetching? && :running) || :done}
        title={gettext("Cost and sales invoices from the last 30 days")}
        hint={
          ngettext(
            "%{count} invoice so far, the number grows live",
            "%{count} invoices so far, the number grows live",
            @invoices
          )
        }
      />
    </ol>
    <p :if={@fetching?} class="mt-4 text-[0.8125rem]/relaxed text-grey-600">
      {gettext(
        "This usually takes a dozen or so seconds. With many invoices KSeF may need even several dozen minutes."
      )}
    </p>
    """
  end

  attr :state, :atom, required: true, values: [:done, :running, :waiting]
  attr :title, :string, required: true
  attr :hint, :string, default: nil

  defp timeline_item(assigns) do
    ~H"""
    <li class={["flex items-start gap-3", @state == :waiting && "text-grey-500"]}>
      <span
        :if={@state == :done}
        class="grid size-5.5 shrink-0 place-items-center rounded-full bg-moss-200 text-moss-700"
      >
        <Lucideicons.check class="size-3.5" aria-hidden="true" />
      </span>
      <span
        :if={@state == :running}
        class="size-5.5 shrink-0 rounded-full border-2 border-moss-200 border-t-moss-700 motion-safe:animate-spin"
      ></span>
      <span
        :if={@state == :waiting}
        class="size-5.5 shrink-0 rounded-full border-[1.5px] border-dashed border-grey-400"
      ></span>
      <span>
        {@title}
        <span :if={@hint} class="mt-0.5 block text-[0.8125rem] text-grey-600">{@hint}</span>
      </span>
    </li>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, required: true
  attr :patch, :string, default: nil
  attr :navigate, :string, default: nil

  defp primary_link(assigns) do
    ~H"""
    <.link
      id={@id}
      kind="unstyled"
      patch={@patch}
      navigate={@navigate}
      class="mt-7 flex w-full items-center gap-4 rounded-xl bg-black px-5.5 py-4 text-white shadow-[0_18px_36px_-20px_rgba(0,0,0,.6)] transition-colors hover:bg-grey-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-black"
    >
      <span class="flex-1">
        <span class="block text-lg font-medium">{@title}</span>
        <span class="block text-sm text-white/65">{@hint}</span>
      </span>
      <Lucideicons.arrow_right class="size-5" aria-hidden="true" />
    </.link>
    """
  end

  # ── Lifecycle ────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope

    if connected?(socket) do
      Endpoint.subscribe("cost_invoice:created:#{scope.tenant}")
      Endpoint.subscribe("requisition:linked:#{scope.tenant}")
    end

    {:ok,
     socket
     |> Connection.init(scope)
     |> assign(
       page_title: gettext("First steps"),
       # The first steps are a page of their own, without the app navigation.
       focused: true,
       no_padding: true,
       # Until the first steps are done every page leads back here, so the way out is logging out.
       exit_path:
         if(
           not UserAuth.first_steps_pending?(
             socket.assigns.current_user,
             socket.assigns.current_org
           ),
           do: UserAuth.signed_in_path_for_user(socket.assigns.current_user, scope.tenant)
         ),
       connecting: @connecting,
       institutions: [],
       bank_query: "",
       fetch_check_scheduled?: false
     )
     |> assign_invoice_count()
     |> assign_bank()
     |> assign_stamped_on_arrival()
     |> schedule_fetch_check()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:step, step(params, socket.assigns))
      |> handle_bank_return(params)

    socket = if socket.assigns.step == :bank, do: assign_institutions(socket), else: socket

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_banks", %{"query" => query}, socket) do
    {:noreply, assign(socket, :bank_query, query)}
  end

  def handle_event("connect_bank", %{"id" => institution_id, "days" => days}, socket) do
    # GoCardless appends `?ref=` to the redirect, so it gets no query of its own;
    # `ref` alone brings the owner back to the bank step.
    redirect_url = Endpoint.url() <> OrganizationNavigation.first_steps_path()

    {:ok, link} =
      Finances.create_requisition(institution_id, String.to_integer(days), redirect_url, scope: socket.assigns.ash_scope)

    {:noreply, redirect(socket, external: link)}
  end

  def handle_event("finish", params, socket) do
    %{current_user: user, current_org: organization, ash_scope: scope} = socket.assigns

    socket =
      if UserAuth.first_steps_pending?(user, organization) do
        Core.complete_organization_onboarding!(organization, scope: scope)
        PosthogBusinessEvents.capture(socket, :onboarding_completed, heard_from(params))
      else
        socket
      end

    {:noreply, push_navigate(socket, to: UserAuth.signed_in_path_for_user(user, organization.id))}
  end

  def handle_event(event, params, socket)
      when event in [
             "select_ksef_auth_method",
             "validate_ksef_certificate",
             "download_ksef_auth_token_request",
             "validate_signed_auth_token_request",
             "upload_signed_auth_token_request",
             "save_ksef_certificate"
           ] do
    Connection.handle_event(event, params, socket, socket.assigns.ash_scope)
  end

  @impl true
  def handle_info(%Broadcast{topic: "credential:" <> _, payload: %Notification{resource: Credential}} = message, socket) do
    {:noreply, socket} = Connection.handle_info(message, socket, socket.assigns.ash_scope)

    {:noreply,
     socket
     |> assign(:ksef_fetching?, Ksef.fetching_invoices?(socket.assigns.ash_scope))
     |> schedule_fetch_check()}
  end

  def handle_info(%Broadcast{topic: "cost_invoice:created:" <> _}, socket) do
    {:noreply, assign_invoice_count(socket)}
  end

  def handle_info(%Broadcast{topic: "requisition:linked:" <> _}, socket) do
    {:noreply, assign_bank(socket)}
  end

  def handle_info(:check_fetch, socket) do
    socket =
      socket
      |> assign(
        fetch_check_scheduled?: false,
        ksef_fetching?: Ksef.fetching_invoices?(socket.assigns.ash_scope)
      )
      |> assign_invoice_count()

    {:noreply, schedule_fetch_check(socket)}
  end

  # ── State ────────────────────────────────────────────────────────────

  # Without a step in the URL, the owner continues where the setup stopped.
  defp step(%{"krok" => "ksef"}, _assigns), do: :ksef
  defp step(%{"krok" => "bank"}, _assigns), do: :bank
  defp step(%{"krok" => "plan"}, _assigns), do: :plan
  defp step(%{"krok" => "gotowe"}, _assigns), do: :gotowe
  defp step(%{"ref" => _requisition}, _assigns), do: :bank
  defp step(_missing, %{ksef_auth_status: :idle}), do: :ksef
  defp step(_missing, %{bank_accounts: [], bank_pending?: false}), do: :bank
  defp step(_missing, _assigns), do: :gotowe

  # GoCardless sends the owner back with the requisition as `ref`, or with an error.
  defp handle_bank_return(socket, %{"ref" => _requisition, "error" => error}) do
    Logger.warning("Failed to connect to bank", error_kind: Firmowid.ErrorKind.classify(error))

    LiveToast.put_toast(socket, :error, gettext("We will keep trying to connect on your behalf."),
      title: gettext("The bank connection could not be created at this time.")
    )
  end

  defp handle_bank_return(socket, %{"ref" => _requisition}) do
    socket
    |> PosthogBusinessEvents.capture(:bank_connection_completed)
    |> assign_bank()
  end

  defp handle_bank_return(socket, _params), do: socket

  defp assign_invoice_count(socket) do
    assign(socket, :invoice_count, Ash.count!(CostInvoice, scope: socket.assigns.ash_scope))
  end

  defp assign_bank(socket) do
    scope = socket.assigns.ash_scope

    assign(socket,
      bank_accounts: Finances.list_bank_accounts!(scope: scope),
      bank_pending?: Enum.any?(Finances.list_requisitions!(scope: scope), &(&1.status == :pending))
    )
  end

  defp assign_institutions(%{assigns: %{institutions: []}} = socket) do
    assign(
      socket,
      :institutions,
      Finances.list_institutions!("pl", actor: socket.assigns.current_user)
    )
  end

  defp assign_institutions(socket), do: socket

  defp schedule_fetch_check(socket) do
    %{ksef_auth_status: status, ksef_fetching?: fetching?, fetch_check_scheduled?: scheduled?} =
      socket.assigns

    if connected?(socket) and not scheduled? and (fetching? or status in @connecting) do
      Process.send_after(self(), :check_fetch, @fetch_check_ms)
      assign(socket, :fetch_check_scheduled?, true)
    else
      socket
    end
  end

  defp heard_from(%{"heard_from" => value}) do
    case Enum.find(heard_from_options(), fn {_label, source} ->
           Atom.to_string(source) == value
         end) do
      {_label, source} -> %{heard_from: source}
      nil -> %{}
    end
  end

  defp heard_from(_params), do: %{}

  # ── Card content ─────────────────────────────────────────────────────

  defp ksef_stamp(%{ksef_auth_status: :working, ksef_fetching?: false}), do: :done

  defp ksef_stamp(%{ksef_auth_status: :working, invoice_count: count}),
    do: {:pending, ngettext("%{count} invoice", "%{count} invoices", count)}

  defp ksef_stamp(%{ksef_auth_status: status}) when status in @connecting, do: {:pending, gettext("connecting")}

  defp ksef_stamp(%{step: :ksef}), do: :active
  defp ksef_stamp(_assigns), do: :waiting

  defp bank_stamp(%{bank_accounts: [account | _accounts]}), do: {:done, bank_stamp_text(account)}

  defp bank_stamp(%{bank_pending?: true}), do: :pending
  defp bank_stamp(%{step: :bank}), do: :active
  defp bank_stamp(_assigns), do: :waiting

  # An account added by hand has no bank connection behind it.
  defp bank_stamp_text(%{institution_id: nil}), do: gettext("Account · added")

  defp bank_stamp_text(account), do: gettext("%{bank} · connected", bank: account.institution_name)

  # Only a bank connection brings the transfers; an account added by hand does not.
  defp bank_synced?(accounts), do: Enum.any?(accounts, & &1.institution_id)

  # Stamps already on the card when the page opens stay still; only the ones
  # earned while it is open are pressed onto it.
  defp assign_stamped_on_arrival(socket) do
    stamped =
      for {stamp, true} <- [
            ksef: ksef_stamp(socket.assigns) == :done,
            bank: match?({:done, _}, bank_stamp(socket.assigns))
          ],
          do: stamp

    assign(socket, :stamped_on_arrival, stamped)
  end

  defp all_stamped?(assigns), do: ksef_stamp(assigns) == :done and match?({:done, _bank}, bank_stamp(assigns))

  defp connect_later_hint(false = _ksef?, false = _bank?),
    do: gettext("You can connect KSeF and the bank at any time in the settings.")

  defp connect_later_hint(false, true), do: gettext("You can connect KSeF at any time in the settings.")

  defp connect_later_hint(true, false), do: gettext("You can connect the bank at any time in the settings.")

  defp connect_later_hint(true, true), do: nil

  defp rows(organization) do
    [
      %{label: "NIP", value: format_nip(organization.nip)},
      %{label: gettext("Address"), value: organization.address},
      %{
        label: "VAT",
        value: (organization.is_vat_payer && gettext("Active VAT payer")) || gettext("Exempt from VAT")
      }
    ]
  end

  # The banks most Polish companies use come first; the rest keep GoCardless's order.
  @popular_banks [
    "pko",
    "mbank",
    "ing",
    "santander",
    "pekao",
    "millennium",
    "alior",
    "credit agricole"
  ]

  defp visible_institutions(institutions, query) do
    query = query |> String.trim() |> String.downcase()

    institutions
    |> Enum.filter(&(query == "" or String.contains?(String.downcase(&1.name), query)))
    |> Enum.sort_by(&popularity(String.downcase(&1.name)))
    |> Enum.take(10)
  end

  defp popularity(name), do: Enum.find_index(@popular_banks, &String.starts_with?(name, &1)) || length(@popular_banks)
end
