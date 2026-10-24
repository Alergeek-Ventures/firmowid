defmodule FirmowidWeb.Management.Components.EmployeeTaxDetails do
  @moduledoc "Effective employee declarations and an explicit-input monthly payout calculation."
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidWeb.Management.Components.Card

  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Payroll.MemberTaxDeclaration
  alias Firmowid.Ash.Payroll.UserSalary

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:declarations, fn ->
        Payroll.list_tax_declarations!(%{member_id: assigns.member_id}, scope: assigns.scope)
      end)
      |> assign_new(:editing, fn -> false end)
      |> assign_new(:calculation, fn -> nil end)
      |> assign_new(:calculation_attempted, fn -> false end)

    socket =
      socket
      |> assign_new(:declaration_form, fn ->
        declaration_form(List.first(socket.assigns.declarations), assigns.scope)
      end)
      |> assign_new(:calculation_form, fn -> calculation_form(assigns) end)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :sections, declaration_sections())

    ~H"""
    <div id={@id}>
      <.card class="min-w-0" dimmed={@archived}>
        <.card_header>
          {gettext("Taxes and insurance")}
          <:actions>
            <.button
              type="button"
              size="small"
              variant="outline"
              phx-click="toggle-tax-editor"
              phx-target={@myself}
            >
              {if @editing, do: gettext("Cancel"), else: gettext("New declaration version")}
            </.button>
          </:actions>
        </.card_header>
        <p class="text-sm/snug text-grey-700">
          {gettext(
            "Record the employee's declarations for this employer. Unknown is not the same as no. A saved declaration does not confirm that its contents are true."
          )}
        </p>
        <%= if @declarations == [] do %>
          <p class="text-sm/snug text-grey-700">
            {gettext(
              "No tax declarations recorded. Existing net forecasts use hypothetical assumptions."
            )}
          </p>
        <% else %>
          <div class="flex flex-wrap items-center gap-2 text-sm/snug">
            <span>{gettext("Declaration versions (effective from):")}</span>
            <.button
              :for={declaration <- @declarations}
              type="button"
              size="small"
              variant="outline"
              phx-click="select-tax-declaration"
              phx-target={@myself}
              phx-value-id={declaration.id}
            >
              {Date.to_iso8601(declaration.applies_from)}
            </.button>
          </div>
        <% end %>

        <.form
          :if={@editing}
          for={@declaration_form}
          id="employee-tax-declaration-form"
          phx-change="validate-tax-declaration"
          phx-submit="save-tax-declaration"
          phx-target={@myself}
          class="flex flex-col gap-6"
        >
          <p class="text-sm/snug text-grey-700">
            {gettext(
              "A different effective date creates a new version. Saving the same date corrects that version. Earlier versions remain available."
            )}
          </p>
          <fieldset :for={{title, fields} <- @sections} class="flex min-w-0 flex-col gap-4">
            <legend class="mbs-2 font-medium">{title}</legend>
            <div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,15rem),1fr))] gap-4">
              <.tax_field :for={field <- fields} form={@declaration_form} definition={field} />
            </div>
          </fieldset>
          <.button size="small" class="self-start" phx-disable-with={gettext("Saving...")}>
            {gettext("Save declarations")}
          </.button>
        </.form>

        <details
          id="employee-payout-calculator"
          class="min-w-0 border-bs border-grey-200 pbs-4"
          open={@calculation_attempted}
        >
          <summary class="cursor-pointer font-medium outline-offset-4 focus-visible:outline-2 focus-visible:outline-turquoise-700 active:text-turquoise-700">
            {gettext("Calculate a monthly payout")}
          </summary>
          <div class="flex flex-col gap-5 pbs-4">
            <p class="text-sm/snug text-grey-700">
              {gettext(
                "Enter the actual payout date, gross pay and balances before this payout. Tax declarations are selected by the payout date. For mandates, confirm unchanged insurance status throughout the work period and up to payout. Nothing is inferred from time records or previous forecasts. This calculation is not a saved payroll record."
              )}
            </p>
            <p class="text-sm/snug text-grey-700">
              {gettext(
                "Supports ordinary Polish employment, mandate and specific-task payouts in 2026. Copyright costs, preferential advances, other PIT-0 exemptions and nonstandard cases are recorded but not calculated."
              )}
            </p>
            <.form
              for={@calculation_form}
              id="employee-payout-calculation-form"
              phx-change="validate-payout-calculation"
              phx-submit="calculate-payout"
              phx-target={@myself}
              class="flex flex-col gap-5"
            >
              <div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,15rem),1fr))] gap-4">
                <.tax_field
                  :for={field <- calculation_fields(@calculation_form[:contract_type].value)}
                  form={@calculation_form}
                  definition={field}
                />
              </div>
              <p class="text-sm/snug text-grey-700">
                {gettext(
                  "Use opening balances from preceding payroll calculations, excluding the gross pay and employer PPK income entered here. Taxable and PIT-0 exempt income concern this employer; the pension contribution base covers all employers. Use the payout's calendar year. Enter zero only when the balance is known to be zero."
                )}
              </p>
              <.button size="small" class="self-start">{gettext("Calculate payout")}</.button>
            </.form>
            <section
              :if={@calculation}
              id="employee-payout-result"
              aria-live="polite"
              class="flex flex-col gap-3"
            >
              <%= if @calculation.status == :calculated do %>
                <h4 class="font-medium">{gettext("Calculation based on supplied data")}</h4>
                <dl class="grid grid-cols-[minmax(0,1fr)_auto] gap-x-4 gap-y-2 text-sm/snug tabular-nums">
                  <%= for {label, amount} <- result_rows(@calculation.result) do %>
                    <dt>{label}</dt>
                    <dd class="text-end">{amount}</dd>
                  <% end %>
                </dl>
                <p class="text-sm/snug text-grey-700">
                  {gettext(
                    "The result applies only to the supplied ordinary monthly payout. It does not verify declarations or replace a complete payroll record."
                  )}
                </p>
              <% else %>
                <h4 class="font-medium">{gettext("Cannot calculate a complete payout")}</h4>
                <p class="text-sm/snug text-grey-700">
                  {gettext(
                    "No net amount is shown until the required inputs and supported conditions are confirmed."
                  )}
                </p>
                <ul class="list-disc space-y-1 ps-5 text-sm/snug text-grey-700">
                  <li :for={reason <- @calculation.missing}>{missing_label(reason)}</li>
                  <li :for={reason <- @calculation.unsupported}>{unsupported_label(reason)}</li>
                </ul>
              <% end %>
            </section>
          </div>
        </details>
      </.card>
    </div>
    """
  end

  @impl true
  def handle_event("toggle-tax-editor", _params, socket) do
    {:noreply,
     socket
     |> update(:editing, &(!&1))
     |> assign(
       :declaration_form,
       declaration_form(List.first(socket.assigns.declarations), socket.assigns.scope, :new)
     )}
  end

  def handle_event("select-tax-declaration", %{"id" => id}, socket) do
    declaration = Enum.find(socket.assigns.declarations, &(&1.id == id))

    {:noreply,
     assign(socket,
       editing: true,
       declaration_form: declaration_form(declaration, socket.assigns.scope)
     )}
  end

  def handle_event("validate-tax-declaration", %{"declaration" => params}, socket) do
    form =
      AshPhoenix.Form.validate(socket.assigns.declaration_form, member_params(params, socket))

    {:noreply, assign(socket, :declaration_form, form)}
  end

  def handle_event("save-tax-declaration", %{"declaration" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.declaration_form,
           params: member_params(params, socket)
         ) do
      {:ok, declaration} ->
        declarations =
          Payroll.list_tax_declarations!(%{member_id: socket.assigns.member_id},
            scope: socket.assigns.scope
          )

        {:noreply,
         assign(socket,
           declarations: declarations,
           declaration_form: declaration_form(declaration, socket.assigns.scope),
           editing: false,
           calculation: nil
         )}

      {:error, form} ->
        {:noreply, assign(socket, :declaration_form, form)}
    end
  end

  def handle_event("validate-payout-calculation", %{"payout" => params}, socket) do
    form =
      AshPhoenix.Form.validate(socket.assigns.calculation_form, member_params(params, socket))

    {:noreply, assign(socket, calculation_form: form, calculation: nil)}
  end

  def handle_event("calculate-payout", %{"payout" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.calculation_form,
           params: member_params(params, socket)
         ) do
      {:ok, result} ->
        {:noreply, assign(socket, calculation: result, calculation_attempted: true)}

      {:error, form} ->
        {:noreply, assign(socket, calculation_form: form, calculation: nil)}
    end
  end

  attr :form, :any, required: true
  attr :definition, :map, required: true

  defp tax_field(assigns) do
    ~H"""
    <.input
      field={@form[@definition.key]}
      label={@definition.label}
      type={@definition.type}
      options={[{gettext("Unknown / not provided"), ""} | @definition.options]}
      min={
        if @definition.type == "number",
          do: if(@definition.key == :request_year, do: "2022", else: "0")
      }
      max={if @definition.key == :request_year, do: "2100"}
      step={
        if @definition.type == "number",
          do: if(@definition.key == :request_year, do: "1", else: "0.01")
      }
      container_class="min-w-0"
      new
    />
    """
  end

  defp member_params(params, socket), do: Map.put(params, "member_id", socket.assigns.member_id)

  defp declaration_form(declaration, scope, mode \\ :correction) do
    fields =
      Enum.flat_map(declaration_sections(), fn {_title, fields} -> Enum.map(fields, & &1.key) end)

    params = if declaration, do: Map.take(declaration, fields), else: %{}
    params = if mode == :new, do: Map.drop(params, [:received_on, :applies_from]), else: params

    MemberTaxDeclaration
    |> AshPhoenix.Form.for_create(:save_tax_declaration,
      scope: scope,
      as: "declaration",
      params: params
    )
    |> to_form()
  end

  defp calculation_form(assigns) do
    UserSalary
    |> AshPhoenix.Form.for_action(:calculate_payout,
      scope: assigns.scope,
      as: "payout",
      params: %{member_id: assigns.member_id, contract_type: assigns.contract_type}
    )
    |> to_form()
  end

  defp field(key, label, type, options \\ []), do: %{key: key, label: label, type: type, options: options}

  defp yes_no, do: [{gettext("Yes"), true}, {gettext("No"), false}]

  defp declaration_sections do
    [
      {gettext("Effective dates and tax residency"),
       [
         field(:received_on, gettext("Declaration received on"), "date"),
         field(:applies_from, gettext("Apply from"), "date"),
         field(:tax_residency, gettext("Tax residency"), "select", [
           {gettext("Poland"), :poland},
           {gettext("Other country"), :other}
         ])
       ]},
      {gettext("Income tax declarations"),
       [
         field(:pit2, gettext("Monthly PIT-2 reduction"), "select", [
           {gettext("No reduction"), :none},
           {"300 PLN (1/12)", :one_twelfth},
           {"150 PLN (1/24)", :one_twenty_fourth},
           {"100 PLN (1/36)", :one_thirty_sixth}
         ]),
         field(:employee_costs, gettext("Employment tax-deductible costs"), "select", [
           {gettext("Do not apply"), :none},
           {gettext("Standard — PLN 250"), :standard},
           {gettext("Elevated — PLN 300"), :elevated}
         ]),
         field(:youth_relief, gettext("Youth tax relief"), "select", [
           {gettext("Apply when eligible"), :apply},
           {gettext("Employee requested non-application"), :waived}
         ]),
         field(:pit0, gettext("Other PIT-0 exemption declaration"), "select", [
           {gettext("None"), :none},
           {gettext("Return to Poland"), :returning},
           {gettext("Families with four or more children"), :family},
           {gettext("Working seniors"), :senior}
         ]),
         field(:tax_mode, gettext("Income tax advance request"), "select", [
           {gettext("Standard withholding"), :standard},
           {gettext("Higher rate — 32%"), :higher},
           {gettext("Do not withhold advances this year"), :no_advance}
         ]),
         field(:preferential, gettext("Preferential advance calculation declaration"), "select", [
           {gettext("None"), :none},
           {gettext("Joint — own income up to PLN 120,000"), :joint_below},
           {gettext("Joint — own income above PLN 120,000"), :joint_above},
           {gettext("Single parent — own income up to PLN 120,000"), :single_below},
           {gettext("Single parent — own income above PLN 120,000"), :single_above}
         ]),
         field(:request_year, gettext("Tax year of the annual request"), "number"),
         field(:copyright_costs, gettext("Apply 50% copyright costs"), "select", yes_no())
       ]},
      {gettext("Mandate and specific-task insurance declarations"),
       [
         field(:student, gettext("Confirmed pupil or student status"), "select", yes_no()),
         field(:student_until, gettext("Student status confirmed through"), "date"),
         field(:other_employment, gettext("Other insurance title"), "select", [
           {gettext("No other title"), :none},
           {gettext("Other employment below minimum wage"), :below_minimum},
           {gettext("Other employment at least minimum wage"), :at_least_minimum},
           {gettext("Other situation requiring individual assessment"), :other}
         ]),
         field(
           :own_employer,
           gettext("Civil contract with or for own employer"),
           "select",
           yes_no()
         ),
         field(:sickness, gettext("Voluntary sickness insurance requested"), "select", yes_no())
       ]},
      {gettext("Employee capital plans (PPK)"),
       [
         field(:ppk, gettext("PPK participation"), "select", [
           {gettext("Not participating"), :none},
           {gettext("Participating"), :participant}
         ]),
         field(:ppk_employee_rate, gettext("Total employee PPK rate (%)"), "number")
       ]}
    ]
  end

  defp calculation_fields(type \\ nil) do
    Enum.filter(
      [
        field(:contract_type, gettext("Contract type"), "select", [
          {gettext("Employment contract"), :uop},
          {gettext("Mandate contract"), :uz},
          {gettext("Specific-task contract"), :uod},
          {"B2B", :b2b}
        ]),
        field(:payout_date, gettext("Actual payout date"), "date"),
        field(:gross, gettext("Gross pay (PLN)"), "number"),
        field(
          :employment_active,
          gettext("Contract still in force on payout date"),
          "select",
          yes_no()
        ),
        field(
          :single_payment,
          gettext("Only payout from this employer in this calendar month"),
          "select",
          yes_no()
        ),
        field(
          :standard_pay,
          gettext("Ordinary pay only, without benefits, sick pay or other deductions"),
          "select",
          yes_no()
        ),
        field(
          :insurance_unchanged,
          gettext("Mandate insurance status unchanged throughout work period and up to payout"),
          "select",
          yes_no()
        ),
        field(
          :prior_taxable_income,
          gettext("Taxable income at this employer before payout (PLN)"),
          "number"
        ),
        field(
          :prior_social_base,
          gettext("Annual pension contribution base at all employers before payout (PLN)"),
          "number"
        ),
        field(
          :prior_exempt_income,
          gettext("Annual PIT-0 exempt income at this employer before payout (PLN)"),
          "number"
        ),
        field(
          :employer_ppk_income,
          gettext("Employer PPK payments actually credited this month (PLN)"),
          "number"
        ),
        field(
          :employer_ppk_date,
          gettext("Employer PPK transfer date (required for a positive amount)"),
          "date"
        )
      ],
      fn field ->
        case field.key do
          :insurance_unchanged ->
            type in [nil, :uz, "uz"]

          :prior_taxable_income ->
            type in [nil, :uop, "uop"]

          field when field in [:prior_social_base, :prior_exempt_income] ->
            type in [nil, :uop, "uop", :uz, "uz"]

          _field ->
            true
        end
      end
    )
  end

  defp result_rows(result) do
    [
      {gettext("Gross"), result.gross},
      {gettext("Social insurance"), result.social},
      {gettext("Health insurance"), result.health},
      {gettext("Tax-deductible costs"), result.costs},
      {gettext("Taxable base"), result.taxable},
      {gettext("Income tax advance"), result.tax},
      {gettext("Employee PPK contribution"), result.ppk},
      {gettext("Net payout"), result.amount}
    ]
  end

  defp missing_label(:applicable_declaration), do: gettext("No tax declaration is available for the payout date.")

  defp missing_label(:birthday), do: gettext("The employee's date of birth is missing from their profile.")

  defp missing_label(reason), do: gettext("Required input: %{field}", field: input_label(reason))
  defp unsupported_label(reason), do: reason_label(reason)

  defp input_label(reason) do
    labels =
      declaration_sections()
      |> Enum.flat_map(&elem(&1, 1))
      |> Enum.concat(calculation_fields())
      |> Map.new(&{&1.key, &1.label})

    Map.fetch!(labels, reason)
  end

  defp reason_label(:b2b_taxation), do: gettext("B2B contractor taxes are not employee payroll deductions.")

  defp reason_label(:contract_type), do: gettext("This contract type is not supported.")

  defp reason_label(:tax_year), do: gettext("Only payouts in 2026 are supported. Rates for other years are not assumed.")

  defp reason_label(:inactive_contract),
    do: gettext("Payouts after the contract ends require separate declaration rules.")

  defp reason_label(:multiple_payments),
    do: gettext("Multiple payouts in one month require shared monthly tax costs and reductions.")

  defp reason_label(:nonstandard_pay),
    do: gettext("Benefits, sick pay and other deductions require a full payroll calculation.")

  defp reason_label(:negative_inputs), do: gettext("Pay and prior balances cannot be negative.")

  defp reason_label(:foreign_tax_residency),
    do: gettext("Foreign tax residency requires individual tax and insurance assessment.")

  defp reason_label(:pit0), do: gettext("PIT-0 exemptions other than youth relief are recorded but not calculated.")

  defp reason_label(:preferential), do: gettext("Preferential advance declarations are recorded but not calculated.")

  defp reason_label(:copyright_costs),
    do: gettext("Copyright remuneration requires separate eligibility and cost allocation.")

  defp reason_label(:no_advance),
    do: gettext("The annual request not to withhold advances is recorded but not calculated.")

  defp reason_label(:own_employer),
    do: gettext("A civil contract with or for the employee's employer must be combined with employment payroll.")

  defp reason_label(:other_employment),
    do: gettext("This insurance title requires an individual contribution assessment.")

  defp reason_label(:small_civil_contract),
    do:
      gettext(
        "For civil-contract payments up to PLN 200, the total contractual amount is needed to determine the tax regime."
      )

  defp reason_label(:student_status_change), do: reason_label(:insurance_status_change)

  defp reason_label(:ppk_eligibility),
    do: gettext("PPK participation or employer PPK income is inconsistent with this contract's insurance status.")

  defp reason_label(:ppk_employee_rate), do: gettext("The employee PPK contribution rate is outside the supported range.")

  defp reason_label(:reduced_ppk_rate),
    do: gettext("PPK rates below 2% require monthly earnings from all sources; reduced rates are not calculated.")

  defp reason_label(:exempt_social_allocation),
    do: gettext("Partial youth relief combined with PPK or contribution limits requires more detailed income allocation.")

  defp reason_label(:health_contribution_cap),
    do: gettext("A health contribution reduction under the 2021 rules may apply; this case is not calculated.")

  defp reason_label(:negative_payout),
    do: gettext("Deductions exceed the payout. Tax collection requires an individual payroll calculation.")

  defp reason_label(:insurance_status_change),
    do: gettext("Changes in mandate insurance status require separate calculations for each work period.")

  defp reason_label(:birthday), do: gettext("The employee's date of birth must not be after the payout date.")

  defp reason_label(:ppk_transfer_timing),
    do:
      gettext(
        "Only employer PPK transfers made in the payout month on or before payout can be included. Other transfers require separate tax collection."
      )
end
