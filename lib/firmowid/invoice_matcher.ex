defmodule Firmowid.InvoiceMatcher do
  @moduledoc """
  Business logic for matching invoices and transactions.
  """
  @enforce_keys [:amount, :sale_date]
  defstruct [
    :id,
    :documents,
    :imported_transactions,
    :amount,
    :amount_numeric,
    :issue_date,
    :sale_date,
    :due_date,
    :file_url,
    :seller,
    :seller_display_name,
    :buyer,
    :skip_invoicing
  ]

  alias Akin
  alias OpenAI

  alias Firmowid.Documents
  alias Firmowid.Finances

  def get_invoice_matchers(organization_id, from, to) do
    documents = Documents.list_documents_with_metadata(organization_id, from, to)

    imported_transactions =
      Finances.list_imported_transactions(organization_id, from, to, only_costs: true)
      # already matched will have a transaction inside a `document.imported_transactions`
      # prevent duplication here
      |> Enum.filter(fn t ->
        Enum.all?(documents, fn d ->
          Enum.all?(d.imported_transactions, fn i -> i.transaction_id != t.transaction_id end)
        end)
      end)

    documents
    |> Enum.map(&from_document/1)
    |> Enum.concat(Enum.map(imported_transactions, &from_imported_transaction/1))
    |> Enum.sort(&compare_date_then_creditor_then_amount/2)
    |> Enum.filter(fn invoice_matcher ->
      # don't include documents that are issued for previous month and were
      # paid in previous month

      was_paid =
        invoice_matcher.imported_transactions != [] or
          invoice_matcher.skip_invoicing == true

      was_issued_in_date_range =
        Date.compare(from, invoice_matcher.issue_date) in [:lt, :eq] and
          Date.compare(to, invoice_matcher.issue_date) in [:gt, :eq]

      IO.inspect(%{
        seller_display_name: invoice_matcher.seller_display_name,
        was_paid: was_paid,
        from: from,
        to: to,
        issue_date: invoice_matcher.issue_date,
        from_compare: Date.compare(from, invoice_matcher.issue_date),
        to_compare: Date.compare(to, invoice_matcher.issue_date)
      })

      !was_paid or (was_paid and was_issued_in_date_range)
    end)
  end

  def compare_date_then_creditor_then_amount(a, b) do
    cond do
      Date.compare(a.issue_date, b.issue_date) != :eq ->
        Date.compare(a.issue_date, b.issue_date) == :gt

      a.seller != b.seller ->
        a.seller < b.seller

      a.amount_numeric != b.amount_numeric ->
        Decimal.compare(a.amount_numeric, b.amount_numeric) == :gt

      a.documents != [] and b.documents != [] ->
        Enum.at(a.documents, 0).id < Enum.at(b.documents, 0).id

      a.imported_transactions != [] and b.imported_transactions != [] ->
        Enum.at(a.imported_transactions, 0).id < Enum.at(b.imported_transactions, 0).id

      true ->
        true
    end
  end

  def from_document(document) do
    %__MODULE__{
      id: document.id,
      documents: [document],
      imported_transactions: document.imported_transactions,
      amount: Money.new(document.currency, document.total_amount),
      amount_numeric: document.total_amount,
      issue_date: document.issue_date,
      sale_date: document.sale_date,
      due_date: document.due_date,
      seller: document.seller,
      seller_display_name: document.seller_display_name,
      file_url: document.file_url,
      skip_invoicing: document.skip_invoicing
    }
  end

  defp from_imported_transaction(transaction) do
    %__MODULE__{
      id: transaction.id,
      documents: transaction.document_transactions,
      imported_transactions: [transaction],
      amount: Money.new(transaction.transaction_currency, transaction.transaction_amount),
      amount_numeric: transaction.transaction_amount,
      issue_date: transaction.booking_date,
      sale_date: transaction.value_date,
      seller: transaction.creditor_name,
      seller_display_name: transaction.creditor_name,
      skip_invoicing: transaction.skip_invoicing
    }
  end

  def get_potential_transactions_for_document(document, organization_id, opts \\ []) do
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
    issue_date = document.issue_date |> Date.add(-days_before)
    payment_deadline = document.due_date |> Date.add(days_after)

    # either an exact match or within ~10% deviation
    {min_amount, max_amount} =
      if document.currency == "PLN" do
        # allow deviation even for PLN if option provided
        if exact_amount do
          {document.total_amount, document.total_amount}
        else
          {Decimal.mult(document.total_amount, Decimal.from_float(1.1)),
           Decimal.mult(document.total_amount, Decimal.from_float(0.9))}
        end
      else
        # deviation always allowed
        # when doing currency conversion
        {:ok, amount} =
          Money.to_currency(
            Money.new(
              document.currency,
              document.total_amount
            ),
            "PLN",
            Money.ExchangeRates.historic_rates(document.issue_date)
          )

        amount = amount |> Money.to_decimal()

        {Decimal.mult(amount, Decimal.from_float(1.1)),
         Decimal.mult(amount, Decimal.from_float(0.9))}
      end

    unmatched_transactions =
      Finances.list_unmatched_imported_transactions(organization_id)

    # transactions with exact amount (or in the range for non-PLN) that are between issue_date and payment_deadline
    candidates =
      unmatched_transactions
      |> Enum.filter(fn i ->
        Date.compare(i.booking_date, issue_date) != :lt and
          Date.compare(i.booking_date, payment_deadline) != :gt and
          Decimal.compare(i.transaction_amount, min_amount) != :lt and
          Decimal.compare(i.transaction_amount, max_amount) != :gt

        # i.transaction_amount >= min_amount and i.transaction_amount <= max_amount
      end)

    # use Jaro-Winkler name similarity to check if seller matches
    candidates =
      candidates
      |> Enum.map(fn candidate_transaction ->
        similarity =
          Akin.compare(candidate_transaction.creditor_name, document.seller).jaro_winkler

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

  def match_with_transaction_combo(document, organization_id) do
    # when there are multiple transactions on the same invoice
    # typically - services / goods that you get across the month

    # highly experimental!

    issue_date = document.issue_date |> Date.add(-35)
    payment_deadline = document.due_date |> Date.add(7)

    all_found =
      Finances.list_unmatched_imported_transactions(organization_id)
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
            document.total_amount
          )

        are_amounts_equal == :eq and
          Akin.compare(grouped_transaction.creditor_name, document.seller).jaro_winkler > 0.4
      end)

    all_found
  end

  def match_all_good_candidates_for_unconnected_documents(organization_id) do
    for similarity_threshold <- [0.9, 0.8, 0] do
      documents = Documents.list_unmatched_documents(organization_id)

      if similarity_threshold == 0 do
        documents
        |> Enum.map(fn document ->
          {document,
           get_potential_transactions_for_document(
             document,
             organization_id,
             similarity_threshold: similarity_threshold,
             max_results: 5
           )}
        end)
        |> Enum.each(fn {document, candidates} ->
          matches =
            llm_re_grade_matches(document, candidates)
            |> Enum.filter(fn {_transaction, grade} -> grade >= 0.8 end)
            |> Enum.map(fn {transaction, _grade} -> transaction end)

          if length(matches) == 1 do
            [match] = matches

            Documents.create_documents_imported_transactions_connection(
              Integer.to_string(document.id),
              Integer.to_string(match.id),
              organization_id
            )
          end
        end)
      else
        documents
        |> Enum.map(fn document ->
          {document,
           get_potential_transactions_for_document(
             document,
             organization_id,
             similarity_threshold: similarity_threshold,
             max_results: 5
           )}
        end)
        |> Enum.each(fn
          {document, [golden_candidate]} ->
            Documents.create_documents_imported_transactions_connection(
              Integer.to_string(document.id),
              Integer.to_string(golden_candidate.id),
              organization_id
            )

          _ ->
            nil
        end)
      end
    end

    documents = Documents.list_unmatched_documents(organization_id)

    documents
    |> Enum.each(fn document ->
      combo_matches = match_with_transaction_combo(document, organization_id)

      case combo_matches do
        [{_grouped_transaction, transactions}] ->
          Enum.each(transactions, fn transaction ->
            Documents.create_documents_imported_transactions_connection(
              Integer.to_string(document.id),
              Integer.to_string(transaction.id),
              organization_id
            )
          end)

        _ ->
          nil
      end
    end)
  end

  def llm_re_grade_matches(document, candidates) do
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
                "You are a assistant to a finance person. You help matching between documents and transactions, to complete the paper trail."
            },
            %{
              role: "user",
              content: "
              This is the metadata of a document I want to match:
              {
                invoice_identifier: #{document.invoice_identifier},
                description: #{document.description},
                issue_date: #{document.issue_date},
                total_amount: #{document.total_amount},
                currency: #{document.currency},
                seller: #{document.seller},
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

              Considering  metadata of them and the metadata of the document,
              please give me a score between 0 and 1. Take into consideration
              whether the name of seller matches with creditor name, dates and
              if the amount matches. Also look at the description of the document.
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
    document_ids = invoice_matcher.documents |> Enum.map(& &1.id) |> Enum.join(", ")

    imported_transaction_ids =
      invoice_matcher.imported_transactions |> Enum.map(& &1.id) |> Enum.join(", ")

    "#{document_ids} | #{imported_transaction_ids}"
  end
end
