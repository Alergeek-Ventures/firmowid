defmodule FirmowidWeb.Organization.Views.Index do
  @moduledoc """
  Onboarding of an account without a company to work in, or with one more to add.

  An owner builds the company card in three steps: the path, the NIP with the
  register data it finds, and the industry, hourly billing and VAT status. Creating
  the company switches to it and continues with the first steps (KSeF, bank). An
  employee joins with an invite code instead.

  An admin who goes back from the first steps edits the company they are setting up
  in the same two steps, instead of creating another one.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Inputs
  import FirmowidUI.Components.Link
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import FirmowidWeb.Organization.Components.CompanyCard
  import FirmowidWeb.Organization.Components.OnboardingHeader
  import FirmowidWeb.Organization.Components.OnboardingStep
  import Phoenix.Component, except: [link: 1]

  alias Ash.Error.Invalid
  alias Firmowid.Analysis.IndustryTemplate
  alias Firmowid.Core
  alias Firmowid.Core.Nip
  alias Firmowid.Core.Organization
  alias FirmowidWeb.Analysis.Utilities.Industry
  alias FirmowidWeb.Auth.Utilities.PendingAuthorization
  alias FirmowidWeb.Infrastructure.Hooks.RequireOrganization
  alias FirmowidWeb.Infrastructure.UserAuth
  alias FirmowidWeb.Invoicing.Utilities.VatExemption
  alias FirmowidWeb.Organization.Utilities.Navigation, as: OrganizationNavigation
  alias Phoenix.LiveView.Socket

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen w-full bg-grey-100">
      <div class="mx-auto flex max-w-7xl flex-col gap-4 px-4 pb-8 sm:px-8 lg:px-20 lg:pb-10">
        <.onboarding_header
          exit_path={@exit_path}
          back={back_path(@step, @organization)}
          step={step_number(@step)}
          connecting_client={@connecting_client}
        />

        <div class="grid items-start gap-10 lg:grid-cols-[minmax(0,1fr)_26rem] lg:gap-16">
          <%!-- The card stays under the header while the steps beside it scroll. --%>
          <div class="order-2 lg:sticky lg:top-28 lg:order-1 lg:pt-2">
            <.card_for_step {assigns} />
          </div>
          <section class="order-1 lg:order-2" aria-live="polite">
            <.onboarding_step id={"step-#{@step}"}>
              <.step_panel {assigns} />
            </.onboarding_step>
          </section>
        </div>
      </div>
    </div>
    <.form
      for={%{}}
      id="switch-organization-form"
      action={~p"/organizacja/przelacz"}
      phx-trigger-action={not is_nil(@switch_to)}
    >
      <input type="hidden" name="organizacja" value={@switch_to} />
      <input type="hidden" name="cel" value={@switch_target} />
    </.form>
    """
  end

  # ── Card ─────────────────────────────────────────────────────────────

  defp card_for_step(%{step: :dolacz} = assigns) do
    ~H"""
    <.company_card
      id="company-card"
      name={@invite && @invite.organization_name}
      rows={invite_rows(@invite)}
    >
      <:stamps :let={card}>
        <.stamp
          :if={@invite}
          card={card}
          text={gettext("INVITATION")}
          icon={:users}
          rotate={-7}
          pressed
        />
      </:stamps>
    </.company_card>
    """
  end

  defp card_for_step(assigns) do
    ~H"""
    <.company_card
      id="company-card"
      name={@company && @company.name}
      rows={company_rows(@company, @step, @organization)}
    >
      <:stamps :let={card}>
        <%!-- The industry is stamped once confirmed, also for a company being edited. --%>
        <%= if @step == :branza and not is_nil(@industry) do %>
          <.stamp
            card={card}
            text={billing_stamp_text(@industry, @bills_hourly)}
            icon={billing_icon(@bills_hourly)}
            rotate={-9}
            pressed
          />
        <% else %>
          <.stamp_slot label={gettext("Industry")} hint={gettext("step %{number}", number: 3)} />
        <% end %>
        <.stamp_slot label="KSeF" hint={gettext("step %{number}", number: 4)} />
        <.stamp_slot label={gettext("Bank")} hint={gettext("step %{number}", number: 5)} />
      </:stamps>
    </.company_card>
    """
  end

  # ── Step panels ──────────────────────────────────────────────────────

  defp step_panel(%{step: :start} = assigns) do
    ~H"""
    <h1 class="text-2xl/tight font-semibold tracking-tight text-balance text-grey-900 sm:text-[2.625rem]/[1.1]">
      <%= if @current_user.member do %>
        {gettext("Add another company.")}
      <% else %>
        {gettext("Welcome to Firmowid.")}
      <% end %>
    </h1>
    <p class="mt-4 text-[1.0625rem]/relaxed text-grey-700">
      <%= if @connecting_client do %>
        {gettext(
          "Set up your company to use Firmowid in %{client}. Every step stamps the company card, and after five steps you will approve the connection and return to %{client}.",
          client: @connecting_client
        )}
      <% else %>
        {gettext(
          "We will start with your company card. Every step stamps it, and after five steps the company is ready to issue invoices."
        )}
      <% end %>
    </p>
    <div class="mt-9 grid gap-3">
      <.choice
        id="choose-owner"
        patch={OrganizationNavigation.onboarding_path(:firma)}
        icon="building-2"
        title={gettext("I am setting up my company")}
        description={gettext("I run the company or handle its administration")}
        primary
      />
      <.choice
        id="choose-employee"
        patch={OrganizationNavigation.onboarding_path(:dolacz)}
        icon="users"
        title={gettext("I am joining a team")}
        description={gettext("I have an invite code from my employer")}
      />
    </div>
    """
  end

  defp step_panel(%{step: :firma} = assigns) do
    ~H"""
    <h1 class="text-2xl/tight font-semibold tracking-tight text-balance text-grey-900 sm:text-[2.625rem]/[1.1]">
      <%= if @organization do %>
        {gettext("Check the company details.")}
      <% else %>
        {gettext("Enter the NIP, we will find the rest.")}
      <% end %>
    </h1>
    <.form
      for={%{}}
      id="company-form"
      phx-change="company_changed"
      phx-submit="company_confirmed"
      class="mt-7"
    >
      <.label for="company-nip" class="mb-2 text-sm text-grey-700">{gettext("Company NIP")}</.label>
      <div class="relative">
        <input
          id="company-nip"
          name="nip"
          value={@nip}
          inputmode="numeric"
          autocomplete="off"
          phx-debounce="300"
          aria-invalid={to_string(Map.has_key?(@errors, :nip))}
          class="h-16 w-full rounded-xl border-2 border-black bg-white px-5 text-2xl font-medium tracking-[.06em] text-grey-900 tabular-nums focus:border-black focus:ring-0 aria-invalid:border-brick-700"
        />
        <span class="absolute inset-y-0 right-5 flex items-center gap-1.5 text-sm font-medium">
          <%= case @lookup do %>
            <% :loading -> %>
              <span class="size-4 rounded-full border-2 border-moss-200 border-t-moss-800 motion-safe:animate-spin"></span>
              <span class="text-grey-600">{gettext("searching")}</span>
            <% :found -> %>
              <Lucideicons.check class="size-4 text-moss-700" aria-hidden="true" />
              <span class="text-moss-800">{gettext("found")}</span>
            <% _other -> %>
          <% end %>
        </span>
      </div>
      <.field_error :if={@errors[:nip]} message={@errors[:nip]} />

      <.button
        :if={@lookup == :found and not @manual?}
        id="edit-company-manually"
        type="button"
        variant="unstyled"
        phx-click="edit_manually"
        class="mt-4 text-[1.0625rem] font-medium text-grey-900 underline underline-offset-4 hover:text-black"
      >
        {gettext("Correct the details")}
      </.button>
      <p :if={@lookup == :not_found} class="mt-4 text-[1.0625rem]/relaxed text-grey-700">
        {gettext("The VAT white list does not know this NIP. Enter the company details yourself.")}
      </p>
      <p :if={@lookup == :failed} class="mt-4 text-[1.0625rem]/relaxed text-grey-700">
        {gettext("We could not reach the VAT white list. Enter the company details yourself.")}
      </p>

      <div :if={@manual?} class="mt-5 grid gap-4">
        <.input
          id="company-name"
          name="name"
          value={@company && @company.name}
          label={gettext("Company name")}
          errors={List.wrap(@errors[:name])}
        />
        <.input
          id="company-address"
          name="address"
          value={@company && @company.address}
          label={gettext("Business address")}
          placeholder={gettext("Street and number, postal code and city")}
          errors={List.wrap(@errors[:address])}
        />
      </div>

      <div :if={@company} class="mt-5">
        <.input
          id="company-display-name"
          name="display_name"
          value={@display_name}
          label={gettext("Name in the app")}
        />
        <p class="mt-1.5 text-sm text-grey-600">
          {gettext("Invoices keep the full name from the register.")}
        </p>
      </div>

      <%!-- The owner's name belongs to their member, which the company details do not change. --%>
      <div :if={is_nil(@organization)} class="mt-5">
        <.input
          id="owner-name"
          name="owner_name"
          value={@owner_name}
          label={gettext("Your full name")}
          autocomplete="name"
          errors={List.wrap(@errors[:owner_name])}
        />
      </div>

      <.primary_action
        id="confirm-company"
        title={gettext("This is my company")}
        hint={gettext("We will put the details on the card")}
        disabled={@lookup == :loading or is_nil(@company)}
      />
    </.form>
    """
  end

  defp step_panel(%{step: :branza} = assigns) do
    ~H"""
    <h1 class="text-2xl/tight font-semibold tracking-tight text-balance text-grey-900 sm:text-[2.375rem]/[1.1]">
      {gettext("What does your company do?")}
    </h1>
    <p class="mt-3 text-[1.0625rem]/relaxed text-grey-700">
      {gettext("Firmowid adapts to your industry. You can change it later in the company settings.")}
    </p>
    <.form
      for={%{}}
      id="industry-form"
      phx-change="industry_changed"
      phx-submit={if @organization, do: "update", else: "create"}
      class="mt-5"
    >
      <fieldset>
        <legend class="sr-only">{gettext("Industry")}</legend>
        <div class="grid gap-2">
          <.option
            :for={{label, industry} <- Industry.options()}
            name="industry"
            value={industry}
            checked={@industry == industry}
            title={label}
            icon={Industry.icon(industry)}
            description={Industry.description(industry)}
            note={
              @company.pkd && @company.suggested_industry == industry &&
                gettext("matches PKD %{code}", code: @company.pkd)
            }
          />
        </div>
      </fieldset>

      <fieldset class="mt-6">
        <legend class="text-[1.0625rem] font-medium text-grey-900">
          {gettext("Do you bill clients by the hour?")}
        </legend>
        <div class="mt-2.5 grid gap-2">
          <.option
            name="bills_hourly"
            value="true"
            checked={@bills_hourly == true}
            title={gettext("Yes, I sell hours of work")}
            description={
              gettext(
                "We will turn on time tracking and projects with an hours budget, and show revenue per hour."
              )
            }
          />
          <.option
            name="bills_hourly"
            value="false"
            checked={@bills_hourly == false}
            title={gettext("No, a flat fee or selling goods")}
            description={gettext("You can turn time tracking on later in the company settings.")}
          />
        </div>
      </fieldset>

      <fieldset class="mt-6">
        <legend class="text-[1.0625rem] font-medium text-grey-900">{gettext("VAT")}</legend>
        <div class="mt-2.5 grid grid-cols-2 gap-1 rounded-xl border border-grey-300 bg-white p-1 text-sm">
          <label class="cursor-pointer rounded-lg p-2 text-center has-checked:bg-grey-700 has-checked:text-white has-focus-visible:outline-2 has-focus-visible:outline-black">
            <input type="radio" name="vat_payer" value="true" checked={@vat_payer} class="sr-only" />
            {gettext("Active VAT payer")}
          </label>
          <label class="cursor-pointer rounded-lg p-2 text-center has-checked:bg-grey-700 has-checked:text-white has-focus-visible:outline-2 has-focus-visible:outline-black">
            <input
              type="radio"
              name="vat_payer"
              value="false"
              checked={not @vat_payer}
              class="sr-only"
            />
            {gettext("Exempt from VAT")}
          </label>
        </div>
        <div :if={not @vat_payer} class="mt-3 grid gap-3">
          <.input
            id="vat-exemption-type"
            type="select"
            name="vat_exemption_type"
            value={@vat_exemption_type}
            options={VatExemption.options()}
            label={gettext("VAT exemption")}
          />
          <.input
            :if={@vat_exemption_type == "other"}
            id="vat-exemption-basis"
            name="vat_exemption_basis"
            value={@vat_exemption_basis}
            label={gettext("Legal basis for the VAT exemption")}
          />
        </div>
      </fieldset>

      <div
        :if={@create_errors != []}
        class="mt-5 rounded-lg bg-brick-100 px-4 py-3 text-sm text-brick-800"
        role="alert"
      >
        <p class="font-medium">
          <%= if @organization do %>
            {gettext("We could not save the company.")}
          <% else %>
            {gettext("We could not create the company.")}
          <% end %>
        </p>
        <ul class="mt-1 list-disc pl-5">
          <li :for={message <- @create_errors}>{message}</li>
        </ul>
      </div>

      <.primary_action
        id="create-company"
        title={gettext("Stamp it")}
        hint={gettext("Next: connecting KSeF")}
        disabled={is_nil(@industry) or is_nil(@bills_hourly) or not is_nil(@switch_to)}
      />
    </.form>
    """
  end

  defp step_panel(%{step: :dolacz} = assigns) do
    ~H"""
    <h1 class="text-2xl/tight font-semibold tracking-tight text-balance text-grey-900 sm:text-[2.625rem]/[1.1]">
      {gettext("Join your team.")}
    </h1>
    <p class="mt-4 text-[1.0625rem]/relaxed text-grey-700">
      <%= if @invite do %>
        {gettext("%{company} invites you to its team.",
          company: @invite.organization_name
        )}
      <% else %>
        {gettext("Enter the invite code you got from your employer.")}
      <% end %>
      {gettext("Enter the full name you will sign your hours and leave requests with.")}
    </p>
    <.form
      for={@join_form}
      id="join_form"
      phx-change="invite_changed"
      phx-submit="join"
      class="mt-7 grid gap-4"
    >
      <.input
        field={@join_form[:code]}
        type="text"
        label={gettext("Invitation code")}
        autocomplete="off"
        phx-debounce="300"
      />
      <.input field={@join_form[:name]} type="text" label={gettext("Full name")} autocomplete="name" />
      <.primary_action
        id="join-team"
        title={gettext("Join the team")}
        hint={gettext("You will see your hours record right away")}
        class="mt-2"
      />
    </.form>
    """
  end

  # ── Building blocks ──────────────────────────────────────────────────

  defp back_path(:start, _organization), do: nil
  defp back_path(:branza, _organization), do: OrganizationNavigation.onboarding_path(:firma)
  # The company being edited exists already, so there is no path to choose any more.
  defp back_path(:firma, %Organization{}), do: nil
  defp back_path(_firma_or_dolacz, _organization), do: OrganizationNavigation.onboarding_path()

  defp step_number(:start), do: 1
  defp step_number(:firma), do: 2
  defp step_number(:branza), do: 3
  defp step_number(:dolacz), do: nil

  attr :id, :string, required: true
  attr :patch, :string, required: true
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :primary, :boolean, default: false

  defp choice(assigns) do
    ~H"""
    <.link
      id={@id}
      kind="unstyled"
      patch={@patch}
      class={[
        "group flex items-center gap-4 rounded-2xl border bg-white px-6 py-5 transition-colors hover:border-black focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-black",
        if(@primary,
          do: "border-2 border-black shadow-[0_18px_36px_-24px_rgba(0,0,0,.5)]",
          else: "border-grey-300"
        )
      ]}
    >
      <span class="grid size-11 shrink-0 place-items-center rounded-xl bg-grey-100 text-grey-900">
        <Lucideicons.render! name={@icon} class="size-5" aria-hidden="true" />
      </span>
      <span class="min-w-0 flex-1">
        <span class="block text-lg font-medium text-grey-900">{@title}</span>
        <span class="mt-0.5 block text-sm text-grey-600">{@description}</span>
      </span>
      <Lucideicons.arrow_right
        class="size-5 shrink-0 text-grey-900 transition-transform group-hover:translate-x-0.5"
        aria-hidden="true"
      />
    </.link>
    """
  end

  attr :name, :string, required: true
  attr :value, :string, required: true
  attr :checked, :boolean, required: true
  attr :title, :string, required: true
  attr :icon, :string, default: nil, doc: "a Lucide icon name shown at the end of the option"
  attr :description, :string, required: true

  attr :note, :any,
    default: nil,
    doc: "a short remark beside the title, such as why the option is suggested"

  defp option(assigns) do
    ~H"""
    <label class="flex cursor-pointer items-center gap-3.5 rounded-xl border border-grey-300 bg-white px-4.5 py-3.5 has-checked:border-2 has-checked:border-black has-checked:px-4.25 has-checked:py-3.25 has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-black">
      <input type="radio" name={@name} value={@value} checked={@checked} class="peer sr-only" />
      <span class="size-4.5 shrink-0 rounded-full border-[1.5px] border-grey-400 peer-checked:border-[5px] peer-checked:border-black"></span>
      <span class="min-w-0 flex-1">
        <span class="flex flex-wrap items-baseline gap-x-2 gap-y-0.5">
          <span class="text-[0.9375rem] text-grey-900">{@title}</span>
          <span :if={@note} class="text-xs font-medium text-moss-700">{@note}</span>
        </span>
        <span class="mt-0.5 block text-[0.8125rem] text-grey-600">{@description}</span>
      </span>
      <span
        :if={@icon}
        class="grid size-9 shrink-0 place-items-center rounded-lg bg-grey-100 text-grey-900"
      >
        <Lucideicons.render! name={@icon} class="size-4.5" aria-hidden="true" />
      </span>
    </label>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, required: true
  attr :disabled, :boolean, default: false
  attr :class, :any, default: nil

  defp primary_action(assigns) do
    ~H"""
    <.button
      id={@id}
      type="submit"
      variant="unstyled"
      disabled={@disabled}
      phx-disable-with
      class={[
        "mt-6 flex w-full items-center gap-4 rounded-xl bg-black px-5.5 py-4 text-left text-white shadow-[0_18px_36px_-20px_rgba(0,0,0,.6)] transition-colors hover:bg-grey-800 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-black disabled:cursor-not-allowed disabled:opacity-60 phx-submit-loading:opacity-75",
        @class
      ]}
    >
      <span class="flex-1">
        <span class="block text-lg font-medium">{@title}</span>
        <span class="block text-sm text-white/65">{@hint}</span>
      </span>
      <Lucideicons.arrow_right class="size-5" aria-hidden="true" />
    </.button>
    """
  end

  attr :message, :string, required: true

  defp field_error(assigns) do
    ~H"""
    <p class="mt-2 flex items-center gap-1.5 text-sm text-brick-700">
      <Lucideicons.circle_alert class="size-4" aria-hidden="true" />
      {@message}
    </p>
    """
  end

  # ── Params and lifecycle ─────────────────────────────────────────────

  @impl true
  def mount(_params, session, socket) do
    # Without the flag the user keeps the organization form from before the wizard.
    if flag_enabled?(:inbox, socket.assigns) do
      mount_wizard(assign(socket, :connecting_client, PendingAuthorization.client_name(session)))
    else
      {:ok, push_navigate(socket, to: OrganizationNavigation.legacy_form_path())}
    end
  end

  defp mount_wizard(socket) do
    user = socket.assigns.current_user
    # A user adding another company is prefilled with the name they use in the current one.
    name = if user.member, do: user.member.name, else: ""

    organization = organization_in_onboarding(socket.assigns)

    {:ok,
     socket
     |> assign(
       # The wizard is a page of its own, without the app navigation.
       focused: true,
       no_padding: true,
       organization: organization,
       # Until the first steps are done every page leads back to them, so the way out is logging out.
       exit_path:
         if(user.member && is_nil(organization),
           do: UserAuth.signed_in_path_for_user(user, user.member.organization_id)
         ),
       page_title: gettext("Set up your company"),
       switch_to: nil,
       switch_target: nil,
       nip: "",
       lookup: :idle,
       company: nil,
       manual?: false,
       owner_name: name,
       display_name: "",
       errors: %{},
       industry: nil,
       bills_hourly: nil,
       vat_payer: true,
       vat_exemption_type: nil,
       vat_exemption_basis: nil,
       create_errors: [],
       invite: nil,
       join_form: to_form(%{"name" => name, "code" => ""})
     )
     |> assign_organization(organization)
     |> guard_organization(organization)}
  end

  # The admin of a company still before its first steps is setting that company up,
  # so coming back here edits it. A member of a working company adds another one.
  defp organization_in_onboarding(%{current_user: user, current_org: organization}) do
    if UserAuth.first_steps_pending?(user, organization), do: organization
  end

  defp organization_in_onboarding(_no_organization), do: nil

  # Editing the company acts on it, so every event checks the admin still belongs to it.
  defp guard_organization(socket, nil), do: socket

  defp guard_organization(socket, _organization), do: RequireOrganization.attach_access_hook(socket, :ash_scope)

  defp assign_organization(socket, nil), do: socket

  defp assign_organization(socket, organization) do
    assign(socket,
      nip: organization.nip,
      company: %{
        blank_company(organization.nip)
        | name: organization.name,
          address: organization.address,
          vat_payer?: organization.is_vat_payer
      },
      manual?: true,
      display_name: organization.display_name,
      industry: organization.industry,
      bills_hourly: organization.bills_hourly,
      vat_payer: organization.is_vat_payer,
      vat_exemption_type: organization.vat_exemption_type && Atom.to_string(organization.vat_exemption_type),
      vat_exemption_basis: organization.vat_exemption_basis
    )
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case {params["krok"], socket.assigns.company} do
      {krok, _company}
      when krok not in ["firma", "branza"] and not is_nil(socket.assigns.organization) ->
        {:noreply, push_patch(socket, to: OrganizationNavigation.onboarding_path(:firma), replace: true)}

      {"firma", _company} ->
        {:noreply, assign(socket, :step, :firma)}

      {"branza", nil} ->
        {
          :noreply,
          push_patch(socket, to: OrganizationNavigation.onboarding_path(:firma), replace: true)
        }

      {"branza", _company} ->
        {:noreply, assign(socket, :step, :branza)}

      {"dolacz", _company} ->
        {:noreply, assign(socket, :step, :dolacz)}

      _start ->
        {:noreply, assign(socket, :step, :start)}
    end
  end

  # ── NIP and company details ──────────────────────────────────────────

  @impl true
  def handle_event("company_changed", params, socket) do
    nip = Nip.normalize_digits(params["nip"] || "")

    socket =
      socket
      |> assign(
        nip: params["nip"],
        owner_name: params["owner_name"] || socket.assigns.owner_name,
        display_name: params["display_name"] || socket.assigns.display_name
      )
      |> update_manual_details(params)

    {:noreply, maybe_look_up(socket, nip)}
  end

  def handle_event("edit_manually", _params, socket) do
    {:noreply, assign(socket, :manual?, true)}
  end

  def handle_event("company_confirmed", params, socket) do
    socket =
      socket
      |> assign(
        owner_name: params["owner_name"] || socket.assigns.owner_name,
        display_name: params["display_name"] || ""
      )
      |> update_manual_details(params)

    errors = company_errors(socket.assigns)

    if errors == %{} do
      {:noreply,
       socket
       |> assign(errors: %{})
       |> assign_industry_defaults()
       |> push_patch(to: OrganizationNavigation.onboarding_path(:branza))}
    else
      {:noreply, assign(socket, :errors, errors)}
    end
  end

  # ── Industry, billing and VAT ────────────────────────────────────────

  def handle_event("industry_changed", params, socket) do
    {:noreply, assign_industry_params(socket, params)}
  end

  def handle_event("create", params, socket) do
    socket = assign_industry_params(socket, params)

    attrs =
      Map.merge(organization_attrs(socket.assigns), %{
        # The owner goes on to the first steps, which every page leads back to until done.
        start_onboarding: true,
        owner_name: String.trim(socket.assigns.owner_name)
      })

    case Core.create_organization(attrs, actor: socket.assigns.current_user) do
      {:ok, organization} ->
        {:noreply,
         assign(socket,
           switch_to: organization.id,
           switch_target: OrganizationNavigation.first_steps_target()
         )}

      {:error, %Invalid{} = error} ->
        {:noreply, assign(socket, :create_errors, Enum.map(error.errors, &Exception.message/1))}
    end
  end

  def handle_event("update", params, socket) do
    socket = assign_industry_params(socket, params)
    %{organization: organization, ash_scope: scope} = socket.assigns

    case Core.update_basic_info(organization, organization_attrs(socket.assigns), scope: scope) do
      {:ok, _organization} ->
        {:noreply, redirect(socket, to: OrganizationNavigation.first_steps_path(:ksef))}

      {:error, %Invalid{} = error} ->
        {:noreply, assign(socket, :create_errors, Enum.map(error.errors, &Exception.message/1))}
    end
  end

  # ── Joining with an invite code ──────────────────────────────────────

  def handle_event("invite_changed", %{"code" => code, "name" => name}, socket) do
    {:noreply,
     assign(socket,
       join_form: to_form(%{"name" => name, "code" => code}),
       invite: find_invite(code, socket.assigns.current_user)
     )}
  end

  def handle_event("join", %{"code" => invite_code, "name" => name}, socket) do
    join(invite_code, name, socket)
  end

  @impl true
  # The NIP was shortened or broken while the lookup ran, so its result no longer applies.
  def handle_async(:look_up, _result, %{assigns: %{lookup: lookup}} = socket) when lookup != :loading do
    {:noreply, socket}
  end

  def handle_async(:look_up, {:ok, {:ok, nil}}, socket) do
    {:noreply, assign(socket, lookup: :not_found, manual?: true, company: blank_company(socket.assigns.nip))}
  end

  def handle_async(:look_up, {:ok, {:ok, found}}, socket) do
    company = %{
      nip: found.nip,
      name: found.name,
      address: found.address,
      pkd: found.pkd,
      pkd_name: found.pkd_name,
      suggested_industry: found.industry,
      vat_payer?: found.vat_payer?,
      fresh?: true
    }

    {:noreply,
     assign(socket,
       lookup: :found,
       manual?: false,
       company: company,
       display_name: suggested_display_name(found.name),
       errors: %{}
     )}
  end

  # The lookup only saves typing: when the white list is unreachable, the owner enters the details.
  def handle_async(:look_up, _failed, socket) do
    {:noreply, assign(socket, lookup: :failed, manual?: true, company: blank_company(socket.assigns.nip))}
  end

  defp maybe_look_up(socket, nip) do
    looked_up = socket.assigns.company && socket.assigns.company.nip

    cond do
      String.length(nip) < 10 ->
        assign(socket,
          lookup: :idle,
          company: nil,
          manual?: false,
          errors: Map.delete(socket.assigns.errors, :nip)
        )

      not Nip.valid?(nip) ->
        assign(socket,
          lookup: :idle,
          company: nil,
          manual?: false,
          errors: %{nip: gettext("This NIP has a wrong check digit.")}
        )

      nip == looked_up ->
        socket

      true ->
        user = socket.assigns.current_user

        socket
        |> assign(lookup: :loading, company: nil, errors: %{})
        |> start_async(:look_up, fn -> Core.look_up_company(nip, actor: user) end)
    end
  end

  defp organization_attrs(assigns) do
    %{
      name: assigns.company.name,
      nip: Nip.normalize_digits(assigns.company.nip),
      address: assigns.company.address,
      display_name: assigns.display_name,
      industry: assigns.industry,
      bills_hourly: assigns.bills_hourly,
      is_vat_payer: assigns.vat_payer,
      vat_exemption_type: assigns.vat_exemption_type,
      vat_exemption_basis: assigns.vat_exemption_basis
    }
  end

  defp update_manual_details(%{assigns: %{manual?: true, company: %{} = company}} = socket, params) do
    company = %{
      company
      | name: params["name"] || company.name,
        address: params["address"] || company.address,
        fresh?: false
    }

    assign(socket, :company, company)
  end

  defp update_manual_details(socket, _params), do: socket

  defp company_errors(%{company: company, owner_name: owner_name, nip: nip}) do
    []
    |> add_error(
      :nip,
      not Nip.valid?(Nip.normalize_digits(nip || "")),
      gettext("Enter a valid NIP.")
    )
    |> add_error(
      :name,
      is_nil(company) or blank?(company.name),
      gettext("Enter the company name.")
    )
    |> add_error(
      :address,
      is_nil(company) or blank?(company.address),
      gettext("Enter the business address.")
    )
    |> add_error(:owner_name, blank?(owner_name), gettext("Enter your full name."))
    |> Map.new()
  end

  defp add_error(errors, field, true, message), do: [{field, message} | errors]
  defp add_error(errors, _field, false, _message), do: errors

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""

  defp blank_company(nip) do
    %{
      nip: Nip.normalize_digits(nip || ""),
      name: nil,
      address: nil,
      pkd: nil,
      pkd_name: nil,
      suggested_industry: nil,
      vat_payer?: true,
      fresh?: false
    }
  end

  # The PKD suggests the industry, the industry suggests hourly billing, and the
  # white list knows the VAT status; the owner can change each of them.
  defp assign_industry_defaults(%{assigns: %{industry: nil, company: company}} = socket) do
    industry = company.suggested_industry || :services

    assign(socket,
      industry: industry,
      bills_hourly: industry == :services,
      vat_payer: company.vat_payer?
    )
  end

  defp assign_industry_defaults(socket), do: socket

  defp assign_industry_params(socket, params) do
    exemption = if params["vat_payer"] == "false", do: params["vat_exemption_type"] || "art_113"

    assign(socket,
      industry: parse_industry(params["industry"]) || socket.assigns.industry,
      bills_hourly: parse_boolean(params["bills_hourly"], socket.assigns.bills_hourly),
      vat_payer: parse_boolean(params["vat_payer"], socket.assigns.vat_payer),
      vat_exemption_type: exemption,
      vat_exemption_basis: params["vat_exemption_basis"]
    )
  end

  defp parse_industry(value), do: Enum.find(IndustryTemplate.industries(), &(Atom.to_string(&1) == value))

  defp parse_boolean("true", _default), do: true
  defp parse_boolean("false", _default), do: false
  defp parse_boolean(_value, default), do: default

  # ── Card content ─────────────────────────────────────────────────────

  defp company_rows(nil, _step, _organization) do
    [
      %{label: "NIP", value: nil},
      %{label: gettext("Address"), value: nil},
      %{label: "PKD", value: nil},
      %{label: "VAT", value: nil}
    ]
  end

  defp company_rows(company, step, organization) do
    fresh? = company.fresh? and step == :firma

    rows = [
      %{label: "NIP", value: format_nip(Nip.normalize_digits(company.nip)), fresh: fresh?},
      %{label: gettext("Address"), value: company.address, fresh: fresh?},
      %{
        label: "PKD",
        value: company.pkd && "#{company.pkd} · #{company.pkd_name}",
        fresh: fresh?
      },
      %{label: "VAT", value: vat_label(company.vat_payer?), fresh: fresh?}
    ]

    # The company keeps no PKD, so the one being edited shows the rows it has, as on the first steps.
    if organization, do: Enum.reject(rows, &(&1.label == "PKD" and is_nil(&1.value))), else: rows
  end

  defp invite_rows(nil), do: [%{label: gettext("Role"), value: nil}, %{label: gettext("Code valid until"), value: nil}]

  defp invite_rows(invite) do
    [
      %{label: gettext("Role"), value: Firmowid.Core.UserRole.label(invite.role)},
      %{
        label: gettext("Code valid until"),
        value: Calendar.strftime(invite.expires_at, "%d.%m.%Y")
      }
    ]
  end

  defp vat_label(true), do: gettext("Active VAT payer")
  defp vat_label(false), do: gettext("Exempt from VAT")

  # ── Invites ──────────────────────────────────────────────────────────

  defp find_invite(code, user) do
    case String.trim(code || "") do
      "" ->
        nil

      code ->
        %{invite_code: code}
        |> Core.query_to_read_invite_by_code(actor: user)
        |> Ash.read_one!(actor: user, load: [:organization_name])
    end
  end

  @doc "Joins the company of an invite code; the organization form from before the wizard shares it."
  @spec join(String.t(), String.t(), Socket.t()) :: {:noreply, Socket.t()}
  def join(invite_code, name, socket) do
    user = socket.assigns.current_user
    Logger.metadata(user_id: user.id)

    case find_invite(invite_code, user) do
      nil ->
        join_form =
          to_form(%{"name" => name, "code" => invite_code},
            errors: [code: {gettext("This invite code is invalid or has expired."), []}]
          )

        {:noreply, assign(socket, :join_form, join_form)}

      invite ->
        consume_invite(invite, invite_code, name, socket)
    end
  end

  defp consume_invite(invite, invite_code, name, socket) do
    user = socket.assigns.current_user
    Logger.metadata(user_id: user.id, organization_id: invite.organization_id)

    case Core.consume_invite(invite, %{name: name}, tenant: invite.organization_id, actor: user) do
      {:ok, invite} ->
        {:noreply, assign(socket, :switch_to, invite.organization_id)}

      {:error,
       %Invalid{
         errors: [%Ash.Error.Changes.InvalidChanges{fields: [:organization_id], message: message}]
       }} ->
        join_form =
          to_form(%{"name" => name, "code" => invite_code}, errors: [code: {message, []}])

        {:noreply, assign(socket, :join_form, join_form)}

      {:error, %Invalid{errors: [%Ash.Error.Changes.Required{field: :name}]}} ->
        join_form =
          to_form(%{"name" => name, "code" => invite_code},
            errors: [name: {gettext("Enter your full name."), []}]
          )

        {:noreply, assign(socket, :join_form, join_form)}

      {:error, error} ->
        raise error
    end
  end
end
