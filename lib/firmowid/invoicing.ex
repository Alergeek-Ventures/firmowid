defmodule Firmowid.Invoicing do
  @moduledoc false
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false
  import Paradex, only: [~>: 2]

  alias Firmowid.Ash.Finances.TransactionQueries
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction
  alias Firmowid.Ash.Invoicing.SalesInvoiceTransaction
  alias Firmowid.CostInvoices
  # SQL fragment that converts KSeF VAT rate string codes to numeric decimals.
  # Must match VatRate.to_numeric/1 behavior for consistency.
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.Matching
  alias Firmowid.Invoicing.TransactionGroup
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices
  alias Firmowid.SalesInvoices.SalesInvoice

  require Logger

  @vat_rate_to_decimal_sql """
  CASE ?
    WHEN '23' THEN 0.23
    WHEN '22' THEN 0.22
    WHEN '8' THEN 0.08
    WHEN '7' THEN 0.07
    WHEN '5' THEN 0.05
    WHEN '4' THEN 0.04
    WHEN '3' THEN 0.03
    ELSE 0
  END
  """
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
    query = Map.get(params, :query)
    include_cost = should_include_cost?(params)

    has_amount_filter = not is_nil(Map.get(params, :amount_gt)) or not is_nil(Map.get(params, :amount_lt))

    queries =
      Enum.filter(
        [
          include_cost && select_for_search(build_cost_invoice_query(params), "cost", query),
          Map.get(params, :include_sales, true) &&
            select_for_search(build_sales_invoice_query(params), "sales", query, has_amount_filter)
        ],
        & &1
      )

    unified_query = unify_queries(queries)

    order = if query in [nil, ""], do: [desc: :date], else: [desc: :score]

    # Paradedb @@@ (~> in Ecto) operator needs this, otherwise "Postgres expressions not solved" error
    unified_query
    |> subquery()
    |> order_by(^order)
    |> limit(50)
    |> Repo.all(prepare: :unnamed)
    |> hydrate_search_results()
  end

  defp should_include_cost?(params) do
    has_sales_only_filter =
      not is_nil(Map.get(params, :buyer_type)) or
        not is_nil(Map.get(params, :is_cash)) or
        not is_nil(Map.get(params, :is_reverse_charge))

    Map.get(params, :include_cost, true) and not has_sales_only_filter
  end

  defp select_for_search(base_query, type, query, has_group_by \\ false)

  defp select_for_search(base_query, type, query, _has_group_by) when query in [nil, ""] do
    select(base_query, [i], %{
      id: i.id,
      type: ^type,
      date: i.issue_date,
      score: 0.0,
      organization_id: i.organization_id
    })
  end

  # ParadeDB bug in v0.22.3/PG18: pdb.score() crashes with "no relation entry
  # for relid N" when used together with LEFT JOIN + GROUP BY. Wrapping in max()
  # works around it — the value is the same per grouped id anyway.
  defp select_for_search(base_query, type, _query, true = _has_group_by) do
    select(base_query, [i], %{
      id: i.id,
      type: ^type,
      date: i.issue_date,
      score: max(fragment("pdb.score(?)", i.id)),
      organization_id: i.organization_id
    })
  end

  defp select_for_search(base_query, type, _query, _has_group_by) do
    select(base_query, [i], %{
      id: i.id,
      type: ^type,
      date: i.issue_date,
      score: fragment("pdb.score(?)", i.id),
      organization_id: i.organization_id
    })
  end

  defp unify_queries([single]), do: single
  defp unify_queries([first, second]), do: union_all(first, ^second)

  defp unify_queries([]) do
    from(cost_invoice in CostInvoice,
      where: false,
      select: %{id: nil, type: nil, date: nil, score: nil, organization_id: nil}
    )
  end

  defp build_cost_invoice_query(params) do
    from(cost_invoice in CostInvoice, as: :cost_invoice)
    |> maybe_filter_unmatched_cost(Map.get(params, :only_unmatched, false))
    |> maybe_cost_filter(:currency, Map.get(params, :currency))
    |> maybe_cost_filter(:amount_gt, Map.get(params, :amount_gt))
    |> maybe_cost_filter(:amount_lt, Map.get(params, :amount_lt))
    |> maybe_cost_filter(:date_from, Map.get(params, :date_from))
    |> maybe_cost_filter(:date_to, Map.get(params, :date_to))
    |> maybe_search_cost_invoices(Map.get(params, :query))
  end

  defp maybe_filter_unmatched_cost(query, false), do: query
  defp maybe_filter_unmatched_cost(query, nil), do: query

  defp maybe_filter_unmatched_cost(query, _) do
    query
    |> join(:left, [cost_invoice], t in assoc(cost_invoice, :transactions))
    |> where([cost_invoice, t], is_nil(t.id))
    |> where([cost_invoice], cost_invoice.skip_invoicing == false)
  end

  defp maybe_cost_filter(query, _field, nil), do: query
  defp maybe_cost_filter(query, :currency, val), do: where(query, [ci], ci.currency == ^val)
  defp maybe_cost_filter(query, :amount_gt, val), do: where(query, [ci], ci.total_amount >= ^val)
  defp maybe_cost_filter(query, :amount_lt, val), do: where(query, [ci], ci.total_amount <= ^val)
  defp maybe_cost_filter(query, :date_from, val), do: where(query, [ci], ci.issue_date >= ^val)
  defp maybe_cost_filter(query, :date_to, val), do: where(query, [ci], ci.issue_date <= ^val)

  defp maybe_search_cost_invoices(query, search) when search in [nil, ""], do: query

  defp maybe_search_cost_invoices(query, search) do
    search_dynamic =
      Enum.reduce(
        [
          dynamic([cost_invoice], cost_invoice.seller ~> ^search),
          dynamic([cost_invoice], cost_invoice.seller_display_name ~> ^search),
          dynamic([cost_invoice], cost_invoice.description ~> ^search),
          dynamic([cost_invoice], cost_invoice.invoice_identifier ~> ^search)
        ],
        fn expr, acc -> dynamic([cost_invoice], ^acc or ^expr) end
      )

    where(query, ^search_dynamic)
  end

  defp build_sales_invoice_query(params) do
    amount_gt = Map.get(params, :amount_gt)
    amount_lt = Map.get(params, :amount_lt)

    from(SalesInvoice, as: :sales_invoice)
    |> where([sales_invoice], sales_invoice.ksef_invoice_kind == :vat)
    |> maybe_join_items_for_amount(amount_gt, amount_lt)
    |> maybe_sales_amount_filter(:gt, amount_gt)
    |> maybe_sales_amount_filter(:lt, amount_lt)
    |> maybe_filter_unmatched_sales(Map.get(params, :only_unmatched))
    |> maybe_sales_filter(:currency, Map.get(params, :currency))
    |> maybe_sales_filter(:date_from, Map.get(params, :date_from))
    |> maybe_sales_filter(:date_to, Map.get(params, :date_to))
    |> maybe_sales_filter(:buyer_type, Map.get(params, :buyer_type))
    |> maybe_sales_filter(:is_cash, Map.get(params, :is_cash))
    |> maybe_sales_filter(:is_reverse_charge, Map.get(params, :is_reverse_charge))
    |> maybe_search_sales_invoices(Map.get(params, :query))
  end

  defp maybe_join_items_for_amount(query, nil, nil), do: query

  defp maybe_join_items_for_amount(query, _amount_gt, _amount_lt) do
    query
    |> join(:left, [sales_invoice], sales_invoice_item in assoc(sales_invoice, :sales_invoice_items))
    |> group_by([sales_invoice], sales_invoice.id)
  end

  # Note: vat_rate is now a string (KSeF code), so we use a CASE expression
  # to convert it to numeric for gross calculation
  defp maybe_sales_amount_filter(query, _op, nil), do: query

  defp maybe_sales_amount_filter(query, :gt, amount) do
    having(
      query,
      [sales_invoice, sales_invoice_item],
      sum(
        sales_invoice_item.quantity * sales_invoice_item.unit_price *
          (1 + fragment(@vat_rate_to_decimal_sql, sales_invoice_item.vat_rate))
      ) >= ^amount
    )
  end

  defp maybe_sales_amount_filter(query, :lt, amount) do
    having(
      query,
      [sales_invoice, sales_invoice_item],
      sum(
        sales_invoice_item.quantity * sales_invoice_item.unit_price *
          (1 + fragment(@vat_rate_to_decimal_sql, sales_invoice_item.vat_rate))
      ) <= ^amount
    )
  end

  defp maybe_filter_unmatched_sales(query, nil), do: query
  defp maybe_filter_unmatched_sales(query, false), do: query

  defp maybe_filter_unmatched_sales(query, _) do
    query
    |> where(
      [si],
      fragment("NOT EXISTS (SELECT 1 FROM sales_invoices_transactions WHERE sales_invoice_id = ?)", si.id)
    )
    |> where([si], si.skip_invoicing == false)
  end

  defp maybe_sales_filter(query, _field, nil), do: query
  defp maybe_sales_filter(query, :currency, val), do: where(query, [si], si.currency == ^val)
  defp maybe_sales_filter(query, :date_from, val), do: where(query, [si], si.issue_date >= ^val)
  defp maybe_sales_filter(query, :date_to, val), do: where(query, [si], si.issue_date <= ^val)
  defp maybe_sales_filter(query, :buyer_type, val), do: where(query, [si], si.buyer_type == ^val)
  defp maybe_sales_filter(query, :is_cash, _), do: where(query, [si], si.is_cash_account == true)

  defp maybe_sales_filter(query, :is_reverse_charge, _), do: where(query, [si], si.is_reverse_charge == true)

  defp maybe_search_sales_invoices(query, search) when search in [nil, ""], do: query

  defp maybe_search_sales_invoices(query, search) do
    search_dynamic =
      Enum.reduce(
        [
          # BM25 search fields - must match columns in the index
          dynamic([sales_invoice], sales_invoice.buyer_full_name ~> ^search),
          dynamic([sales_invoice], sales_invoice.buyer_given_name ~> ^search),
          dynamic([sales_invoice], sales_invoice.buyer_surname ~> ^search),
          dynamic([sales_invoice], sales_invoice.invoice_number ~> ^search),
          dynamic([sales_invoice], sales_invoice.buyer_email ~> ^search),
          dynamic([sales_invoice], sales_invoice.buyer_description ~> ^search),
          dynamic([sales_invoice], sales_invoice.buyer_id ~> ^search),
          dynamic([sales_invoice], sales_invoice.item_names ~> ^search)
        ],
        fn expr, acc -> dynamic([sales_invoice], ^acc or ^expr) end
      )

    where(query, ^search_dynamic)
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
        sales_invoice_ids
        |> SalesInvoices.list_sales_invoices_by_ids()
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
          TransactionQueries.list_by_date_range(from, to)
        ]
        |> Enum.concat()
        |> order_entries_for_display()

      :unmatched ->
        [
          CostInvoices.list_unmatched_cost_invoices(from, to),
          SalesInvoices.list_unmatched_sales_invoices(from, to),
          TransactionQueries.list_unmatched(from, to)
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
        |> TransactionQueries.list_by_date_range(to)
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

  # Checks if invoice is a draft (no invoice number assigned)
  # Only applicable to SalesInvoice - other types are never drafts
  defp draft?(%SalesInvoice{} = invoice), do: SalesInvoice.draft?(invoice)
  defp draft?(_), do: false

  # Extracts invoice number for sorting - only SalesInvoice has invoice numbers
  defp get_invoice_number(%SalesInvoice{invoice_number: num}), do: num
  defp get_invoice_number(_), do: nil

  def order_entries_for_display(invoicing_entries) do
    Enum.sort(invoicing_entries, fn a, b ->
      cond do
        # Draft invoices first (only affects SalesInvoice)
        draft?(a) != draft?(b) ->
          draft?(a)

        matched?(a) != matched?(b) ->
          # unmatched first
          not matched?(a)

        get_date(a) != get_date(b) ->
          # newer first
          Date.after?(get_date(a), get_date(b))

        # Invoice number descending (only affects SalesInvoice)
        (inv_a = get_invoice_number(a)) != (inv_b = get_invoice_number(b)) ->
          inv_a >= inv_b

        true ->
          a.id < b.id
      end
    end)
  end

  @spec get_potential_transactions_for_invoice(SalesInvoice.t() | CostInvoice.t()) :: [map()]
  def get_potential_transactions_for_invoice(invoice) do
    unmatched_transactions =
      TransactionQueries.list_unmatched(~D[2000-01-01], ~D[2100-12-30])

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
      TransactionQueries.list_unmatched(~D[2000-01-01], ~D[2100-12-30])

    Logger.info("Found #{length(unmatched_transactions)} unmatched transactions")

    case score_and_sort_transactions(cost_invoice, unmatched_transactions) do
      [{transaction, prediction_score} | _] ->
        Logger.info("Prediction score: #{prediction_score}")

        if Matching.RegressionPredictor.confident_match?(prediction_score) do
          # TODO: replace authorize?: false + actor: %{} with system actor once available
          CostInvoiceTransaction.create_connections(
            [cost_invoice.id],
            [transaction.id],
            organization_id,
            authorize?: false,
            actor: %{}
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
      TransactionQueries.list_unmatched(~D[2000-01-01], ~D[2100-12-30])

    Logger.info("Found #{length(unmatched_transactions)} unmatched transactions")

    case score_and_sort_transactions(sales_invoice, unmatched_transactions) do
      [{transaction, prediction_score} | _] ->
        Logger.info("Prediction score: #{prediction_score}")

        if Matching.RegressionPredictor.confident_match?(prediction_score) do
          # TODO: replace authorize?: false + actor: %{} with system actor once available
          SalesInvoiceTransaction.create_connections(
            [sales_invoice.id],
            [transaction.id],
            organization_id,
            authorize?: false,
            actor: %{}
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
