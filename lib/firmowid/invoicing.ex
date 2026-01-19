defmodule Firmowid.Invoicing do
  @moduledoc false
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false
  import Paradex, only: [~>: 2]

  alias Firmowid.CostInvoices
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Finances
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.Matching
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice
  alias FirmowidWeb.InvoicingLive.TransactionGroup

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
  Searches for invoices based on the provided parameters.
  It can search both sales and cost invoices, depending on the parameters.
  If query is provided, ranks by relevance, if not, by most recent.
  - `params` is a map that can include:
    - `include_sales`: `boolean` - default `true`
    - `include_cost`: `boolean` - default `true`
    - `query`: `String` - searched against:
      - in cost invoices:
        - seller name, seller display name, description, invoice identifier (fuzzy match)
      - in sales invoices:
        - buyer display name, buyer name, buyer surname, invoice number, item names (fuzzy match)
        - buyer email, buyer description (strict match of one "word", words are separated by spaces or punctuation etc.)
        - buyer NIP (strict match)
    - `currency`: `String` - filter by currency
    - `only_unmatched`: `boolean` - if true, only unmatched invoices are included
    - `amount_gt`: `Decimal` - filter by minimum amount
    - `amount_lt`: `Decimal` - filter by maximum amount
    - `date_from`: `Date` - filter by issue date from this date
    - `date_to`: `Date` - filter by issue date to this date

    - Sales invoice only filters:
      - `buyer_type`: `atom` - filter by buyer type (`:individual` or `:company`)
      - `is_cash`: `boolean` - if true, only cash account invoices are included
      - `is_reverse_charge`: `boolean` - if true, only reverse charge invoices are included
  """
  def search_invoices(params \\ %{}) do
    include_sales = Map.get(params, :include_sales, true)
    include_cost = Map.get(params, :include_cost, true)
    query = Map.get(params, :query)

    include_cost =
      if not is_nil(Map.get(params, :buyer_type)) or not is_nil(Map.get(params, :is_cash)) or
           not is_nil(Map.get(params, :is_reverse_charge)) do
        false
      else
        include_cost
      end

    # From prebuilt queries, select just the id, type, date and bm25 score (to hydrate later)
    # This is needed because if we got whole structs, union_all on different schemas doesn't work
    # And we need to subquery to order by score
    cost_query =
      if include_cost do
        base = build_cost_invoice_query(params)

        if query in [nil, ""] do
          select(base, [ci], %{
            id: ci.id,
            type: "cost",
            date: ci.issue_date,
            score: 0.0,
            organization_id: ci.organization_id
          })
        else
          select(base, [ci], %{
            id: ci.id,
            type: "cost",
            date: ci.issue_date,
            score: fragment("pdb.score(?)", ci.id),
            organization_id: ci.organization_id
          })
        end
      end

    sales_query =
      if include_sales do
        base = build_sales_invoice_query(params)

        if query in [nil, ""] do
          select(base, [si], %{
            id: si.id,
            type: "sales",
            date: si.issue_date,
            score: 0.0,
            organization_id: si.organization_id
          })
        else
          select(base, [si], %{
            id: si.id,
            type: "sales",
            date: si.issue_date,
            score: fragment("pdb.score(?)", si.id),
            organization_id: si.organization_id
          })
        end
      end

    queries = Enum.filter([cost_query, sales_query], fn q -> not is_nil(q) end)

    unified_query =
      case queries do
        [single] ->
          single

        [first, second] ->
          union_all(first, ^second)

        [] ->
          from(cost_invoice in CostInvoice,
            where: false,
            select: %{id: nil, type: nil, date: nil, score: nil, organization_id: nil}
          )
      end

    # For performance, reduced into two maps, hydrated all of one type at once, and reassembled list
    base =
      unified_query
      |> subquery()
      |> order_by(
        ^if query in [nil, ""] do
          [desc: :date]
        else
          [desc: :score]
        end
      )
      |> limit(50)

    # Paradedb @@@ (~> in Ecto) operator needs this, otherwise "Postgres expressions not solved" error
    results = Repo.all(base, prepare: :unnamed)

    hydrate_search_results(results)
  end

  defp build_cost_invoice_query(params) do
    query = Map.get(params, :query)
    only_unmatched = Map.get(params, :only_unmatched, false)
    currency = Map.get(params, :currency)
    amount_gt = Map.get(params, :amount_gt)
    amount_lt = Map.get(params, :amount_lt)
    date_from = Map.get(params, :date_from)
    date_to = Map.get(params, :date_to)

    base_query = from(cost_invoice in CostInvoice, as: :cost_invoice)

    base_query =
      if only_unmatched do
        base_query
        |> join(:left, [cost_invoice], t in assoc(cost_invoice, :transactions))
        |> where([cost_invoice, t], is_nil(t.id))
        |> where([cost_invoice], cost_invoice.skip_invoicing == false)
      else
        base_query
      end

    base_query =
      if currency,
        do: where(base_query, [cost_invoice], cost_invoice.currency == ^currency),
        else: base_query

    base_query =
      if amount_gt,
        do: where(base_query, [cost_invoice], cost_invoice.total_amount >= ^amount_gt),
        else: base_query

    base_query =
      if amount_lt,
        do: where(base_query, [cost_invoice], cost_invoice.total_amount <= ^amount_lt),
        else: base_query

    base_query =
      if date_from,
        do: where(base_query, [cost_invoice], cost_invoice.issue_date >= ^date_from),
        else: base_query

    base_query =
      if date_to,
        do: where(base_query, [cost_invoice], cost_invoice.issue_date <= ^date_to),
        else: base_query

    if query in [nil, ""] do
      base_query
    else
      search_dynamic =
        Enum.reduce(
          [
            dynamic([cost_invoice], cost_invoice.seller ~> ^query),
            dynamic([cost_invoice], cost_invoice.seller_display_name ~> ^query),
            dynamic([cost_invoice], cost_invoice.description ~> ^query),
            dynamic([cost_invoice], cost_invoice.invoice_identifier ~> ^query)
          ],
          fn expr, acc -> dynamic([cost_invoice], ^acc or ^expr) end
        )

      where(base_query, ^search_dynamic)
    end
  end

  defp build_sales_invoice_query(params) do
    query = Map.get(params, :query)
    only_unmatched = Map.get(params, :only_unmatched)
    currency = Map.get(params, :currency)
    amount_gt = Map.get(params, :amount_gt)
    amount_lt = Map.get(params, :amount_lt)
    date_from = Map.get(params, :date_from)
    date_to = Map.get(params, :date_to)
    buyer_type = Map.get(params, :buyer_type)
    is_cash_account = Map.get(params, :is_cash)
    is_reverse_charge = Map.get(params, :is_reverse_charge)

    base_query = from(SalesInvoice, as: :sales_invoice)

    needs_items_join = not is_nil(amount_gt) or not is_nil(amount_lt)

    base_query =
      if needs_items_join do
        base_query
        |> join(
          :left,
          [sales_invoice],
          sales_invoice_item in assoc(sales_invoice, :sales_invoice_items)
        )
        |> group_by([sales_invoice], sales_invoice.id)
      else
        base_query
      end

    # equivalent to get_gross
    base_query =
      if amount_gt do
        having(
          base_query,
          [sales_invoice, sales_invoice_item],
          sum(
            sales_invoice_item.quantity * sales_invoice_item.unit_price *
              (1 + sales_invoice_item.vat_rate / 100)
          ) >= ^amount_gt
        )
      else
        base_query
      end

    base_query =
      if amount_lt do
        having(
          base_query,
          [sales_invoice, sales_invoice_item],
          sum(
            sales_invoice_item.quantity * sales_invoice_item.unit_price *
              (1 + sales_invoice_item.vat_rate / 100)
          ) <= ^amount_lt
        )
      else
        base_query
      end

    base_query =
      if only_unmatched do
        base_query
        |> where(
          [sales_invoice],
          fragment(
            "NOT EXISTS (SELECT 1 FROM sales_invoices_transactions WHERE sales_invoice_id = ?)",
            sales_invoice.id
          )
        )
        |> where([sales_invoice], sales_invoice.skip_invoicing == false)
      else
        base_query
      end

    base_query =
      if currency,
        do: where(base_query, [sales_invoice], sales_invoice.currency == ^currency),
        else: base_query

    base_query =
      if date_from,
        do: where(base_query, [sales_invoice], sales_invoice.issue_date >= ^date_from),
        else: base_query

    base_query =
      if date_to,
        do: where(base_query, [sales_invoice], sales_invoice.issue_date <= ^date_to),
        else: base_query

    base_query =
      if buyer_type,
        do: where(base_query, [sales_invoice], sales_invoice.buyer_type == ^buyer_type),
        else: base_query

    base_query =
      if is_cash_account,
        do: where(base_query, [sales_invoice], sales_invoice.is_cash_account == true),
        else: base_query

    base_query =
      if is_reverse_charge,
        do: where(base_query, [sales_invoice], sales_invoice.is_reverse_charge == true),
        else: base_query

    if query in [nil, ""] do
      base_query
    else
      search_dynamic =
        Enum.reduce(
          [
            dynamic([sales_invoice], sales_invoice.buyer_display_name ~> ^query),
            dynamic([sales_invoice], sales_invoice.buyer_name ~> ^query),
            dynamic([sales_invoice], sales_invoice.buyer_surname ~> ^query),
            dynamic([sales_invoice], sales_invoice.invoice_number ~> ^query),
            dynamic([sales_invoice], sales_invoice.buyer_email ~> ^query),
            dynamic([sales_invoice], sales_invoice.buyer_description ~> ^query),
            dynamic([sales_invoice], sales_invoice.buyer_id ~> ^query),
            dynamic([sales_invoice], sales_invoice.item_names ~> ^query)
          ],
          fn expr, acc -> dynamic([sales_invoice], ^acc or ^expr) end
        )

      where(base_query, ^search_dynamic)
    end
  end

  defp hydrate_search_results(results) do
    grouped_by_type = Enum.group_by(results, fn i -> i.type end)

    cost_invoice_ids =
      Enum.map(grouped_by_type["cost"] || [], fn i -> i.id end)

    sales_invoice_ids =
      Enum.map(grouped_by_type["sales"] || [], fn i -> i.id end)

    hydrated_cost_invoices =
      if Enum.any?(cost_invoice_ids) do
        from(cost_invoice in CostInvoice,
          where: cost_invoice.id in ^cost_invoice_ids,
          preload: [:transactions]
        )
        |> Repo.all()
        |> Map.new(fn i -> {i.id, i} end)
      else
        %{}
      end

    hydrated_sales_invoices =
      if Enum.any?(sales_invoice_ids) do
        from(sales_invoice in SalesInvoice,
          where: sales_invoice.id in ^sales_invoice_ids,
          preload: [:transactions, :sales_invoice_items]
        )
        |> Repo.all()
        |> Map.new(fn i -> {i.id, i} end)
      else
        %{}
      end

    results
    |> Enum.map(fn raw ->
      case raw.type do
        "cost" -> Map.get(hydrated_cost_invoices, raw.id)
        "sales" -> Map.get(hydrated_sales_invoices, raw.id)
      end
    end)
    |> Enum.reject(&is_nil/1)
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

  defp get_date(%TransactionGroup{date: date}), do: date

  defp matched?(%SalesInvoice{} = invoice),
    do: Enum.any?(invoice.transactions) or Map.get(invoice, :skip_invoicing, false)

  defp matched?(%CostInvoice{} = invoice), do: Enum.any?(invoice.transactions) or Map.get(invoice, :skip_invoicing, false)

  defp matched?(%Transaction{} = transaction),
    do:
      Enum.any?(transaction.sales_invoices_transactions ++ transaction.cost_invoices_transactions) or
        Map.get(transaction, :skip_invoicing, false)

  defp matched?(%TransactionGroup{}) do
    # Groups only contain unmatched transactions by design
    false
  end

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
