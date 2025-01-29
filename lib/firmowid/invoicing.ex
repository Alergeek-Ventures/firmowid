defmodule Firmowid.Invoicing do
  alias Akin
  alias OpenAI

  alias Firmowid.CostInvoices
  alias Firmowid.Finances
  alias Firmowid.SalesInvoices

  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Finances.Transaction

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

  def get_potential_transactions_for_cost_invoice(cost_invoice, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        similarity_threshold: 0.1,
        exact_amount: true,
        max_results: 5,
        days_before: 3,
        days_after: 6
      )

    similarity_threshold = Keyword.fetch!(opts, :similarity_threshold)
    max_results = Keyword.fetch!(opts, :max_results)
    exact_amount = Keyword.fetch!(opts, :exact_amount)

    days_before = Keyword.fetch!(opts, :days_before)
    days_after = Keyword.fetch!(opts, :days_after)

    # date range -> between issue_date and payment_deadline
    issue_date = cost_invoice.issue_date |> Date.add(-days_before)
    payment_deadline = cost_invoice.due_date |> Date.add(days_after)

    rates =
      case Money.ExchangeRates.historic_rates(cost_invoice.issue_date) do
        {:ok, rates} ->
          {:ok, rates}

        # fallback to some hardcoded rates if OpenExchange API is not
        # available (like Bartek running dev on it and using our quota)
        _ ->
          {:ok,
           %{
             EUR: Decimal.new("0.9"),
             PLN: Decimal.new("4.2"),
             USD: Decimal.new("1.1")
           }}
      end

    # either an exact match or within ~10% deviation
    {min_amount, max_amount} =
      if cost_invoice.currency == "PLN" do
        # allow deviation even for PLN if option provided
        if exact_amount do
          {cost_invoice.total_amount, cost_invoice.total_amount}
        else
          {Decimal.mult(cost_invoice.total_amount, Decimal.from_float(1.1)),
           Decimal.mult(cost_invoice.total_amount, Decimal.from_float(0.9))}
        end
      else
        # deviation always allowed
        # when doing currency conversion
        {:ok, amount} =
          Money.to_currency(
            Money.new(
              cost_invoice.currency,
              cost_invoice.total_amount
            ),
            "PLN",
            rates
          )

        amount = amount |> Money.to_decimal()

        {Decimal.mult(amount, Decimal.from_float(1.1)),
         Decimal.mult(amount, Decimal.from_float(0.9))}
      end

    unmatched_transactions =
      Finances.list_unmatched_transactions(~D[1970-01-01], ~D[2100-01-01])

    # transactions with exact amount (or in the range for non-PLN)
    # that are between issue_date and payment_deadline
    candidates =
      unmatched_transactions
      |> Enum.filter(fn i ->
        {:ok, transaction_amount_in_pln} =
          Money.to_currency(
            Money.new(
              i.transaction_currency,
              i.transaction_amount
            ),
            "PLN",
            rates
          )

        transaction_amount =
          transaction_amount_in_pln
          |> Money.to_decimal()

        Date.compare(i.booking_date, issue_date) != :lt and
          Date.compare(i.booking_date, payment_deadline) != :gt and
          Decimal.compare(transaction_amount, min_amount) != :lt and
          Decimal.compare(transaction_amount, max_amount) != :gt
      end)

    # use Jaro-Winkler name similarity to check if seller matches
    candidates =
      candidates
      |> Enum.map(fn candidate_transaction ->
        similarity =
          Akin.compare(candidate_transaction.creditor_name, cost_invoice.seller).jaro_winkler

        {candidate_transaction, similarity}
      end)
      |> Enum.filter(fn {_candidate, similarity} ->
        similarity >= similarity_threshold
      end)
      |> Enum.sort_by(fn {_candidate, similarity} -> similarity end, :desc)
      |> Enum.map(fn {candidate, _similarity} -> candidate end)
      |> Enum.take(max_results)

    candidates
  end

  def match_with_transaction_combo(cost_invoice) do
    # when there are multiple transactions on the same invoice
    # typically - services / goods that you get across the month

    # highly experimental!

    issue_date = cost_invoice.issue_date |> Date.add(-35)
    payment_deadline = cost_invoice.due_date |> Date.add(7)

    all_found =
      Finances.list_unmatched_transactions(~D[1970-01-01], ~D[2100-01-01])
      |> Enum.filter(fn i ->
        Date.compare(i.booking_date, issue_date) != :lt and
          Date.compare(i.booking_date, payment_deadline) != :gt
      end)
      |> Enum.group_by(&"#{&1.creditor_name} #{&1.booking_date.year}-#{&1.booking_date.month}")
      |> Enum.filter(fn {_, transactions} -> length(transactions) > 1 end)
      |> Enum.map(fn
        {_label, transactions} ->
          grouped_transaction =
            hd(transactions)
            |> Map.put(
              :transaction_amount,
              Enum.map(
                transactions,
                &Decimal.to_float(&1.transaction_amount)
              )
              |> Enum.sum()
              |> Decimal.from_float()
            )
            |> Map.put(:booking_date, Enum.at(transactions, -1).booking_date)

          {grouped_transaction, transactions}
      end)

    all_found =
      all_found
      |> Enum.filter(fn {grouped_transaction, _transactions} ->
        are_amounts_equal =
          Decimal.compare(
            grouped_transaction.transaction_amount,
            cost_invoice.total_amount
          )

        are_amounts_equal == :eq and
          Akin.compare(grouped_transaction.creditor_name, cost_invoice.seller).jaro_winkler > 0.4
      end)

    all_found
  end

  def match_all_good_candidates_for_unconnected_cost_invoices(organization_id) do
    for similarity_threshold <- [0.9, 0.8, 0] do
      cost_invoices = CostInvoices.list_unmatched_cost_invoices()

      dbg(organization_id)
      dbg(cost_invoices)
      dbg(similarity_threshold)

      if similarity_threshold == 0 do
        cost_invoices
        |> Enum.map(fn cost_invoice ->
          {cost_invoice,
           get_potential_transactions_for_cost_invoice(
             cost_invoice,
             similarity_threshold: similarity_threshold,
             max_results: 5
           )}
        end)
        |> Enum.each(fn {cost_invoice, candidates} ->
          matches =
            llm_re_grade_matches(cost_invoice, candidates)
            |> Enum.filter(fn {_transaction, grade} -> grade >= 0.8 end)
            |> Enum.map(fn {transaction, _grade} -> transaction end)

          if length(matches) == 1 do
            [match] = matches

            CostInvoices.create_cost_invoices_transactions_connection(
              cost_invoice.id,
              match.id,
              organization_id
            )
          end
        end)
      else
        cost_invoices
        |> Enum.map(fn cost_invoice ->
          {cost_invoice,
           get_potential_transactions_for_cost_invoice(
             cost_invoice,
             similarity_threshold: similarity_threshold,
             max_results: 5
           )}
        end)
        |> Enum.each(fn
          {cost_invoice, [golden_candidate]} ->
            CostInvoices.create_cost_invoices_transactions_connection(
              cost_invoice.id,
              golden_candidate.id,
              organization_id
            )

          _ ->
            nil
        end)
      end
    end

    cost_invoices = CostInvoices.list_unmatched_cost_invoices()

    cost_invoices
    |> Enum.each(fn cost_invoice ->
      combo_matches = match_with_transaction_combo(cost_invoice)

      case combo_matches do
        [{_grouped_transaction, transactions}] ->
          Enum.each(transactions, fn transaction ->
            CostInvoices.create_cost_invoices_transactions_connection(
              Integer.to_string(cost_invoice.id),
              Integer.to_string(transaction.id),
              organization_id
            )
          end)

        _ ->
          nil
      end
    end)
  end

  def llm_re_grade_matches(cost_invoice, candidates) do
    call_llm = fn transaction ->
      {:ok, response} =
        OpenAI.chat_completion(
          model: "gpt-4o-mini",
          max_completion_tokens: 20,
          response_format: %{
            type: "json_schema",
            json_schema: %{
              name: "grading_response",
              strict: true,
              schema: %{
                type: "object",
                properties: %{
                  grade: %{
                    type: "number",
                    additionalProperties: false
                  }
                },
                required: ["grade"],
                additionalProperties: false
              }
            }
          },
          messages: [
            %{
              role: "system",
              content:
                "You are a assistant to a finance person. You help matching between cost invoices and transactions, to complete the paper trail."
            },
            %{
              role: "user",
              content: "
              This is the metadata of a cost invoice I want to match:
              {
                invoice_identifier: #{cost_invoice.invoice_identifier},
                description: #{cost_invoice.description},
                issue_date: #{cost_invoice.issue_date},
                total_amount: #{cost_invoice.total_amount},
                currency: #{cost_invoice.currency},
                seller: #{cost_invoice.seller},
              }

              Here is a transaction that I selected as possible match:
              {
                booking_date: #{transaction.booking_date},
                value_date: #{transaction.value_date},
                transaction_currency: #{transaction.transaction_currency},
                transaction_amount: #{transaction.transaction_amount},
                creditor_name: #{transaction.creditor_name},
                remittance_information_unstructured: #{transaction.remittance_information_unstructured},
              }

              Considering  metadata of them and the metadata of the cost invoice,
              please give me a score between 0 and 1. Take into consideration
              whether the name of seller matches with creditor name, dates and
              if the amount matches. Also look at the description of the cost invoice.
              Reply only with the score.
              " |> String.trim()
            }
          ]
        )

      response
    end

    candidates
    # run calls for each candidate in parallel
    |> Enum.map(
      &Task.async(fn ->
        candidate = &1

        content =
          call_llm.(candidate).choices
          |> List.first()
          |> Map.get("message")
          |> Map.get("content")
          |> Jason.decode!()
          |> Map.get("grade")

        {candidate, content}
      end)
    )
    |> Enum.map(&Task.await/1)
  end
end
