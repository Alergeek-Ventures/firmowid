defmodule FirmowidWeb.DesignSystem.Components.TaxForecastSummary do
  @moduledoc """
  Planned monthly tax reserves from `Firmowid.Ash.Analysis.TaxForecast`.

  The summary is rendered apart from recorded documents, bank transactions and
  their totals. Unknown amounts and missing inputs stay visible instead of being
  shown as zero.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter
  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the reserves of one `TaxForecast.get/2` result.

  Pass `settings_path` only to viewers allowed to change the reserve assumptions.
  """
  @spec tax_forecast_summary(map()) :: Rendered.t()
  attr :id, :string, required: true
  attr :forecast, :map, required: true, doc: "The map returned by `TaxForecast.get/2`."
  attr :settings_path, :string, default: nil
  attr :class, :any, default: nil

  def tax_forecast_summary(assigns) do
    assigns =
      assign(
        assigns,
        :assumptions,
        Enum.uniq(assigns.forecast.assumptions ++ Enum.flat_map(assigns.forecast.taxes, & &1.assumptions))
      )

    ~H"""
    <section
      id={@id}
      aria-labelledby={@id <> "-title"}
      class={[
        "flex flex-col gap-4 rounded-xl border border-dashed border-grey-300 bg-white p-6",
        @class
      ]}
    >
      <div class="flex flex-col gap-1">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 id={@id <> "-title"} class="text-lg font-medium text-darkGrey">
            {gettext("Planned tax reserve")}
          </h2>
          <.status_badge status={@forecast.status} />
        </div>
        <p class="max-w-prose text-sm text-grey-700">
          {gettext(
            "A planning estimate from the invoices recorded in Firmowid. It is not a tax return, the tax due or a balance to pay, and it is not included in this month's totals."
          )}
        </p>
      </div>

      <div class="grid grid-cols-[repeat(auto-fit,minmax(min(100%,20rem),1fr))] gap-4">
        <.tax
          :for={tax <- @forecast.taxes}
          id={"#{@id}-#{tax.kind}"}
          tax={tax}
          currency={@forecast.currency}
          settings_path={@settings_path}
        />
      </div>

      <details id={@id <> "-assumptions"} class="text-sm text-grey-700">
        <summary class="w-fit cursor-pointer font-medium focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-turquoise-500 active:text-grey-900">
          {gettext("Assumptions")}
        </summary>
        <ul class="flex list-disc flex-col gap-1 ps-5 pbs-2">
          <li :for={assumption <- @assumptions}>{assumption_text(assumption)}</li>
        </ul>
      </details>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :tax, :map, required: true
  attr :currency, :string, required: true
  attr :settings_path, :string, default: nil

  defp tax(assigns) do
    ~H"""
    <article id={@id} class="flex flex-col gap-3 rounded-lg bg-grey-50 p-4">
      <div class="flex flex-col gap-1">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h3 class="font-medium text-grey-900">{tax_name(@tax.kind)}</h3>
          <.status_badge status={@tax.status} />
        </div>
        <p class="text-xs text-grey-600 tabular-nums">
          {gettext("Period: %{period}",
            period:
              TimeFormatter.format_date_range(@tax.liability_period.from, @tax.liability_period.to)
          )}
        </p>
      </div>

      <.reserve id={@id <> "-reserve"} tax={@tax} currency={@currency} />
      <.details tax={@tax} currency={@currency} />

      <ul
        :if={@tax.missing_inputs != []}
        id={@id <> "-missing"}
        class="flex list-disc flex-col gap-1 ps-5 text-sm text-orange-700"
      >
        <li :for={{input, count} <- missing_input_counts(@tax.missing_inputs)}>
          {missing_input_text(input, count)}
        </li>
      </ul>

      <.link
        :if={@tax.kind == :income_tax and @settings_path}
        kind="text"
        size="small"
        navigate={@settings_path}
        class="w-fit"
      >
        {gettext("Reserve assumptions in settings")}
        <Lucideicons.chevron_right />
      </.link>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :tax, :map, required: true
  attr :currency, :string, required: true

  defp reserve(%{tax: %{status: :not_applicable}} = assigns), do: ~H""

  defp reserve(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col gap-0.5">
      <span class="text-xs text-grey-600">{gettext("Reserve to set aside")}</span>
      <span :if={@tax.estimated_liability} class="text-2xl font-semibold text-grey-900 tabular-nums">
        {Money.new(@currency, @tax.estimated_liability)}
      </span>
      <span :if={is_nil(@tax.estimated_liability)} class="text-base text-grey-700">
        {if @tax.status == :partial,
          do: gettext("Not calculated: some data is missing"),
          else: gettext("Not calculated")}
      </span>
    </div>
    """
  end

  attr :tax, :map, required: true
  attr :currency, :string, required: true

  defp details(%{tax: %{kind: :vat, status: status}} = assigns) when status in [:complete, :partial] do
    ~H"""
    <dl class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
      <.detail label={gettext("VAT on sales")}>
        <.amount value={@tax.output_vat} currency={@currency} />
      </.detail>
      <.detail label={gettext("Deductible VAT on costs")}>
        <.amount value={@tax.input_vat} currency={@currency} />
      </.detail>
      <.detail
        :if={@tax.net_vat && Decimal.negative?(@tax.net_vat)}
        label={gettext("Excess deductible VAT")}
      >
        <.amount value={Decimal.negate(@tax.net_vat)} currency={@currency} />
      </.detail>
      <.detail label={gettext("Sales invoices included")}>
        {coverage_text(@tax.coverage.sales)}
      </.detail>
      <.detail label={gettext("Cost invoices included")}>
        {coverage_text(@tax.coverage.costs)}
      </.detail>
    </dl>
    """
  end

  defp details(%{tax: %{kind: :vat, status: :not_applicable}} = assigns) do
    ~H"""
    <p class="text-sm text-grey-700">{gettext("The company is not a VAT payer.")}</p>
    """
  end

  defp details(%{tax: %{kind: :income_tax, status: status}} = assigns) when status in [:complete, :partial] do
    ~H"""
    <dl class="grid grid-cols-[1fr_auto] gap-x-4 gap-y-1 text-sm">
      <.detail label={gettext("Reserve rate chosen by an administrator")}>
        {percent(@tax.income_reserve_rate)}
      </.detail>
      <.detail label={gettext("Base: net sales less invoice costs")}>
        <.amount value={@tax.reserve_base} currency={@currency} />
      </.detail>
      <.detail label={gettext("Sales invoices included")}>
        {coverage_text(@tax.coverage.sales)}
      </.detail>
      <.detail label={gettext("Cost invoices included")}>
        {coverage_text(@tax.coverage.costs)}
      </.detail>
    </dl>
    """
  end

  defp details(%{tax: %{status: :unavailable}} = assigns), do: ~H""

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp detail(assigns) do
    ~H"""
    <dt class="text-grey-700">{@label}</dt>
    <dd class="text-end text-grey-900 tabular-nums">{render_slot(@inner_block)}</dd>
    """
  end

  attr :value, :any, required: true, doc: "A Decimal amount, or nil when it is unknown."
  attr :currency, :string, required: true

  defp amount(%{value: nil} = assigns) do
    ~H"""
    <span class="text-grey-600">{pgettext("tax reserve amount", "Unknown")}</span>
    """
  end

  defp amount(assigns) do
    ~H"""
    {Money.new(@currency, @value)}
    """
  end

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "rounded-full px-3 py-1 text-sm/tight",
      @status == :complete && "bg-turquoise-100 text-turquoise-700",
      @status == :partial && "bg-orange-100 text-orange-700",
      @status in [:unavailable, :not_applicable] && "bg-grey-100 text-grey-700"
    ]}>
      {status_text(@status)}
    </span>
    """
  end

  defp status_text(:complete), do: pgettext("tax reserve status", "Data complete")
  defp status_text(:partial), do: pgettext("tax reserve status", "Data incomplete")
  defp status_text(:unavailable), do: pgettext("tax reserve status", "Unavailable")
  defp status_text(:not_applicable), do: pgettext("tax reserve status", "Not applicable")

  defp tax_name(:vat), do: gettext("VAT")
  defp tax_name(:income_tax), do: gettext("Income tax")

  defp coverage_text(coverage) do
    gettext("%{covered} of %{documents}",
      covered: coverage.covered,
      documents: coverage.documents
    )
  end

  # Shows the administrator's rate with its own precision, e.g. 19% or 8,5%.
  defp percent(rate) do
    rate
    |> Decimal.div(100)
    |> Firmowid.Cldr.Number.to_string!(
      format: :percent,
      fractional_digits: max(0, -Decimal.normalize(rate).exp)
    )
  end

  # Organization-level inputs have no entity; document inputs are counted per type and reason.
  defp missing_input_counts(missing_inputs) do
    Enum.frequencies_by(missing_inputs, &{Map.get(&1, :entity_type), &1.reason})
  end

  defp missing_input_text({nil, :vat_payer_status_missing}, _count),
    do: gettext("The company's VAT payer status is not set.")

  defp missing_input_text({nil, :income_tax_reserve_not_configured}, _count),
    do: gettext("No income tax reserve rate has been chosen.")

  defp missing_input_text({nil, :invoice_planning_cost_assumption_not_accepted}, _count),
    do: gettext("The cost assumption for the reserve has not been accepted.")

  defp missing_input_text({:cost_invoice, :deductible_cost_vat_missing}, count),
    do:
      ngettext(
        "%{count} cost invoice without recorded deductible VAT",
        "%{count} cost invoices without recorded deductible VAT",
        count
      )

  defp missing_input_text({:cost_invoice, :deductible_vat_currency_mismatch}, count),
    do:
      ngettext(
        "%{count} cost invoice with deductible VAT in neither PLN nor the invoice currency",
        "%{count} cost invoices with deductible VAT in neither PLN nor the invoice currency",
        count
      )

  defp missing_input_text({:cost_invoice, :unsupported_currency}, count),
    do:
      ngettext(
        "%{count} cost invoice in a currency outside NBP Table A",
        "%{count} cost invoices in currencies outside NBP Table A",
        count
      )

  defp missing_input_text({:cost_invoice, :exchange_rate_unavailable}, count),
    do:
      ngettext(
        "%{count} cost invoice without an available NBP rate",
        "%{count} cost invoices without an available NBP rate",
        count
      )

  defp missing_input_text({:cost_invoice, :document_period_missing}, count),
    do:
      ngettext(
        "%{count} cost invoice without a sale or issue date",
        "%{count} cost invoices without a sale or issue date",
        count
      )

  defp missing_input_text({:sales_invoice, :unsupported_currency}, count),
    do:
      ngettext(
        "%{count} sales invoice in a currency outside NBP Table A",
        "%{count} sales invoices in currencies outside NBP Table A",
        count
      )

  defp missing_input_text({:sales_invoice, :exchange_rate_unavailable}, count),
    do:
      ngettext(
        "%{count} sales invoice without an available NBP rate",
        "%{count} sales invoices without an available NBP rate",
        count
      )

  defp missing_input_text({:sales_invoice, :document_period_missing}, count),
    do:
      ngettext(
        "%{count} sales invoice without a sale or issue date",
        "%{count} sales invoices without a sale or issue date",
        count
      )

  defp missing_input_text({:sales_invoice, :correction_reference_missing}, count),
    do:
      ngettext(
        "%{count} sales correction without the corrected invoice",
        "%{count} sales corrections without the corrected invoice",
        count
      )

  defp missing_input_text({:sales_invoice, :correction_currency_mismatch}, count),
    do:
      ngettext(
        "%{count} sales correction in a different currency than the corrected invoice",
        "%{count} sales corrections in a different currency than the corrected invoice",
        count
      )

  defp missing_input_text({:sales_invoice, :sales_items_missing}, count),
    do: ngettext("%{count} sales invoice without items", "%{count} sales invoices without items", count)

  defp missing_input_text({:sales_invoice, :sales_item_tax_data_missing}, count),
    do:
      ngettext(
        "%{count} sales invoice with an item missing its VAT rate, quantity or price",
        "%{count} sales invoices with an item missing its VAT rate, quantity or price",
        count
      )

  defp missing_input_text({:sales_invoice, :sales_item_net_data_missing}, count),
    do:
      ngettext(
        "%{count} sales invoice with an item missing its quantity or price",
        "%{count} sales invoices with an item missing its quantity or price",
        count
      )

  defp assumption_text(:planning_reserve_not_tax_return), do: gettext("This is a planning reserve, not a tax return.")

  defp assumption_text(:recorded_documents_only_not_a_complete_tax_register),
    do: gettext("Only invoices recorded in Firmowid are used. They are not a complete tax register.")

  defp assumption_text(:current_organization_vat_status_applied_to_requested_month),
    do: gettext("The company's current VAT status is applied to this month.")

  defp assumption_text(:sale_month_with_issue_date_fallback),
    do: gettext("Invoices count in their sale month, or in their issue month when the sale date is missing.")

  defp assumption_text(:corrections_use_their_own_sale_month_not_statutory_recognition),
    do: gettext("Corrections count in their own sale month, which may differ from the statutory settlement period.")

  defp assumption_text(:advance_payments_cash_accounting_and_special_vat_rules_not_modelled),
    do: gettext("Advance payments, cash accounting and special VAT schemes are not modelled.")

  defp assumption_text(:payment_reconciliation_does_not_filter_invoices),
    do: gettext("Invoices count whether or not they have been paid.")

  defp assumption_text(:verified_nbp_rate_by_invoice_dates_matches_renderer),
    do:
      gettext(
        "Invoices in currencies other than PLN are converted at the NBP Table A rate from the last business day before the earlier of their issue and sale dates, as on invoices issued in Firmowid; corrections use their own rate. An invoice without that rate counts as missing data, and no other rate is used."
      )

  defp assumption_text(:no_previous_period_carry_forward),
    do: gettext("Nothing is carried forward from previous periods.")

  defp assumption_text(:no_tax_payment_allocation_or_remaining_balance),
    do: gettext("Tax payments already made are not deducted, so this is not a balance to pay.")

  defp assumption_text(:admin_configured_reserve_rate_not_a_pit_or_cit_rate),
    do: gettext("The reserve rate is chosen by an administrator and is not a PIT or CIT rate.")

  defp assumption_text(:all_invoice_payment_amounts_less_recorded_deductible_vat_accepted_as_planning_costs),
    do: gettext("Every cost invoice counts as a cost: its payment amount less the recorded deductible VAT.")

  defp assumption_text(:non_deductible_vat_and_settlement_charges_remain_planning_costs),
    do: gettext("Non-deductible VAT and settlement charges stay in the costs.")

  defp assumption_text(:standalone_bank_costs_payroll_and_tax_adjustments_not_included),
    do: gettext("Bank costs without an invoice, payroll and tax adjustments are not included.")

  defp assumption_text(:monthly_positive_base_only_no_loss_or_allowance_carry_forward),
    do: gettext("Only a positive monthly base is used. Losses and allowances are not carried forward.")
end
