defmodule Firmowid.Analysis.TaxForecastCalculator do
  @moduledoc """
  Pure invoice planning calculation in PLN, independent of cash reconciliation.

  A sales correction stores the entire state after the correction, so its VAT
  contribution is the difference from `reference_invoice`, not its full value.
  Each document is assigned to its own sale month (issue month if absent), even
  for corrections. This is a planning convention, not a VAT recognition rule.
  Cost input VAT is used only when explicitly recorded as deductible for planning.
  Foreign amounts use verified document-date NBP context, never a current-rate
  fallback. Like InvoiceRenderer, corrections convert both states at the
  correction's rate, rounding each VAT group separately. This convention also
  applies to planning revenue; it is not statutory PIT/CIT/VAT recognition.
  """

  alias Firmowid.Ksef.VatRate

  # Same FA(3) rounding groups used by VerifyImportedDocument and InvoiceRenderer.
  @vat_groups [["23", "22"], ["8", "7"], ["5"], ["4"], ["3"]]
  @assumptions [
    :planning_reserve_not_tax_return,
    :recorded_documents_only_not_a_complete_tax_register,
    :current_organization_vat_status_applied_to_requested_month,
    :sale_month_with_issue_date_fallback,
    :corrections_use_their_own_sale_month_not_statutory_recognition,
    :advance_payments_cash_accounting_and_special_vat_rules_not_modelled,
    :payment_reconciliation_does_not_filter_invoices,
    :verified_nbp_rate_by_invoice_dates_matches_renderer,
    :no_previous_period_carry_forward,
    :no_tax_payment_allocation_or_remaining_balance
  ]

  @doc """
  Calculates a month's planning rows from loaded items and correction references.

  Optional conversion context is keyed by `{entity_type, document_id}` with
  `{:ok, NBP_metadata}` or `{:error, missing_input}` values. NBP metadata contains
  the float rate, currency, conversion date, effective date and table number.
  A foreign document without context remains incomplete, never assumed PLN.
  """
  @spec calculate(Date.t(), boolean() | nil, [map()], [map()], map() | nil, map()) :: map()
  def calculate(month, is_vat_payer, sales, costs, settings \\ nil, conversions \\ %{}) do
    month = Date.beginning_of_month(month)
    period = %{from: month, to: Date.end_of_month(month)}
    sales = Enum.filter(sales, &in_month?(&1, month))
    costs = Enum.filter(costs, &in_month?(&1, month))
    vat = vat_row(is_vat_payer, sales, costs, period, conversions)

    income = income_row(settings, sales, costs, period, conversions)
    taxes = [vat, income]

    %{
      month: month,
      as_of: DateTime.utc_now(),
      currency: "PLN",
      purpose: :planning_reserve,
      exchange_rates:
        Enum.flat_map(conversions, fn
          {{type, id}, {:ok, metadata}} -> [Map.merge(metadata, %{entity_type: type, id: id})]
          {_key, {:error, _reason}} -> []
        end),
      status:
        if(Enum.all?(taxes, &(&1.status in [:complete, :not_applicable])),
          do: :complete,
          else: :partial
        ),
      taxes: taxes,
      assumptions: @assumptions
    }
  end

  defp income_row(
         %{income_reserve_rate: %Decimal{} = rate, invoice_costs_deductible: true},
         sales,
         costs,
         period,
         conversions
       ) do
    revenue = coverage(sales, :sales_invoice, &sales_value(&1, :net, conversions))
    expenses = coverage(costs, :cost_invoice, &planning_cost(&1, conversions))
    missing = revenue.missing ++ expenses.missing
    base = if missing == [], do: Decimal.add(revenue.known_amount, expenses.known_amount)

    reserve =
      if base do
        base
        |> Decimal.max(Decimal.new(0))
        |> Decimal.mult(rate)
        |> Decimal.div(100)
        |> Decimal.round(2)
      end

    :income_tax
    |> row(if(missing == [], do: :complete, else: :partial), period, missing)
    |> Map.merge(%{
      estimated_liability: reserve,
      reserve_base: base,
      income_reserve_rate: rate,
      coverage: %{sales: revenue, costs: expenses},
      assumptions:
        @assumptions ++
          [
            :admin_configured_reserve_rate_not_a_pit_or_cit_rate,
            :all_invoice_payment_amounts_less_recorded_deductible_vat_accepted_as_planning_costs,
            :non_deductible_vat_and_settlement_charges_remain_planning_costs,
            :standalone_bank_costs_payroll_and_tax_adjustments_not_included,
            :monthly_positive_base_only_no_loss_or_allowance_carry_forward
          ]
    })
  end

  defp income_row(settings, _sales, _costs, period, _conversions) do
    settings = settings || %{}

    missing =
      Enum.flat_map(
        [
          {is_nil(settings[:income_reserve_rate]), :income_tax_reserve_not_configured},
          {settings[:invoice_costs_deductible] != true, :invoice_planning_cost_assumption_not_accepted}
        ],
        fn
          {true, reason} -> [%{reason: reason}]
          {false, _reason} -> []
        end
      )

    row(:income_tax, :unavailable, period, missing)
  end

  defp vat_row(false, _sales, _costs, period, _conversions), do: row(:vat, :not_applicable, period, [])

  defp vat_row(nil, _sales, _costs, period, _conversions),
    do: row(:vat, :unavailable, period, [%{reason: :vat_payer_status_missing}])

  defp vat_row(true, sales, costs, period, conversions) do
    output = coverage(sales, :sales_invoice, &sales_value(&1, :vat, conversions))
    input = coverage(costs, :cost_invoice, &cost_vat(&1, conversions))
    missing = output.missing ++ input.missing
    complete? = missing == []
    status = if complete?, do: :complete, else: :partial

    net = if complete?, do: Decimal.sub(output.known_amount, input.known_amount)

    :vat
    |> row(status, period, missing)
    |> Map.merge(%{
      estimated_liability: net && Decimal.max(net, Decimal.new(0)),
      net_vat: net,
      output_vat: if(output.missing == [], do: output.known_amount),
      input_vat: if(input.missing == [], do: input.known_amount),
      coverage: %{sales: output, costs: input}
    })
  end

  defp row(kind, status, period, missing) do
    %{
      kind: kind,
      status: status,
      estimated_liability: nil,
      liability_period: period,
      remaining_to_pay: nil,
      missing_inputs: missing,
      assumptions: @assumptions
    }
  end

  # Undated documents cannot safely be assigned to another month: flag them as
  # missing inputs rather than quietly claiming complete coverage for this month.
  defp in_month?(invoice, month) do
    case invoice.sale_date || invoice.issue_date do
      nil -> true
      date -> Date.beginning_of_month(date) == month
    end
  end

  defp coverage(invoices, type, calculate) do
    Enum.reduce(
      invoices,
      %{documents: length(invoices), covered: 0, known_amount: Decimal.new(0), missing: []},
      fn
        invoice, acc ->
          result =
            if is_nil(invoice.sale_date) and is_nil(invoice.issue_date),
              do: {:error, :document_period_missing},
              else: calculate.(invoice)

          case result do
            {:ok, amount} ->
              %{
                acc
                | covered: acc.covered + 1,
                  known_amount: Decimal.add(acc.known_amount, amount)
              }

            {:error, reason} ->
              details = if is_map(reason), do: reason, else: %{reason: reason}
              missing = Map.merge(details, %{entity_type: type, id: invoice.id})
              %{acc | missing: acc.missing ++ [missing]}
          end
      end
    )
  end

  defp sales_value(%{ksef_invoice_kind: :vat} = invoice, field, conversions) do
    with {:ok, rate} <- conversion_rate(invoice, :sales_invoice, invoice.currency, conversions) do
      snapshot_value(invoice, field, rate)
    end
  end

  defp sales_value(%{ksef_invoice_kind: :kor, reference_invoice: nil}, _field, _conversions),
    do: {:error, :correction_reference_missing}

  defp sales_value(%{ksef_invoice_kind: :kor, reference_invoice: reference} = invoice, field, conversions) do
    with true <- invoice.currency == reference.currency,
         {:ok, rate} <- conversion_rate(invoice, :sales_invoice, invoice.currency, conversions),
         {:ok, after_value} <- snapshot_value(invoice, field, rate),
         {:ok, before_value} <- snapshot_value(reference, field, rate) do
      {:ok, Decimal.sub(after_value, before_value)}
    else
      false -> {:error, :correction_currency_mismatch}
      {:error, reason} -> {:error, reason}
    end
  end

  defp snapshot_value(%{sales_invoice_items: []}, _field, _rate), do: {:error, :sales_items_missing}

  defp snapshot_value(%{sales_invoice_items: items}, :net, rate) do
    if Enum.all?(items, &(not is_nil(&1.quantity) and not is_nil(&1.unit_price))) do
      net =
        Enum.reduce(
          items,
          Decimal.new(0),
          &Decimal.add(Decimal.mult(&1.quantity, &1.unit_price), &2)
        )

      {:ok, to_pln(Decimal.round(net, 2), rate)}
    else
      {:error, :sales_item_net_data_missing}
    end
  end

  defp snapshot_value(%{sales_invoice_items: items}, :vat, rate) do
    if Enum.all?(
         items,
         &(VatRate.valid?(&1.vat_rate) and not is_nil(&1.quantity) and not is_nil(&1.unit_price))
       ) do
      total =
        Enum.reduce(@vat_groups, Decimal.new(0), fn rates, total ->
          group =
            items
            |> Enum.filter(&(&1.vat_rate in rates))
            |> Enum.reduce(Decimal.new(0), fn item, sum ->
              vat =
                item.quantity
                |> Decimal.mult(item.unit_price)
                |> Decimal.mult(VatRate.to_numeric(item.vat_rate))
                |> Decimal.div(100)

              Decimal.add(sum, vat)
            end)
            |> Decimal.round(2)
            |> to_pln(rate)

          Decimal.add(total, group)
        end)

      {:ok, total}
    else
      {:error, :sales_item_tax_data_missing}
    end
  end

  defp cost_vat(%{deductible_vat_amount: nil}, _conversions), do: {:error, :deductible_cost_vat_missing}

  defp cost_vat(%{deductible_vat_amount: %Money{currency: :PLN, amount: amount}}, _conversions),
    do: {:ok, Decimal.round(amount, 2)}

  defp cost_vat(
         %{deductible_vat_amount: %Money{currency: currency, amount: amount}, amount: %Money{currency: currency}} =
           invoice,
         conversions
       ) do
    with {:ok, rate} <- conversion_rate(invoice, :cost_invoice, to_string(currency), conversions) do
      {:ok, to_pln(amount, rate)}
    end
  end

  defp cost_vat(_invoice, _conversions), do: {:error, :deductible_vat_currency_mismatch}

  # Cost amount uses the bank sign (negative for a purchase); input VAT uses the
  # deduction sign (positive for a purchase). Adding removes deductible VAT from
  # the signed expense. Corrections follow the same formula with signed deltas.
  defp planning_cost(invoice, conversions) do
    with {:ok, vat} <- cost_vat(invoice, conversions),
         {:ok, rate} <-
           conversion_rate(
             invoice,
             :cost_invoice,
             to_string(invoice.amount.currency),
             conversions
           ) do
      {:ok, Decimal.add(to_pln(invoice.amount.amount, rate), vat)}
    end
  end

  defp conversion_rate(_invoice, _type, "PLN", _conversions), do: {:ok, Decimal.new(1)}

  defp conversion_rate(invoice, type, currency, conversions) do
    missing = {:error, %{reason: :exchange_rate_unavailable, currency: currency, rate_date: nil}}

    case Map.get(conversions, {type, invoice.id}, missing) do
      {:ok, %{rate: rate}} -> {:ok, Decimal.from_float(rate)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp to_pln(amount, rate), do: amount |> Decimal.mult(rate) |> Decimal.round(2)
end
