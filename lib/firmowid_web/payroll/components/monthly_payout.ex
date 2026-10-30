defmodule FirmowidWeb.Payroll.Components.MonthlyPayout do
  @moduledoc "Shows the automatically calculated monthly payout and the facts still needed."
  use FirmowidWeb, :html

  alias Firmowid.TimeFormatter
  alias Phoenix.LiveView.Rendered

  attr :calculation, :map, default: nil
  attr :month, Date, required: true

  @doc "Renders a payout without asking the user to run a calculation."
  @spec summary(map()) :: Rendered.t()
  def summary(assigns) do
    assigns = assign(assigns, :amount, amount(assigns.calculation))

    ~H"""
    <section id="monthly-payout" class="flex min-w-0 flex-col gap-4">
      <div class="flex flex-col gap-1">
        <h3 class="text-sm/snug text-grey-700">{gettext("Amount to pay")}</h3>
        <p class="text-2xl/snug font-semibold text-grey-900 tabular-nums">{@amount || "—"}</p>
        <p class="text-xs/snug text-grey-600">{TimeFormatter.format_date(@month, "LLLL yyyy")}</p>
      </div>

      <%= if @amount do %>
        <div class="flex flex-col gap-2 border-bs border-grey-200 pbs-4 text-sm/snug tabular-nums">
          <dl class="grid grid-cols-[minmax(0,1fr)_auto] items-baseline gap-x-4 font-medium">
            <dt>{gross_label(@calculation.gross_source)}</dt>
            <dd class="text-end text-nowrap text-grey-600">{@calculation.result.gross}</dd>
          </dl>
          <dl class="ms-1 grid grid-cols-[minmax(0,1fr)_auto] items-baseline gap-x-4 gap-y-2 border-s border-grey-200 ps-3">
            <%= for {label, value} <- deductions(@calculation.result) do %>
              <dt class="text-grey-700">{label}</dt>
              <dd class="text-end text-nowrap text-grey-600">
                {if Money.zero?(value), do: value, else: Money.negate!(value)}
              </dd>
            <% end %>
          </dl>
        </div>
      <% else %>
        <div class="flex flex-col gap-2 border-bs border-grey-200 pbs-4 text-sm/snug">
          <p class="font-medium">{status_label(@calculation)}</p>
          <ul
            :if={@calculation}
            class="ms-1 flex flex-col gap-2 border-s border-grey-200 ps-3 text-grey-700"
          >
            <li :for={reason <- Enum.uniq(@calculation.missing)}>{missing_label(reason)}</li>
            <li :for={reason <- Enum.uniq(@calculation.unsupported)}>{unsupported_label(reason)}</li>
          </ul>
        </div>
      <% end %>
    </section>
    """
  end

  @doc "Returns an amount only for a complete, supported calculation."
  @spec amount(map() | nil) :: Money.t() | nil
  def amount(%{status: :calculated, result: %{amount: amount}}), do: amount
  def amount(_calculation), do: nil

  @doc "Describes whether a monthly payout is ready or needs more information."
  @spec status_label(map() | nil) :: String.t()
  def status_label(%{status: :calculated}), do: gettext("Payout calculated from saved details")
  def status_label(%{status: :unsupported}), do: gettext("This payout needs an individual review")
  def status_label(_calculation), do: gettext("More employee details are needed")

  defp deductions(result) do
    [
      {gettext("Social insurance"), result.social},
      {gettext("Health insurance"), result.health},
      {gettext("Income tax advance"), result.tax},
      {gettext("Employee PPK contribution"), result.ppk}
    ]
  end

  defp gross_label(:payroll_data), do: gettext("Gross pay from payroll data")
  defp gross_label(:timesheet), do: gettext("Gross pay from submitted hours")

  defp missing_label(:contract_type), do: gettext("Contract type")
  defp missing_label(:payout_date), do: gettext("Payout date")

  defp missing_label(:payout_date_basis), do: gettext("Whether the payout date is planned or actual")

  defp missing_label(:gross), do: gettext("Confirmed gross pay for this month")
  defp missing_label(:hours_record), do: gettext("Submitted timesheet for this month")
  defp missing_label(:employment_active), do: gettext("Active employment contract")
  defp missing_label(:single_payment), do: gettext("Number of payouts this month")

  defp missing_label(:standard_pay), do: gettext("Information about benefits and other deductions")

  defp missing_label(:insurance_unchanged), do: gettext("Insurance status during the work period")
  defp missing_label(:birthday), do: gettext("Employee date of birth")

  defp missing_label(:applicable_declaration), do: gettext("Employee declarations covering the payout date")

  defp missing_label(:received_on), do: gettext("Declaration received on")
  defp missing_label(:applies_from), do: gettext("Apply from")
  defp missing_label(:tax_residency), do: gettext("Tax residency")
  defp missing_label(:pit2), do: gettext("Monthly PIT-2 reduction")
  defp missing_label(:pit0), do: gettext("Other PIT-0 exemption declaration")
  defp missing_label(:tax_mode), do: gettext("Tax advances")
  defp missing_label(:preferential), do: gettext("Preferential advance calculation declaration")
  defp missing_label(:copyright_costs), do: gettext("Apply 50% copyright costs")
  defp missing_label(:ppk), do: gettext("PPK participation")
  defp missing_label(:ppk_employee_rate), do: gettext("Employee PPK rate (%)")
  defp missing_label(:employee_costs), do: gettext("Tax-deductible costs")
  defp missing_label(:youth_relief), do: gettext("Youth tax relief")
  defp missing_label(:student), do: gettext("Pupil or student")
  defp missing_label(:student_until), do: gettext("Student status confirmed through")
  defp missing_label(:other_employment), do: gettext("Other insurance title")
  defp missing_label(:own_employer), do: gettext("Contract with own employer")
  defp missing_label(:sickness), do: gettext("Voluntary sickness insurance")
  defp missing_label(:request_year), do: gettext("Tax year of the annual request")
  defp missing_label(:prior_taxable_income), do: gettext("Taxable income before this payout")

  defp missing_label(:prior_social_base), do: gettext("Pension contribution base before this payout, from all employers")

  defp missing_label(:prior_exempt_income), do: gettext("Tax-exempt income before this payout")

  defp missing_label(:employer_ppk_income), do: gettext("Employer PPK contributions transferred this month")

  defp missing_label(:employer_ppk_date), do: gettext("Employer PPK transfer date")

  defp unsupported_label(:b2b_taxation), do: gettext("B2B contractor taxes are not employee payroll deductions.")

  defp unsupported_label(:contract_type), do: gettext("This contract type is not supported.")

  defp unsupported_label(:tax_year),
    do: gettext("Only payouts in 2026 are supported. Rates for other years are not assumed.")

  defp unsupported_label(:inactive_contract), do: gettext("The contract is not active on the payout date.")

  defp unsupported_label(:multiple_payments),
    do: gettext("Multiple payouts in one month require shared monthly tax costs and reductions.")

  defp unsupported_label(:nonstandard_pay),
    do: gettext("Benefits, sick pay and other deductions require a full payroll calculation.")

  defp unsupported_label(:negative_inputs), do: gettext("Pay and prior balances cannot be negative.")

  defp unsupported_label(:foreign_tax_residency),
    do: gettext("Foreign tax residency requires individual tax and insurance assessment.")

  defp unsupported_label(:pit0), do: gettext("PIT-0 exemptions other than youth relief are recorded but not calculated.")

  defp unsupported_label(:preferential), do: gettext("Preferential advance declarations are recorded but not calculated.")

  defp unsupported_label(:copyright_costs),
    do: gettext("Copyright remuneration requires separate eligibility and cost allocation.")

  defp unsupported_label(:no_advance),
    do: gettext("The annual request not to withhold advances is recorded but not calculated.")

  defp unsupported_label(:own_employer),
    do: gettext("A civil contract with or for the employee's employer must be combined with employment payroll.")

  defp unsupported_label(:other_employment),
    do: gettext("This insurance title requires an individual contribution assessment.")

  defp unsupported_label(:small_civil_contract),
    do:
      gettext(
        "For civil-contract payments up to PLN 200, the total contractual amount is needed to determine the tax regime."
      )

  defp unsupported_label(:student_status_change), do: unsupported_label(:insurance_status_change)

  defp unsupported_label(:ppk_eligibility),
    do: gettext("PPK participation or employer PPK income is inconsistent with this contract's insurance status.")

  defp unsupported_label(:ppk_employee_rate),
    do: gettext("The employee PPK contribution rate is outside the supported range.")

  defp unsupported_label(:reduced_ppk_rate),
    do: gettext("PPK rates below 2% require monthly earnings from all sources; reduced rates are not calculated.")

  defp unsupported_label(:exempt_social_allocation),
    do: gettext("Partial youth relief combined with PPK or contribution limits requires more detailed income allocation.")

  defp unsupported_label(:health_contribution_cap),
    do: gettext("A health contribution reduction under the 2021 rules may apply; this case is not calculated.")

  defp unsupported_label(:negative_payout),
    do: gettext("Deductions exceed the payout. Tax collection requires an individual payroll calculation.")

  defp unsupported_label(:insurance_status_change),
    do: gettext("Changes in mandate insurance status require separate calculations for each work period.")

  defp unsupported_label(:birthday), do: gettext("The employee's date of birth must not be after the payout date.")

  defp unsupported_label(:ppk_transfer_timing),
    do:
      gettext(
        "Only employer PPK transfers made in the payout month on or before payout can be included. Other transfers require separate tax collection."
      )

  defp unsupported_label(:rate_change),
    do: gettext("The hourly rate changed during this month. Add a document confirming the gross pay.")

  defp unsupported_label(:currency), do: gettext("Only payouts in PLN are supported.")
end
