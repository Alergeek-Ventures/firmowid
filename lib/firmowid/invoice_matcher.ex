defmodule Firmowid.InvoiceMatcher do
  @moduledoc """
  Business logic for matching invoices and transactions.
  """
  @enforce_keys [:amount, :sale_date]
  defstruct [
    :id,
    :cost_invoices,
    :transactions,
    :amount,
    :amount_numeric,
    :issue_date,
    :sale_date,
    :due_date,
    :file_url,
    :seller,
    :seller_display_name,
    :buyer,
    :skip_invoicing,
    :inserted_at
  ]

  alias Akin
  alias OpenAI

  alias Firmowid.Documents
  alias Firmowid.Finances

  def get_invoice_matchers(organization_id, from, to, filter) do
    cost_invoices = Documents.list_cost_invoices(from, to)

    transactions =
      Finances.list_transactions(organization_id, from, to, only_costs: true)
      # already matched will have a transaction inside a `cost_invoice.transactions`
      # prevent duplication here
      |> Enum.filter(fn t ->
        Enum.all?(cost_invoices, fn d ->
          Enum.all?(d.transactions, fn i -> i.transaction_id != t.transaction_id end)
        end)
      end)

    all =
      cost_invoices
      |> Enum.map(&from_cost_invoice/1)
      |> Enum.concat(Enum.map(transactions, &from_transaction/1))
      |> Enum.sort(&compare_date_then_creditor_then_amount/2)
      |> Enum.filter(fn invoice_matcher ->
        # don't include cost invoices that are issued for previous month and were
        # paid in previous month

        was_paid =
          invoice_matcher.transactions != [] or
            invoice_matcher.skip_invoicing == true

        was_issued_in_date_range =
          Date.compare(from, invoice_matcher.issue_date) in [:lt, :eq] and
            Date.compare(to, invoice_matcher.issue_date) in [:gt, :eq]

        !was_paid or (was_paid and was_issued_in_date_range)
      end)

    case filter do
      :all ->
        all

      :unmatched ->
        Enum.filter(
          all,
          &((&1.cost_invoices == [] or &1.transactions == []) and
              &1.skip_invoicing == false)
        )

      :invoices ->
        Enum.filter(all, &(&1.cost_invoices != []))

      :transactions ->
        Enum.filter(all, &(&1.transactions != []))
    end
  end

  def compare_date_then_creditor_then_amount(a, b) do
    cond do
      Date.compare(a.issue_date, b.issue_date) != :eq ->
        Date.compare(a.issue_date, b.issue_date) == :gt

      a.seller != b.seller ->
        a.seller < b.seller

      a.amount_numeric != b.amount_numeric ->
        Decimal.compare(a.amount_numeric, b.amount_numeric) == :gt

      a.cost_invoices != [] and b.cost_invoices != [] ->
        Enum.at(a.cost_invoices, 0).id < Enum.at(b.cost_invoices, 0).id

      a.transactions != [] and b.transactions != [] ->
        Enum.at(a.transactions, 0).id < Enum.at(b.transactions, 0).id

      true ->
        true
    end
  end

  def from_cost_invoice(cost_invoice) do
    %__MODULE__{
      id: cost_invoice.id,
      cost_invoices: [cost_invoice],
      transactions: cost_invoice.transactions,
      amount: Money.new(cost_invoice.currency, cost_invoice.total_amount),
      amount_numeric: cost_invoice.total_amount,
      issue_date: cost_invoice.issue_date,
      sale_date: cost_invoice.sale_date,
      due_date: cost_invoice.due_date,
      seller: cost_invoice.seller,
      seller_display_name: cost_invoice.seller_display_name,
      file_url: cost_invoice.file_url,
      skip_invoicing: cost_invoice.skip_invoicing,
      inserted_at: cost_invoice.inserted_at
    }
  end

  defp from_transaction(transaction) do
    %__MODULE__{
      id: transaction.id,
      cost_invoices: transaction.cost_invoices_transactions,
      transactions: [transaction],
      amount: Money.new(transaction.transaction_currency, transaction.transaction_amount),
      amount_numeric: transaction.transaction_amount,
      issue_date: transaction.booking_date,
      sale_date: transaction.value_date,
      seller: transaction.creditor_name,
      seller_display_name: transaction.creditor_name,
      skip_invoicing: transaction.skip_invoicing,
      inserted_at: transaction.inserted_at
    }
  end

  def get_potential_transactions_for_cost_invoice(cost_invoice, organization_id, opts \\ []) do
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
      Finances.list_unmatched_transactions(organization_id)

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

  def match_with_transaction_combo(cost_invoice, organization_id) do
    # when there are multiple transactions on the same invoice
    # typically - services / goods that you get across the month

    # highly experimental!

    issue_date = cost_invoice.issue_date |> Date.add(-35)
    payment_deadline = cost_invoice.due_date |> Date.add(7)

    all_found =
      Finances.list_unmatched_transactions(organization_id)
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
      cost_invoices = Documents.list_unmatched_cost_invoices()

      if similarity_threshold == 0 do
        cost_invoices
        |> Enum.map(fn cost_invoice ->
          {cost_invoice,
           get_potential_transactions_for_cost_invoice(
             cost_invoice,
             organization_id,
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

            Documents.create_cost_invoices_transactions_connection(
              Integer.to_string(cost_invoice.id),
              Integer.to_string(match.id),
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
             organization_id,
             similarity_threshold: similarity_threshold,
             max_results: 5
           )}
        end)
        |> Enum.each(fn
          {cost_invoice, [golden_candidate]} ->
            Documents.create_cost_invoices_transactions_connection(
              Integer.to_string(cost_invoice.id),
              Integer.to_string(golden_candidate.id),
              organization_id
            )

          _ ->
            nil
        end)
      end
    end

    cost_invoices = Documents.list_unmatched_cost_invoices(organization_id)

    cost_invoices
    |> Enum.each(fn cost_invoice ->
      combo_matches = match_with_transaction_combo(cost_invoice, organization_id)

      case combo_matches do
        [{_grouped_transaction, transactions}] ->
          Enum.each(transactions, fn transaction ->
            Documents.create_cost_invoices_transactions_connection(
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
    |> Enum.map(fn candidate ->
      content =
        call_llm.(candidate).choices
        |> List.first()
        |> Map.get("message")
        |> Map.get("content")
        |> Jason.decode!()
        |> Map.get("grade")

      {candidate, content}
    end)
  end
end

defimpl Phoenix.HTML.Safe, for: Firmowid.InvoiceMatcher do
  def to_iodata(invoice_matcher) do
    cost_invoice_ids = invoice_matcher.cost_invoices |> Enum.map(& &1.id) |> Enum.join(", ")

    transaction_ids =
      invoice_matcher.transactions |> Enum.map(& &1.id) |> Enum.join(", ")

    "#{cost_invoice_ids}|#{transaction_ids}"
  end
end
