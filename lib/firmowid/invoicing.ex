defmodule Firmowid.Invoicing do
  alias Firmowid.Accounts.User
  alias Akin
  alias OpenAI

  alias Firmowid.CostInvoices
  alias Firmowid.Finances
  alias Firmowid.SalesInvoices

  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Finances.Transaction

  alias Firmowid.Invoicing.Matching

  require Logger

  alias Firmowid.Repo
  import Ecto.Query, warn: false

  @behaviour Bodyguard.Policy

  def authorize(_, %User{role: :admin}, _), do: true

  def authorize(_, _, _), do: false

  @doc """
  Returns all months with invoicing entries - so all months where Firmowid can function.
  Useful e.g. for the invoicing live view's date picker.
  """
  def get_all_months_with_invoicing_entries() do
    transactions_query =
      from(t in Transaction,
        select: %{
          date_string:
            fragment(
              "date_trunc('month', ?)",
              t.booking_date
            ),
          organization_id: t.organization_id
        }
      )

    sales_invoices_query =
      from(si in Firmowid.SalesInvoices.SalesInvoice,
        select: %{
          date_string:
            fragment(
              "date_trunc('month', ?)",
              si.issue_date
            ),
          organization_id: si.organization_id
        }
      )

    cost_invoices_query =
      from(ci in Firmowid.CostInvoices.CostInvoice,
        select: %{
          date_string:
            fragment(
              "date_trunc('month', ?)",
              ci.issue_date
            ),
          organization_id: ci.organization_id
        }
      )

    union_query =
      transactions_query
      |> union(^sales_invoices_query)
      |> union(^cost_invoices_query)

    from(u in subquery(union_query),
      select: %{
        date: u.date_string
      },
      distinct: true
    )
    |> Repo.all()
    |> Enum.map(& &1.date)
  end

  def get_invoicing_entries(from, to, filter) do
    case filter do
      :all ->
        Enum.concat([
          CostInvoices.list_cost_invoices(from, to),
          SalesInvoices.list_sales_invoices(from, to),
          Finances.list_transactions(from, to)
        ])
        |> order_entries_for_display()

      :unmatched ->
        Enum.concat([
          CostInvoices.list_unmatched_cost_invoices(from, to),
          SalesInvoices.list_unmatched_sales_invoices(from, to),
          Finances.list_unmatched_transactions(from, to)
        ])
        |> order_entries_for_display()

      :invoices ->
        Enum.concat(
          CostInvoices.list_cost_invoices(from, to),
          SalesInvoices.list_sales_invoices(from, to)
        )
        |> order_entries_for_display()

      :transactions ->
        Finances.list_transactions(from, to)
        |> order_entries_for_display()
    end
  end

  defp get_date(%SalesInvoice{} = invoice) do
    invoice.issue_date
  end

  defp get_date(%CostInvoice{} = invoice) do
    invoice.issue_date
  end

  defp get_date(%Transaction{} = transaction) do
    transaction.booking_date
  end

  def order_entries_for_display(invoicing_entries) do
    order_by_date = fn a, b ->
      a_date = get_date(a)
      b_date = get_date(b)

      case Date.compare(a_date, b_date) do
        :gt ->
          true

        :lt ->
          false

        :eq ->
          a.id < b.id
      end
    end

    invoicing_entries
    |> Enum.sort_by(& &1, order_by_date)
  end

  def match_with_transaction_combo(
        issue_date,
        due_date,
        total_amount
      ) do
    # when there are multiple transactions on the same invoice
    # typically - services / goods that you get across the month

    # highly experimental!

    issue_date = issue_date |> Date.add(-35)
    due_date = due_date |> Date.add(7)

    all_found =
      Finances.list_unmatched_transactions(issue_date, due_date)
      |> Enum.group_by(
        &%{
          creditor_name: &1.creditor_name,
          year_month: "#{&1.booking_date.year}-#{&1.booking_date.month}"
        }
      )
      |> Enum.map(fn
        {%{creditor_name: creditor_name, year_month: year_month}, transactions} ->
          %{
            id: UUIDv7.generate(),
            creditor_name: creditor_name,
            year_month: year_month,
            total_amount:
              Enum.reduce(transactions, Decimal.new(0), fn t, acc ->
                Decimal.add(t.transaction_amount, acc)
              end),
            currency: Enum.at(transactions, 0).transaction_currency,
            transactions: transactions
          }
      end)

    result =
      all_found
      |> Enum.filter(fn %{
                          total_amount: group_total_amount,
                          transactions: transactions
                        } ->
        is_amount_equal = Decimal.compare(group_total_amount, total_amount) == :eq
        is_a_group = length(transactions) > 1

        is_amount_equal and is_a_group
      end)

    # if we have multiple groups this means something went wrong :)
    case result do
      [%{transactions: transactions}] -> transactions
      _ -> nil
    end
  end

  @spec get_potential_transactions_for_invoice(%SalesInvoice{} | %CostInvoice{}) :: [map()]
  def get_potential_transactions_for_invoice(invoice) do
    unmatched_transactions =
      Finances.list_unmatched_transactions(~D[2000-01-01], ~D[2100-12-30])

    attached_transactions = Map.get(invoice, :transactions, [])

    # Combine and deduplicate by transaction id
    all_transactions =
      (unmatched_transactions ++ attached_transactions)
      |> Enum.uniq_by(& &1.id)

    score_and_sort_transactions(invoice, all_transactions)
  end

  def match_cost_invoices(organization_id) do
    Firmowid.Repo.put_org_id(organization_id)

    unmatched_cost_invoices = CostInvoices.list_unmatched_cost_invoices()

    unmatched_cost_invoices
    |> Enum.each(&match_cost_invoice(&1.id, organization_id))
  end

  def match_cost_invoice(cost_invoice_id, organization_id) do
    Firmowid.Repo.put_org_id(organization_id)

    cost_invoice = CostInvoices.get_cost_invoice!(cost_invoice_id)

    Logger.info("Matching cost invoice #{cost_invoice.id} for organization #{organization_id}")

    unmatched_transactions =
      Finances.list_unmatched_transactions(~D[2000-01-01], ~D[2100-12-30])

    Logger.info("Found #{length(unmatched_transactions)} unmatched transactions")

    case score_and_sort_transactions(cost_invoice, unmatched_transactions) do
      [{transaction, prediction_score} | _] ->
        Logger.info("Prediction score: #{prediction_score}")

        if Matching.RegressionPredictor.confident_match?(prediction_score) do
          CostInvoices.create_cost_invoices_transactions_connection(
            cost_invoice.id,
            transaction.id,
            organization_id
          )

          Logger.info(
            "Matched cost invoice #{cost_invoice.id} with transaction #{transaction.id}"
          )
        else
          Logger.info("No confident match for cost invoice #{cost_invoice.id}")
        end

      [] ->
        Logger.info("No match found for cost invoice #{cost_invoice.id}")
    end
  end

  defp score_and_sort_transactions(invoice, transactions) do
    Matching.Windowing.pre_filter_invoice_transactions(invoice, transactions)
    |> Enum.map(fn transaction ->
      features = Matching.ParametrizedResult.generate_parametrized_result(invoice, transaction)

      prediction_score =
        Matching.RegressionPredictor.score([
          features.days_lag_le_3,
          features.days_lag_le_7,
          features.days_lag_le_30,
          features.days_lag_gt_30,
          features.signed_amount_match,
          features.relative_amount_difference,
          features.transaction_side_similarity,
          features.bank_account_similarity,
          features.is_same_currency,
          features.amount_present_in_remittance_information_unstructured,
          features.invoice_identifier_present_in_remittance_information_unstructured
        ])

      {transaction, prediction_score}
    end)
    |> Enum.sort_by(fn {_, prediction_score} -> prediction_score end, :desc)
  end
end
