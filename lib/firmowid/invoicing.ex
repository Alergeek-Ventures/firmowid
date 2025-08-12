defmodule Firmowid.Invoicing do
  @moduledoc false
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Firmowid.CostInvoices
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Finances
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.Matching
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice

  require Logger

  def authorize(:read, %{role: :admin}, _), do: true
  def authorize(:show, %{role: :admin}, _), do: true
  def authorize(:update, %{role: :admin}, _), do: true
  def authorize(:upload, %{role: :admin}, _), do: true
  def authorize(_, _, _), do: false

  @pubsub_topic "invoicing_broadcast"

  def subscribe_invoicing_broadcast(organization_id) do
    Phoenix.PubSub.subscribe(
      Firmowid.PubSub,
      "#{@pubsub_topic}:#{organization_id}"
    )
  end

  defp broadcast_cost_invoice_match(organization_id, cost_invoice, transaction) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@pubsub_topic}:#{organization_id}",
      {:cost_invoice_match,
       %{
         cost_invoice: cost_invoice,
         transaction: transaction
       }}
    )
  end

  @doc """
  Returns all months with invoicing entries - so all months where Firmowid can function.
  Useful e.g. for the invoicing live view's date picker.
  """
  def get_all_months_with_invoicing_entries do
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
      from(si in SalesInvoice,
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
      from(ci in CostInvoice,
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
    |> Enum.map(&DateTime.to_date(&1.date))
  end

  def get_invoicing_entries(from, to, filter) do
    case filter do
      :all ->
        [
          CostInvoices.list_cost_invoices(from, to),
          SalesInvoices.list_sales_invoices(from, to),
          Finances.list_transactions(from, to)
        ]
        |> Enum.concat()
        |> order_entries_for_display()

      :unmatched ->
        [
          CostInvoices.list_unmatched_cost_invoices(from, to),
          SalesInvoices.list_unmatched_sales_invoices(from, to),
          Finances.list_unmatched_transactions(from, to)
        ]
        |> Enum.concat()
        |> order_entries_for_display()

      :invoices ->
        from
        |> CostInvoices.list_cost_invoices(to)
        |> Enum.concat(SalesInvoices.list_sales_invoices(from, to))
        |> order_entries_for_display()

      :transactions ->
        from
        |> Finances.list_transactions(to)
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

  defp matched?(%SalesInvoice{} = invoice),
    do: length(invoice.transactions) > 0 or Map.get(invoice, :skip_invoicing, false)

  defp matched?(%CostInvoice{} = invoice),
    do: length(invoice.transactions) > 0 or Map.get(invoice, :skip_invoicing, false)

  defp matched?(%Transaction{} = transaction),
    do:
      length(transaction.sales_invoices_transactions ++ transaction.cost_invoices_transactions) > 0 or
        Map.get(transaction, :skip_invoicing, false)

  defp matched?(_), do: false

  def order_entries_for_display(invoicing_entries) do
    Enum.sort(invoicing_entries, fn a, b ->
      cond do
        matched?(a) != matched?(b) ->
          # unmatched first
          not matched?(a)

        get_date(a) != get_date(b) ->
          # newer first
          Date.after?(get_date(a), get_date(b))

        true ->
          a.id < b.id
      end
    end)
  end

  @spec get_potential_transactions_for_invoice(SalesInvoice.t() | CostInvoice.t()) :: [map()]
  def get_potential_transactions_for_invoice(invoice) do
    unmatched_transactions =
      Finances.list_unmatched_transactions(~D[2000-01-01], ~D[2100-12-30])

    attached_transactions = Map.get(invoice, :transactions, [])

    # Combine and deduplicate by transaction id
    all_transactions = Enum.uniq_by(unmatched_transactions ++ attached_transactions, & &1.id)

    score_and_sort_transactions(invoice, all_transactions)
  end

  def match_cost_invoices(organization_id) do
    Repo.put_org_id(organization_id)

    unmatched_cost_invoices = CostInvoices.list_unmatched_cost_invoices()

    Enum.each(unmatched_cost_invoices, &match_cost_invoice(&1.id, organization_id))
  end

  def match_cost_invoice(cost_invoice_id, organization_id) do
    Repo.put_org_id(organization_id)

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

          broadcast_cost_invoice_match(
            organization_id,
            cost_invoice,
            transaction
          )

          Logger.info("Matched cost invoice #{cost_invoice.id} with transaction #{transaction.id}")
        else
          Logger.info("No confident match for cost invoice #{cost_invoice.id}")
        end

      [] ->
        Logger.info("No match found for cost invoice #{cost_invoice.id}")
    end
  end

  defp score_and_sort_transactions(invoice, transactions) do
    invoice
    |> Matching.Windowing.pre_filter_invoice_transactions(transactions)
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

  def match_sales_invoices(organization_id) do
    Repo.put_org_id(organization_id)

    unmatched_sales_invoices = SalesInvoices.list_unmatched_sales_invoices()

    Enum.each(unmatched_sales_invoices, &match_sales_invoice(&1.id, organization_id))
  end

  def match_sales_invoice(sales_invoice_id, organization_id) do
    Repo.put_org_id(organization_id)

    sales_invoice = SalesInvoices.get_sales_invoice(sales_invoice_id)

    Logger.info("Matching sales invoice #{sales_invoice.id} for organization #{organization_id}")

    unmatched_transactions =
      Finances.list_unmatched_transactions(~D[2000-01-01], ~D[2100-12-30])

    Logger.info("Found #{length(unmatched_transactions)} unmatched transactions")

    case score_and_sort_transactions(sales_invoice, unmatched_transactions) do
      [{transaction, prediction_score} | _] ->
        Logger.info("Prediction score: #{prediction_score}")

        if Matching.RegressionPredictor.confident_match?(prediction_score) do
          SalesInvoices.create_sales_invoices_transactions_connection(
            sales_invoice.id,
            transaction.id,
            organization_id
          )

          Logger.info("Matched sales invoice #{sales_invoice.id} with transaction #{transaction.id}")
        else
          Logger.info("No confident match for sales invoice #{sales_invoice.id}")
        end

      [] ->
        Logger.info("No match found for sales invoice #{sales_invoice.id}")
    end
  end
end
