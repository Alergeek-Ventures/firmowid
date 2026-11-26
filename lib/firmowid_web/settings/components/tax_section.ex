defmodule FirmowidWeb.Settings.Components.TaxSection do
  @moduledoc """
  The "Taxes and ZUS" card of the company settings: the legal form, and for the
  selected tax year the VAT period, the owners' income tax and ZUS or the CIT of a
  limited company, and the accident insurance rate.

  The component owns the selected year and its form; a year without a record is
  created on save. The legal form belongs to the organization, so the page saves
  it (`set_legal_form`) and passes the organization back in, which rebuilds the
  form for the new form's partners. Only admins reach the company settings.

  Settings that the transfers to the tax office suggest and the year still lacks
  or contradicts (`Taxes.pending_suggestions/3`) are preselected; saving the year
  confirms them. A prefilled setting the year lacks is marked quietly as based on
  the transactions; one that contradicts the saved value says what is saved under the
  field, and a line under the description lists every difference. The submit button
  then reads "Confirm".
  """
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [attach_access_hook: 2]

  alias Firmowid.Core
  alias Firmowid.LocalDate
  alias Firmowid.Taxes
  alias Firmowid.Taxes.Partner
  alias Firmowid.Taxes.TaxYear
  alias FirmowidWeb.Inbox.Components.SidebarNav
  alias FirmowidWeb.Settings.Components.TaxDifferences
  alias FirmowidWeb.Settings.Utilities.TaxSettings
  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField

  @impl true
  def mount(socket), do: {:ok, attach_access_hook(socket, :scope)}

  @impl true
  def update(assigns, socket) do
    previous_organization = socket.assigns[:organization]
    socket = assign(socket, assigns)

    cond do
      is_nil(previous_organization) ->
        {:ok, load_year(socket, LocalDate.today().year)}

      previous_organization.legal_form != assigns.organization.legal_form ->
        {:ok, assign_form(socket)}

      true ->
        {:ok, socket}
    end
  end

  @impl true
  def handle_event("select_year", %{"year" => year}, socket) do
    {:noreply, load_year(socket, String.to_integer(year))}
  end

  def handle_event("validate", %{"tax_year" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"tax_year" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _tax_year} ->
        LiveToast.send_toast(:success, gettext("Changes saved"))
        # The inbox counts a missing tax profile, so its badge follows the save.
        send_update(SidebarNav, id: SidebarNav.id(), refresh: true)
        {:noreply, load_year(socket, socket.assigns.year)}

      # Some errors belong to fields this form does not show, e.g. after another tab
      # changed the legal form, so the save failing is always said out loud.
      {:error, form} ->
        LiveToast.send_toast(
          :error,
          gettext("Could not save the changes. Refresh the page and try again.")
        )

        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("add_partner", _params, socket) do
    form =
      AshPhoenix.Form.add_form(socket.assigns.form, :partners, params: blank_partner(:civil_partnership))

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("remove_partner", %{"path" => path}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.remove_form(socket.assigns.form, path))}
  end

  # The switcher offers the years that have a record and always the current one.
  defp load_year(socket, year) do
    tax_years =
      Taxes.list_tax_years!(%{},
        load: [partners: Ash.Query.sort(Partner, :id)],
        scope: socket.assigns.scope
      )

    years = Enum.sort(Enum.uniq([LocalDate.today().year | Enum.map(tax_years, & &1.year)]))

    socket
    |> assign(:years, years)
    |> assign(:year, year)
    |> assign(:suggestions, Taxes.suggest_tax_settings!(year, scope: socket.assigns.scope))
    |> assign(:tax_year, Enum.find(tax_years, &(&1.year == year)))
    |> assign_former_partners()
    |> assign_form()
  end

  # A partner who has left the team stays a choice in the years they were a partner in;
  # otherwise the person select would fall back to someone else.
  defp assign_former_partners(%{assigns: %{tax_year: nil}} = socket), do: assign(socket, :former_partners, [])

  defp assign_former_partners(socket) do
    %{tax_year: tax_year, members: members, scope: scope} = socket.assigns
    active = MapSet.new(members, & &1.member.id)

    left =
      for partner <- tax_year.partners,
          not MapSet.member?(active, partner.member_id),
          do: partner.member_id

    former_partners =
      if left == [],
        do: [],
        else:
          Enum.filter(
            Core.list_users!(%{status: :archived}, load: [:member], scope: scope),
            &(&1.member.id in left)
          )

    assign(socket, :former_partners, former_partners)
  end

  defp assign_form(%{assigns: %{organization: %{legal_form: nil}}} = socket),
    do: assign(socket, form: nil, suggested: %{}, saved: %{}, differences: [])

  defp assign_form(socket) do
    %{tax_year: tax_year, year: year, organization: organization, scope: scope} = socket.assigns
    suggestions = Taxes.pending_suggestions(socket.assigns.suggestions, tax_year, organization)
    partners = tax_year |> saved_partners() |> fit_partners(organization.legal_form)
    params = Enum.reduce(suggestions, %{"partners" => partners}, &put_suggestion(&2, &1))
    opts = [scope: scope, domain: Taxes, as: "tax_year", forms: [partners: partner_forms()]]

    form =
      case tax_year do
        nil ->
          AshPhoenix.Form.for_create(
            TaxYear,
            :create,
            [params: Map.put(params, "year", year)] ++ opts
          )

        tax_year ->
          AshPhoenix.Form.for_update(tax_year, :update, [params: params] ++ opts)
      end

    differences = TaxSettings.differences(suggestions, tax_year)

    socket
    |> assign(:form, to_form(form))
    |> assign(:suggested, Map.new(suggestions, &{&1.setting, &1.value}))
    |> assign(:saved, Map.new(differences, &{&1.setting, &1.saved}))
    |> assign(:differences, differences)
  end

  defp put_suggestion(params, %{setting: setting, value: value}) when setting in [:vat_period, :cit_advances],
    do: Map.put(params, to_string(setting), to_string(value))

  # The owner's suggestions (income tax, ZUS) apply only to a sole proprietorship, whose owner is the
  # only row.
  defp put_suggestion(%{"partners" => [owner]} = params, %{setting: setting, value: value}),
    do: Map.put(params, "partners", [Map.put(owner, to_string(setting), to_string(value))])

  # Every row is a create form: the tax year matches the partners it saves by member,
  # so a row whose person changes replaces that partner.
  defp partner_forms, do: [type: :list, resource: Partner, create_action: :create]

  defp saved_partners(nil), do: []

  defp saved_partners(tax_year) do
    Enum.map(tax_year.partners, fn partner ->
      %{
        "member_id" => partner.member_id,
        "profit_share" => to_string(partner.profit_share),
        "income_tax" => to_string(partner.income_tax),
        "lump_sum_rate" => to_string(partner.lump_sum_rate),
        "pit_advances" => to_string(partner.pit_advances),
        "social_insurance" => to_string(partner.social_insurance),
        "voluntary_sickness" => to_string(partner.voluntary_sickness)
      }
    end)
  end

  # The saved partners may come from another legal form; give the current one its rows.
  defp fit_partners(_partners, :limited_company), do: []

  defp fit_partners(partners, :sole_proprietorship),
    do: [Map.put(List.first(partners, blank_partner(:sole_proprietorship)), "profit_share", "100")]

  defp fit_partners(partners, :civil_partnership),
    do: partners ++ List.duplicate(blank_partner(:civil_partnership), max(2 - length(partners), 0))

  defp blank_partner(:sole_proprietorship), do: %{"profit_share" => "100", "voluntary_sickness" => "false"}

  defp blank_partner(:civil_partnership), do: %{"profit_share" => "", "voluntary_sickness" => "false"}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :legal_form, assigns.organization.legal_form)

    ~H"""
    <section id="podatki" class="flex scroll-mt-6 flex-col gap-6 rounded-md bg-white p-5">
      <div class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-2">
        <h2 class="text-lg font-semibold text-grey-900">{gettext("Taxes and ZUS")}</h2>
        <div
          :if={@legal_form}
          role="group"
          aria-label={gettext("Tax year")}
          class="flex gap-4 text-sm"
        >
          <.button
            :for={year <- @years}
            type="button"
            variant="unstyled"
            phx-click="select_year"
            phx-value-year={year}
            phx-target={@myself}
            aria-pressed={to_string(year == @year)}
            class={[
              "cursor-pointer border-b-2 pb-0.5 tabular-nums transition-colors",
              year == @year && "border-grey-900 font-medium text-grey-900",
              year != @year && "border-transparent text-grey-500 hover:text-grey-900"
            ]}
          >
            {year}
          </.button>
        </div>
      </div>
      <div class="-mt-4 flex flex-col gap-2 text-sm/snug text-grey-600">
        <p>
          {gettext(
            "We use these settings to work out how much you pay and when: ZUS and income tax advances by the 20th, VAT by the 25th of the month."
          )}
        </p>
        <%!-- Only for a year that has saved values the payments contradict. --%>
        <p :if={@form && @differences != []} id="tax-recommendation-summary">
          <TaxDifferences.list
            differences={@differences}
            lead={gettext("The transfers indicate different settings than the saved ones –")}
            highlight
            end_with="."
          />
          <span :if={holds_indicated?(@form, @differences)}>
            {gettext("The fields already hold the values from the transfers, confirm to save them.")}
          </span>
        </p>
      </div>

      <div class="grid grid-cols-[2.25rem_minmax(0,1fr)] items-baseline gap-y-8 sm:grid-cols-[2.25rem_11rem_minmax(0,1fr)]">
        <.rubric_label number={1} id="tax-legal-form-label">{gettext("Legal form")}</.rubric_label>
        <div class={["flex flex-col gap-3", answer_styles()]}>
          <.form for={%{}} id="tax-legal-form" phx-change="set_legal_form">
            <div
              role="radiogroup"
              aria-labelledby="tax-legal-form-label"
              class="flex flex-row flex-wrap items-baseline gap-x-8 gap-y-2"
            >
              <label :for={{value, label} <- legal_form_options()} class="cursor-pointer">
                <input
                  type="radio"
                  name="legal_form"
                  id={"tax-legal-form-#{value}"}
                  value={value}
                  checked={@legal_form == value}
                  class="peer sr-only"
                />
                <span class="inline-block border-b-2 border-transparent pb-1 text-2xl/tight font-medium text-grey-500 transition-colors duration-150 ease-out peer-checked:border-grey-900 peer-checked:text-black peer-focus-visible:outline-2 peer-focus-visible:outline-offset-4 peer-focus-visible:outline-(--focus-ring) peer-active:text-grey-900 hover:text-grey-800 peer-checked:hover:text-black">
                  {label}
                </span>
              </label>
            </div>
          </.form>
          <p :if={is_nil(@legal_form)} class="text-sm/snug text-grey-600">
            {gettext("Choose the legal form to set up the company's taxes and ZUS.")}
          </p>
        </div>

        <.year_form
          :if={@legal_form && @form}
          form={@form}
          organization={@organization}
          members={@members ++ @former_partners}
          suggested={@suggested}
          saved={@saved}
          confirm?={@differences != []}
          myself={@myself}
        />
      </div>
    </section>
    """
  end

  attr :form, Form, required: true
  attr :organization, :map, required: true
  attr :members, :list, required: true

  attr :suggested, :map,
    required: true,
    doc: "the preselected settings that the transfers suggest"

  attr :saved, :map,
    required: true,
    doc: "what the year has saved for the suggested settings that it contradicts"

  attr :confirm?, :boolean,
    required: true,
    doc: "whether saving confirms values that contradict the saved ones"

  attr :myself, :any, required: true

  # `contents` lets the form's rows join the section's rubric grid.
  defp year_form(assigns) do
    assigns =
      assigns
      |> assign(:legal_form, assigns.organization.legal_form)
      |> assign(:member_options, member_options(assigns.members))

    ~H"""
    <.form
      for={@form}
      id="tax-year-form"
      phx-change="validate"
      phx-submit="save"
      phx-target={@myself}
      class="contents"
    >
      <input
        :if={@form.source.type == :create}
        type="hidden"
        name={@form[:year].name}
        value={@form[:year].value}
      />

      <.rubric_label number={2} id="tax-vat-label">{gettext("VAT settlement")}</.rubric_label>
      <div :if={@organization.is_vat_payer} class={answer_styles()}>
        <.choice
          field={@form[:vat_period]}
          options={TaxSettings.period_options()}
          labelledby="tax-vat-label"
        />
        <.suggested
          field={@form[:vat_period]}
          setting={:vat_period}
          suggested={@suggested}
          saved={@saved}
        />
      </div>
      <div :if={!@organization.is_vat_payer} class={answer_styles()}>
        <input type="hidden" name={@form[:vat_period].name} value="" />
        <p class="text-sm/snug text-grey-600">{not_vat_payer_text()}</p>
      </div>

      <%= if @legal_form == :limited_company do %>
        <.rubric_label number={3} id="tax-cit-label">CIT</.rubric_label>
        <div class={["flex flex-wrap items-start gap-x-6 gap-y-3", answer_styles()]}>
          <.choice field={@form[:cit_rate]} options={cit_rate_options()} labelledby="tax-cit-label" />
          <div>
            <.choice
              field={@form[:cit_advances]}
              options={TaxSettings.cit_advances_options()}
              labelledby="tax-cit-label"
            />
            <.suggested
              field={@form[:cit_advances]}
              setting={:cit_advances}
              suggested={@suggested}
              saved={@saved}
            />
          </div>
        </div>
      <% else %>
        <input type="hidden" name={@form[:cit_rate].name} value="" />
        <input type="hidden" name={@form[:cit_advances].name} value="" />
        <.rubric_label number={3} id="tax-partners-label">
          {partners_label(@legal_form)}
        </.rubric_label>
        <%!-- Like the invoice creator's items, the table sits under its label, from the label's
             left edge, so a row with a lump sum rate fits without scrolling. --%>
        <div class={[
          "flex min-w-0 flex-col items-start gap-3 sm:col-start-2 sm:-col-end-1 sm:-mt-4",
          answer_styles()
        ]}>
          <div class="max-w-full overflow-x-auto">
            <div class={[
              "grid items-start gap-2 text-sm",
              @legal_form == :civil_partnership && "grid-cols-[repeat(7,auto)]",
              @legal_form == :sole_proprietorship && "grid-cols-[repeat(5,auto)]"
            ]}>
              <span class="text-grey-600">{gettext("Person")}</span>
              <span :if={@legal_form == :civil_partnership} class="text-grey-600">
                {pgettext("profit share", "Share")}
              </span>
              <span class="text-grey-600">{gettext("Income tax")}</span>
              <span class="text-grey-600">{pgettext("tax", "Advances")}</span>
              <span class="text-grey-600">ZUS</span>
              <span class="text-grey-600">{gettext("Sickness insurance")}</span>
              <span :if={@legal_form == :civil_partnership}></span>

              <.inputs_for :let={partner} field={@form[:partners]}>
                <.partner_row
                  partner={partner}
                  suggested={@suggested}
                  saved={@saved}
                  submitted?={@form.source.submitted_once?}
                  legal_form={@legal_form}
                  member_options={@member_options}
                  removable?={length(@form.source.forms[:partners]) > 2}
                  myself={@myself}
                />
              </.inputs_for>
            </div>
          </div>
          <.field_errors field={@form[:partners]} />
          <.button
            :if={@legal_form == :civil_partnership}
            type="button"
            variant="tertiary"
            size="small"
            phx-click="add_partner"
            phx-target={@myself}
            class="gap-1.5"
          >
            <Lucideicons.plus class="size-4" aria-hidden="true" />
            {gettext("Add partner")}
          </.button>
          <p :if={@legal_form == :civil_partnership} class="text-sm/snug text-grey-600">
            {gettext("Partners are chosen from the team. Their shares add up to 100%.")}
          </p>
        </div>
      <% end %>

      <.rubric_label number={4} for={@form[:accident_insurance_rate].id}>
        {gettext("Accident insurance contribution")}
      </.rubric_label>
      <div class={["flex flex-col gap-2", answer_styles()]}>
        <div class="flex items-baseline gap-1.5">
          <.input
            type="number"
            field={@form[:accident_insurance_rate]}
            step="0.01"
            min="0.34"
            max="10"
            input_class="w-24"
            phx-debounce="300"
          />
          <span class="text-sm text-grey-600">%</span>
        </div>
        <p class="text-sm/snug text-grey-600">{accident_insurance_hint()}</p>
      </div>

      <div class="col-span-full flex justify-end">
        <.button
          type="submit"
          variant="success"
          size="small"
          phx-disable-with={pgettext("settings", "Saving...")}
        >
          {if @confirm?, do: gettext("Confirm"), else: gettext("Save")}
        </.button>
      </div>
    </.form>
    """
  end

  attr :partner, Form, required: true
  attr :suggested, :map, required: true
  attr :saved, :map, required: true
  attr :submitted?, :boolean, required: true
  attr :legal_form, :atom, required: true
  attr :member_options, :list, required: true
  attr :removable?, :boolean, required: true
  attr :myself, :any, required: true

  defp partner_row(assigns) do
    ~H"""
    <div>
      <.input
        type="select"
        field={@partner[:member_id]}
        options={@member_options}
        prompt={gettext("Choose")}
        aria-label={gettext("Person")}
        input_class="min-w-40"
        show_error={false}
      />
      <.field_errors field={@partner[:member_id]} submitted?={@submitted?} />
    </div>
    <%= if @legal_form == :civil_partnership do %>
      <div class="flex items-baseline gap-1.5">
        <.input
          type="number"
          field={@partner[:profit_share]}
          step="0.01"
          min="0"
          max="100"
          input_class="w-20 min-w-20"
          phx-debounce="300"
          aria-label={pgettext("profit share", "Share")}
        />
        <span class="text-grey-600">%</span>
      </div>
    <% else %>
      <input type="hidden" name={@partner[:profit_share].name} value="100" />
    <% end %>
    <%!-- The lump sum rate goes under the tax form, so a row keeps the card's width. --%>
    <div class="flex flex-col gap-2">
      <div>
        <.input
          type="select"
          field={@partner[:income_tax]}
          options={select_options(TaxSettings.income_tax_options())}
          prompt={gettext("Choose")}
          aria-label={gettext("Income tax")}
          input_class="min-w-36"
          show_error={false}
        />
        <.field_errors field={@partner[:income_tax]} submitted?={@submitted?} />
        <.suggested
          field={@partner[:income_tax]}
          setting={:income_tax}
          suggested={@suggested}
          saved={@saved}
        />
      </div>
      <div :if={to_string(@partner[:income_tax].value) == "lump_sum"}>
        <.input
          type="select"
          field={@partner[:lump_sum_rate]}
          options={TaxSettings.lump_sum_rate_options()}
          prompt={gettext("Choose")}
          aria-label={gettext("Lump sum rate")}
          input_class="min-w-36"
          show_error={false}
        />
        <.field_errors field={@partner[:lump_sum_rate]} submitted?={@submitted?} />
        <.suggested
          field={@partner[:lump_sum_rate]}
          setting={:lump_sum_rate}
          suggested={@suggested}
          saved={@saved}
        />
      </div>
      <%!-- A saved partner is updated with what the form sends; without the rate's select the
           previous rate would stay. --%>
      <input
        :if={to_string(@partner[:income_tax].value) != "lump_sum"}
        type="hidden"
        name={@partner[:lump_sum_rate].name}
        value=""
      />
    </div>
    <div>
      <.input
        type="select"
        field={@partner[:pit_advances]}
        options={select_options(TaxSettings.period_options())}
        prompt={gettext("Choose")}
        aria-label={pgettext("tax", "Advances")}
        input_class="min-w-[8.5rem]"
        show_error={false}
      />
      <.field_errors field={@partner[:pit_advances]} submitted?={@submitted?} />
      <.suggested
        field={@partner[:pit_advances]}
        setting={:pit_advances}
        suggested={@suggested}
        saved={@saved}
      />
    </div>
    <div>
      <.input
        type="select"
        field={@partner[:social_insurance]}
        options={select_options(TaxSettings.social_insurance_options())}
        prompt={gettext("Choose")}
        aria-label="ZUS"
        input_class="min-w-44"
        show_error={false}
      />
      <.field_errors field={@partner[:social_insurance]} submitted?={@submitted?} />
      <.suggested
        field={@partner[:social_insurance]}
        setting={:social_insurance}
        suggested={@suggested}
        saved={@saved}
      />
    </div>
    <div>
      <div class="flex h-9 flex-col justify-center">
        <%= if without_sickness?(@partner[:social_insurance].value) do %>
          <%!-- A disabled switch sends nothing, which would keep a previous "on". --%>
          <input type="hidden" name={@partner[:voluntary_sickness].name} value="false" />
          <.switch
            field={%{@partner[:voluntary_sickness] | value: false}}
            color="teal"
            disabled
            aria-label={gettext("Sickness insurance")}
          />
        <% else %>
          <.switch
            field={@partner[:voluntary_sickness]}
            color="teal"
            aria-label={gettext("Sickness insurance")}
          />
        <% end %>
        <.field_errors field={@partner[:voluntary_sickness]} submitted?={@submitted?} />
      </div>
      <.suggested
        :if={!without_sickness?(@partner[:social_insurance].value)}
        field={@partner[:voluntary_sickness]}
        setting={:voluntary_sickness}
        suggested={@suggested}
        saved={@saved}
        nowrap
      />
    </div>
    <div :if={@legal_form == :civil_partnership} class="flex h-9 items-center">
      <.button
        :if={@removable?}
        type="button"
        variant="icon"
        phx-click="remove_partner"
        phx-value-path={@partner.name}
        phx-target={@myself}
        aria-label={gettext("Remove partner")}
        class="size-8 hover:text-grey-900"
      >
        <Lucideicons.x class="size-4" aria-hidden="true" />
      </.button>
    </div>
    """
  end

  attr :field, FormField, required: true
  attr :options, :list, required: true
  attr :labelledby, :string, required: true

  # One choice of a few, as pills like the presence choice of the time tracker.
  defp choice(assigns) do
    ~H"""
    <div class="flex flex-col">
      <div role="radiogroup" aria-labelledby={@labelledby} class="flex flex-wrap gap-1">
        <label :for={{value, label} <- @options} class="cursor-pointer">
          <input
            type="radio"
            name={@field.name}
            id={"#{@field.id}-#{value}"}
            value={value}
            checked={to_string(@field.value) == to_string(value)}
            class="peer sr-only"
          />
          <span class="inline-flex h-8 items-center rounded-full px-3 text-sm font-medium whitespace-nowrap text-grey-700 transition-colors peer-checked:bg-grey-700 peer-checked:text-white peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-(--focus-ring) hover:bg-grey-200 peer-checked:hover:bg-grey-700">
            {label}
          </span>
        </label>
      </div>
      <.field_errors field={@field} />
    </div>
    """
  end

  attr :field, FormField, required: true
  attr :setting, :atom, required: true
  attr :suggested, :map, required: true
  attr :saved, :map, required: true

  attr :nowrap, :boolean,
    default: false,
    doc: "for the last column, which may run on to the right"

  # What the transfers suggest for a setting. A value the year lacks is prefilled quietly. One that
  # contradicts the saved value says what is saved while the field holds the value from the
  # transfers; once the person picks another, only a reminder of what the transfers indicate
  # stays, so that a different choice is a decision rather than an oversight. The text stays
  # inside its column (`w-0 min-w-full`), as it must not shift the owner's row; only the last
  # column (`nowrap`) takes the room its single line needs.
  defp suggested(assigns) do
    %{field: field, setting: setting, suggested: suggested, saved: saved} = assigns

    assigns =
      assigns
      |> assign(
        :mode,
        suggestion_mode(suggested[setting], field.value, Map.has_key?(saved, setting))
      )
      |> assign(
        :indicated,
        suggested[setting] != nil && TaxSettings.value_label(setting, suggested[setting])
      )
      |> assign(
        :saved_label,
        saved[setting] != nil && TaxSettings.value_label(setting, saved[setting])
      )

    ~H"""
    <p
      :if={@mode}
      class={[
        "mt-1.5 flex items-start gap-1 text-sm/snug text-grey-600",
        if(@nowrap, do: "whitespace-nowrap", else: "w-0 min-w-full")
      ]}
    >
      <Lucideicons.history
        class={["mt-0.5 size-3.5 shrink-0", @mode != :prefilled && "text-moss-700"]}
        aria-hidden="true"
      />
      <%= case @mode do %>
        <% :prefilled -> %>
          {gettext("Based on the transactions")}
        <% :contradicts -> %>
          {gettext("Saved: %{value}", value: @saved_label)}
        <% :reminder -> %>
          {gettext("According to the transfers: %{value}", value: @indicated)}
      <% end %>
    </p>
    """
  end

  # Whether every field still holds the value the transfers indicate; once the person picks another,
  # the form no longer is what the summary promises.
  defp holds_indicated?(form, differences) do
    Enum.all?(differences, fn %{setting: setting, indicated: indicated} ->
      to_string(form_value(form.source, setting)) == to_string(indicated)
    end)
  end

  defp form_value(source, setting) when setting in [:vat_period, :cit_advances],
    do: AshPhoenix.Form.value(source, setting)

  # The owner's settings are suggested only for the one owner of a sole proprietorship.
  defp form_value(%{forms: %{partners: [owner]}}, setting), do: AshPhoenix.Form.value(owner, setting)

  defp form_value(_source, _setting), do: nil

  # How a setting's suggestion shows: nothing without one; against a saved value it contradicts
  # while the field holds the suggestion and is a reminder once it does not; otherwise it is a
  # prefill, shown only while the field holds it.
  defp suggestion_mode(nil, _current, _saved?), do: nil

  defp suggestion_mode(value, current, saved?) do
    held? = to_string(current) == to_string(value)

    cond do
      saved? and held? -> :contradicts
      saved? -> :reminder
      held? -> :prefilled
      true -> nil
    end
  end

  attr :field, FormField, required: true

  attr :submitted?, :boolean,
    default: nil,
    doc: "whether the whole form was submitted; a partner row's own form does not know"

  # A choice nobody made sends no input, so its errors also show once the form is submitted.
  defp field_errors(assigns) do
    %{field: field, submitted?: submitted?} = assigns
    shown? = (used_input?(field) or submitted?) || field.form.source.submitted_once?
    errors = if shown?, do: Enum.map(field.errors, &translate_error/1), else: []
    assigns = assign(assigns, :errors, errors)

    ~H"""
    <.error :for={message <- @errors}>{message}</.error>
    """
  end

  attr :number, :integer, required: true
  attr :for, :string, default: nil
  attr :id, :string, default: nil

  slot :inner_block, required: true

  # The rubric rows of the invoice creator: a numeral column, then a quiet label.
  defp rubric_label(assigns) do
    ~H"""
    <%= if @for do %>
      <label for={@for} id={@id} class="col-span-2 grid grid-cols-subgrid">
        <span class="text-sm/snug font-medium text-grey-900 tabular-nums">{@number}.</span>
        <span class="col-start-2 -col-end-1 pe-12 text-sm/snug text-grey-600">
          {render_slot(@inner_block)}
        </span>
      </label>
    <% else %>
      <p id={@id} class="col-span-2 grid grid-cols-subgrid">
        <span class="text-sm/snug font-medium text-grey-900 tabular-nums">{@number}.</span>
        <span class="col-start-2 -col-end-1 pe-12 text-sm/snug text-grey-600">
          {render_slot(@inner_block)}
        </span>
      </p>
    <% end %>
    """
  end

  # Phones have no label column: each answer goes under its label, in the label text's column.
  defp answer_styles, do: "max-sm:col-start-2 max-sm:-mt-5"

  defp partners_label(:sole_proprietorship), do: gettext("Owner")
  defp partners_label(:civil_partnership), do: gettext("Partners")

  defp not_vat_payer_text, do: gettext("The company is not a VAT payer, so it does not settle VAT.")

  defp accident_insurance_hint do
    gettext(
      "1.67% applies to companies reporting fewer than 10 people for insurance. You will find a different rate in the notice from ZUS."
    )
  end

  defp legal_form_options do
    [
      sole_proprietorship: gettext("Sole proprietorship"),
      civil_partnership: gettext("Civil partnership"),
      limited_company: gettext("Limited company")
    ]
  end

  defp cit_rate_options, do: [reduced: gettext("9% – small taxpayer"), standard: "19%"]

  # The option lists are `value: label`; `options_for_select/2` takes `{label, value}`.
  defp select_options(options), do: Enum.map(options, fn {value, label} -> {label, value} end)

  # Without own social contributions there is no voluntary sickness insurance to join.
  defp without_sickness?(social_insurance), do: to_string(social_insurance) in ["start_relief", "none"]

  defp member_options(users), do: Enum.map(users, &{&1.member.name || &1.email, &1.member.id})
end
