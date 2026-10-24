defmodule FirmowidWeb.Management.Components.EmployeePayoutCalculator do
  @moduledoc "A task-focused payout dialog using profile-owned contracts and explicit payroll inputs."
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button

  alias Firmowid.Ash.Payroll.UserSalary
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  @input_fields ~w(payout_date gross prior_taxable_income prior_social_base prior_exempt_income employer_ppk_income employer_ppk_date)
  @balance_fields [
    :prior_taxable_income,
    :prior_social_base,
    :prior_exempt_income,
    :employer_ppk_income,
    :employer_ppk_date
  ]
  @conditions [:employment_active, :single_payment, :standard_pay]

  @impl true
  def update(assigns, socket) do
    identity_changed? =
      Enum.any?([:member_id, :contract_type, :scope], fn key ->
        Map.get(socket.assigns, key) != Map.fetch!(assigns, key)
      end)

    declarations_changed? = socket.assigns[:declarations] != assigns.declarations

    socket =
      socket
      |> assign(assigns)
      |> assign_new(:open, fn -> false end)
      |> assign_new(:balances_open, fn -> false end)
      |> assign_new(:calculation, fn -> nil end)

    socket =
      if identity_changed? do
        assign(socket,
          form: calculation_form(assigns),
          context: empty_context(),
          calculation: nil,
          balances_open: false
        )
      else
        socket
      end

    {:ok, if(declarations_changed?, do: assign(socket, :calculation, nil), else: socket)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:declaration, applicable_declaration(assigns.declarations, assigns.form))
      |> assign(:positive_ppk, positive_ppk?(assigns.form))

    ~H"""
    <div id={@id}>
      <.button
        type="button"
        size="small"
        variant="outline"
        disabled={@contract_type not in [:uop, :uz, :uod]}
        phx-click={JS.push("open", target: @myself)}
      >
        {gettext("Calculate payout")}
      </.button>
      <.modal
        :if={@open}
        id={"#{@id}-modal"}
        show
        on_cancel={JS.push("close", target: @myself)}
        class="max-w-2xl!"
      >
        <div class="flex min-w-0 flex-col gap-6">
          <header class="flex flex-col gap-2">
            <h2 id={"#{@id}-modal-title"} class="pe-6 text-lg/snug font-medium">
              {gettext("Calculate payout")}
            </h2>
            <div id={"#{@id}-profile-context"} tabindex="-1" class="text-sm/snug text-grey-700">
              <p>{contract_label(@contract_type)} · {declaration_label(@declaration, @form)}</p>
              <p :if={is_nil(@contract_type)}>
                {gettext("Set the contract in the employee profile.")}
              </p>
              <p :if={@contract_type == :b2b}>{reason_label(:b2b_taxation)}</p>
            </div>
          </header>

          <section id={"#{@id}-result"} tabindex="-1" aria-live="polite" class="flex flex-col gap-3">
            <div class="flex flex-col gap-1">
              <h3 class="text-sm/snug text-grey-700">{gettext("Net payout")}</h3>
              <p class="text-turquoise-700 text-3xl/snug font-semibold tabular-nums">
                {if @calculation && @calculation.status == :calculated,
                  do: @calculation.result.amount,
                  else: "—"}
              </p>
            </div>
            <%= if @calculation && @calculation.status == :calculated do %>
              <dl class="grid grid-cols-[minmax(0,1fr)_auto] gap-x-4 gap-y-2 text-sm/snug tabular-nums">
                <dt>{gettext("Gross")}</dt>
                <dd class="text-end">{@calculation.result.gross}</dd>
                <%= for {label, amount} <- deductions(@calculation.result) do %>
                  <dt class="text-grey-700">{label}</dt>
                  <dd class="text-end">{deduction(amount)}</dd>
                <% end %>
              </dl>
              <details id={"#{@id}-calculation-details"}>
                <summary class={disclosure_styles()}>{gettext("Calculation details")}</summary>
                <dl class="grid grid-cols-[minmax(0,1fr)_auto] gap-x-4 gap-y-2 pbs-3 text-sm/snug tabular-nums">
                  <dt>{gettext("Tax-deductible costs")}</dt>
                  <dd class="text-end">{@calculation.result.costs}</dd>
                  <dt>{gettext("Taxable base")}</dt>
                  <dd class="text-end">{@calculation.result.taxable}</dd>
                </dl>
                <p :if={@calculation.result.youth_relief?} class="pbs-2 text-xs/snug text-grey-600">
                  {gettext("Youth tax relief applied.")}
                </p>
              </details>
            <% end %>
            <%= if @calculation && @calculation.missing != [] do %>
              <h4 class="text-sm/snug font-medium">{gettext("Still needed")}</h4>
              <ul class="flex flex-col items-start gap-1 text-sm/snug">
                <li :for={{target, label} <- missing_items(@calculation.missing)}>
                  <.button
                    type="button"
                    variant="unstyled"
                    phx-click={JS.focus(to: "##{@id}-#{target}")}
                    class="active:text-darkGrey focus-visible:outline-turquoise-700 text-turquoise-700 min-h-8 cursor-pointer text-start underline decoration-dotted underline-offset-4 outline-offset-2 focus-visible:outline-2"
                  >
                    {label}
                  </.button>
                </li>
              </ul>
            <% end %>
            <%= if @calculation && @calculation.unsupported != [] do %>
              <h4 class="text-sm/snug font-medium">
                {gettext("Requires a separate payroll calculation")}
              </h4>
              <ul class="flex list-disc flex-col gap-1 ps-5 text-sm/snug text-grey-700">
                <li :for={reason <- @calculation.unsupported}>{reason_label(reason)}</li>
              </ul>
            <% end %>
          </section>

          <.form
            :if={@contract_type in [:uop, :uz, :uod]}
            for={@form}
            id={"#{@id}-form"}
            phx-change="validate"
            phx-submit={JS.push("calculate") |> JS.focus(to: "##{@id}-result")}
            phx-target={@myself}
            class="flex min-w-0 flex-col gap-5"
          >
            <div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,13rem),1fr))] gap-4">
              <.input
                field={@form[:payout_date]}
                id={"#{@id}-payout_date"}
                label={gettext("Payout date")}
                type="date"
                new
              />
              <.input
                field={@form[:gross]}
                id={"#{@id}-gross"}
                label={gettext("Gross pay (PLN)")}
                type="number"
                min="0"
                step="0.01"
                new
              />
            </div>
            <fieldset class="flex min-w-0 flex-col gap-2">
              <legend class="mbs-2 text-sm/snug font-medium">{gettext("Confirm this payout")}</legend>
              <.input
                type="checkbox"
                id={"#{@id}-conditions_confirmed"}
                name="context[conditions_confirmed]"
                checked={@context.conditions_confirmed}
                aria-describedby={"#{@id}-conditions"}
                label={gettext("I confirm all three conditions:")}
              />
              <ul
                id={"#{@id}-conditions"}
                class="flex list-disc flex-col gap-1 ps-6 text-sm/snug text-grey-700"
              >
                <li>{gettext("Contract active on the payout date")}</li>
                <li>{gettext("One payout from us this month")}</li>
                <li>{gettext("No benefits, sick pay or additional deductions")}</li>
              </ul>
              <.input
                :if={@contract_type == :uz}
                type="checkbox"
                id={"#{@id}-insurance_unchanged"}
                name="context[insurance_unchanged]"
                checked={@context.insurance_unchanged}
                label={gettext("Insurance status unchanged from work period through payout")}
              />
            </fieldset>

            <details
              id={"#{@id}-balances"}
              open={@balances_open}
              class="border-bs border-grey-200 pbs-4"
            >
              <summary class={disclosure_styles()}>
                {gettext("Year-to-date balances and PPK")}
              </summary>
              <div class="flex flex-col gap-4 pbs-4">
                <p class="text-xs/snug text-grey-600">
                  {gettext(
                    "Use previous payroll totals; exclude the amounts entered for this payout."
                  )}
                </p>
                <.input
                  :if={@contract_type in [:uop, :uz]}
                  type="checkbox"
                  id={"#{@id}-first_payment"}
                  name="context[first_payment]"
                  checked={@context.first_payment}
                  label={gettext("No earlier payments from us this year")}
                />
                <div class="flex flex-col gap-4">
                  <.balance_input
                    :if={@contract_type == :uop}
                    form={@form}
                    root_id={@id}
                    field={:prior_taxable_income}
                    label={gettext("Our taxable income to date (PLN)")}
                    help={gettext("At this employer this year, before this payout.")}
                    readonly={@context.first_payment}
                  />
                  <.balance_input
                    :if={@contract_type in [:uop, :uz]}
                    form={@form}
                    root_id={@id}
                    field={:prior_exempt_income}
                    label={gettext("Our PIT-0 exempt income to date (PLN)")}
                    help={gettext("Exempt income at this employer this year, before this payout.")}
                    readonly={@context.first_payment}
                  />
                  <.balance_input
                    :if={@contract_type in [:uop, :uz]}
                    form={@form}
                    root_id={@id}
                    field={:prior_social_base}
                    label={gettext("Pension contribution base to date (PLN)")}
                    help={gettext("All payers this year; confirm zero separately.")}
                  />
                  <.balance_input
                    form={@form}
                    root_id={@id}
                    field={:employer_ppk_income}
                    label={gettext("Employer PPK paid this month (PLN)")}
                    help={gettext("Actually transferred by payout, not accrued; enter zero if none.")}
                  />
                  <.input
                    :if={@positive_ppk}
                    field={@form[:employer_ppk_date]}
                    id={"#{@id}-employer_ppk_date"}
                    label={gettext("Employer PPK transfer date")}
                    type="date"
                    new
                  />
                </div>
              </div>
            </details>
            <.button size="small" class="self-start" phx-disable-with={gettext("Calculating...")}>
              {gettext("Calculate payout")}
            </.button>
          </.form>
          <p id={"#{@id}-modal-description"} class="text-xs/snug text-grey-600">
            {gettext(
              "Based on supplied data; does not verify declarations or replace payroll records."
            )}
          </p>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def handle_event("open", _params, socket), do: {:noreply, assign(socket, :open, true)}
  def handle_event("close", _params, socket), do: {:noreply, assign(socket, :open, false)}

  def handle_event("validate", params, socket) do
    {params, context} = payout_params(params, socket)
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form, context: context, calculation: nil)}
  end

  def handle_event("calculate", params, socket) do
    {params, context} = payout_params(params, socket)
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    socket = assign(socket, form: form, context: context, calculation: nil)

    case AshPhoenix.Form.submit(form, params: params) do
      {:ok, calculation} ->
        balances_open =
          calculation.status != :calculated and
            (socket.assigns.balances_open or
               Enum.any?(calculation.missing, &(&1 in @balance_fields)))

        {:noreply, assign(socket, calculation: calculation, balances_open: balances_open)}

      {:error, form} ->
        {:noreply, assign(socket, form: form, balances_open: true)}
    end
  end

  attr :form, :any, required: true
  attr :root_id, :string, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :help, :string, required: true
  attr :readonly, :boolean, default: false

  defp balance_input(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-col gap-1">
      <.input
        field={@form[@field]}
        id={"#{@root_id}-#{@field}"}
        label={@label}
        type="number"
        min="0"
        step="0.01"
        readonly={@readonly}
        aria-describedby={"#{@root_id}-#{@field}-help"}
        new
      />
      <p id={"#{@root_id}-#{@field}-help"} class="text-xs/snug text-grey-600">{@help}</p>
    </div>
    """
  end

  defp empty_context do
    %{conditions_confirmed: false, insurance_unchanged: false, first_payment: false}
  end

  defp calculation_form(assigns) do
    UserSalary
    |> AshPhoenix.Form.for_action(:calculate_payout,
      scope: assigns.scope,
      as: "payout",
      params: %{"member_id" => assigns.member_id, "contract_type" => assigns.contract_type}
    )
    |> to_form()
  end

  defp payout_params(payload, socket) do
    flags = Map.get(payload, "context", %{})

    context = %{
      conditions_confirmed: flags["conditions_confirmed"] == "true",
      insurance_unchanged: flags["insurance_unchanged"] == "true",
      first_payment: flags["first_payment"] == "true"
    }

    # Context flags never reach Ash; identity and contract always come from the profile.
    params =
      payload
      |> Map.get("payout", %{})
      |> Map.take(@input_fields)
      |> Map.put("member_id", socket.assigns.member_id)
      |> Map.put("contract_type", socket.assigns.contract_type)
      |> Map.put("employment_active", confirmed(context.conditions_confirmed))
      |> Map.put("single_payment", confirmed(context.conditions_confirmed))
      |> Map.put("standard_pay", confirmed(context.conditions_confirmed))
      |> Map.put("insurance_unchanged", confirmed(context.insurance_unchanged))
      |> first_payment_balances(context.first_payment, socket.assigns.context.first_payment)

    {params, context}
  end

  defp confirmed(true), do: true
  defp confirmed(false), do: nil

  defp first_payment_balances(params, true, _previous) do
    Map.merge(params, %{"prior_taxable_income" => "0", "prior_exempt_income" => "0"})
  end

  defp first_payment_balances(params, false, true) do
    Map.merge(params, %{"prior_taxable_income" => "", "prior_exempt_income" => ""})
  end

  defp first_payment_balances(params, false, false), do: params

  defp positive_ppk?(form) do
    # ActionInput keeps invalid strings too; compare only successfully cast Decimals.
    case form.source.source.arguments[:employer_ppk_income] do
      %Decimal{coef: coefficient} = amount when is_integer(coefficient) ->
        Decimal.compare(amount, 0) == :gt

      value when is_nil(value) or is_binary(value) ->
        false
    end
  end

  defp applicable_declaration(declarations, form) do
    case form.source.source.arguments[:payout_date] do
      %Date{} = date -> Enum.find(declarations, &(Date.compare(&1.applies_from, date) != :gt))
      value when is_nil(value) or is_binary(value) -> nil
    end
  end

  defp contract_label(:uop), do: gettext("Employment contract")
  defp contract_label(:uz), do: gettext("Mandate contract")
  defp contract_label(:uod), do: gettext("Specific-task contract")
  defp contract_label(:b2b), do: "B2B"
  defp contract_label(nil), do: gettext("No contract in profile")

  defp declaration_label(nil, form) do
    case form.source.source.arguments[:payout_date] do
      %Date{} -> gettext("No declarations for this payout date")
      value when is_nil(value) or is_binary(value) -> gettext("Choose a payout date")
    end
  end

  defp declaration_label(declaration, _form) do
    gettext("Declarations from %{date}",
      date: TimeFormatter.format_date(declaration.applies_from)
    )
  end

  defp disclosure_styles do
    "cursor-pointer text-sm/snug font-medium outline-offset-4 focus-visible:outline-2 focus-visible:outline-turquoise-700 active:text-turquoise-700"
  end

  defp deductions(result) do
    [
      {gettext("Social insurance"), result.social},
      {gettext("Health insurance"), result.health},
      {gettext("Income tax advance"), result.tax},
      {gettext("Employee PPK contribution"), result.ppk}
    ]
  end

  defp deduction(amount), do: if(Money.zero?(amount), do: amount, else: Money.negate!(amount))

  defp missing_items(reasons) do
    reasons =
      if :payout_date in reasons, do: List.delete(reasons, :applicable_declaration), else: reasons

    reasons |> Enum.map(&missing_item/1) |> Enum.uniq()
  end

  defp missing_item(reason) when reason in @conditions do
    {"conditions_confirmed", gettext("Confirm the three payout conditions")}
  end

  defp missing_item(:insurance_unchanged) do
    {"insurance_unchanged", gettext("Confirm unchanged insurance status")}
  end

  defp missing_item(:contract_type), do: {"profile-context", gettext("Set the contract in the employee profile.")}

  defp missing_item(:birthday), do: {"profile-context", gettext("Add the date of birth in the employee profile.")}

  defp missing_item(:applicable_declaration) do
    {"profile-context", gettext("Add declarations covering the payout date in the employee profile.")}
  end

  defp missing_item(reason) when reason in [:payout_date, :gross | @balance_fields] do
    {to_string(reason), input_label(reason)}
  end

  defp missing_item(reason) do
    {"profile-context", gettext("Complete declarations: %{field}", field: declaration_field_label(reason))}
  end

  defp input_label(:payout_date), do: gettext("Payout date")
  defp input_label(:gross), do: gettext("Gross pay (PLN)")
  defp input_label(:prior_taxable_income), do: gettext("Our taxable income to date (PLN)")
  defp input_label(:prior_social_base), do: gettext("Pension contribution base to date (PLN)")
  defp input_label(:prior_exempt_income), do: gettext("Our PIT-0 exempt income to date (PLN)")
  defp input_label(:employer_ppk_income), do: gettext("Employer PPK paid this month (PLN)")
  defp input_label(:employer_ppk_date), do: gettext("Employer PPK transfer date")

  defp declaration_field_label(:received_on), do: gettext("Declaration received on")
  defp declaration_field_label(:applies_from), do: gettext("Apply from")
  defp declaration_field_label(:tax_residency), do: gettext("Tax residency")
  defp declaration_field_label(:pit2), do: gettext("Monthly PIT-2 reduction")
  defp declaration_field_label(:pit0), do: gettext("Other PIT-0 exemption declaration")
  defp declaration_field_label(:tax_mode), do: gettext("Income tax advance request")

  defp declaration_field_label(:preferential), do: gettext("Preferential advance calculation declaration")

  defp declaration_field_label(:copyright_costs), do: gettext("Apply 50% copyright costs")
  defp declaration_field_label(:ppk), do: gettext("PPK participation")
  defp declaration_field_label(:employee_costs), do: gettext("Employment tax-deductible costs")
  defp declaration_field_label(:youth_relief), do: gettext("Youth tax relief")
  defp declaration_field_label(:student), do: gettext("Confirmed pupil or student status")
  defp declaration_field_label(:student_until), do: gettext("Student status confirmed through")
  defp declaration_field_label(:other_employment), do: gettext("Other insurance title")

  defp declaration_field_label(:own_employer), do: gettext("Civil contract with or for own employer")

  defp declaration_field_label(:sickness), do: gettext("Voluntary sickness insurance requested")
  defp declaration_field_label(:ppk_employee_rate), do: gettext("Total employee PPK rate (%)")
  defp declaration_field_label(:request_year), do: gettext("Tax year of the annual request")

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
