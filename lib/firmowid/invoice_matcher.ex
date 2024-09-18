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
    :buyer,
    :skip_invoicing
  ]

  alias Akin

  alias Firmowid.Documents
  alias Firmowid.Finances

  def get_invoice_matchers(from, to) do
    documents = Documents.list_documents_with_metadata(from, to)

    imported_transactions =
      Finances.list_imported_transactions(from, to, only_costs: true)
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
    |> Enum.sort(&(Date.compare(&1.issue_date, &2.issue_date) != :lt))
  end

  defp from_document(document) do
    %__MODULE__{
      id: document.id,
      documents: [document],
      imported_transactions: document.imported_transactions,
      amount: Money.from_float!(document.currency, document.total_amount),
      amount_numeric: document.total_amount,
      issue_date: document.issue_date,
      sale_date: document.sale_date,
      due_date: document.due_date,
      seller: document.seller,
      file_url: document.file_url,
      skip_invoicing: document.skip_invoicing
    }
  end

  defp from_imported_transaction(transaction) do
    %__MODULE__{
      id: transaction.id,
      documents: transaction.document_transactions,
      imported_transactions: [transaction],
      amount: Money.from_float!(transaction.transaction_currency, transaction.transaction_amount),
      amount_numeric: transaction.transaction_amount,
      issue_date: transaction.booking_date,
      sale_date: transaction.value_date,
      seller: transaction.creditor_name,
      skip_invoicing: transaction.skip_invoicing
    }
  end

  def get_potential_transactions_for_document(document, opts \\ []) do
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
          {document.total_amount * 1.1, document.total_amount * 0.9}
        end
      else
        # deviation always allowed
        # when doing currency conversion
        {:ok, amount} =
          Money.to_currency(
            Money.from_float!(
              document.currency,
              document.total_amount
            ),
            "PLN",
            Money.ExchangeRates.historic_rates(document.issue_date)
          )

        amount = amount |> Money.to_decimal() |> Decimal.to_float()

        max_amount = amount * 0.9
        min_amount = amount * 1.1

        {min_amount, max_amount}
      end

    unmatched_transactions =
      Finances.list_unmatched_imported_transactions()

    # transactions with exact amount (or in the range for non-PLN) that are between issue_date and payment_deadline
    candidates =
      unmatched_transactions
      |> Enum.filter(fn i ->
        Date.compare(i.booking_date, issue_date) != :lt and
          Date.compare(i.booking_date, payment_deadline) != :gt and
          i.transaction_amount >= min_amount and i.transaction_amount <= max_amount
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

  def match_with_transaction_combo(document) do
    # when there are multiple transactions on the same invoice
    # typically - services / goods that you get across the month

    # highly experimental!

    issue_date = document.issue_date |> Date.add(-35)
    payment_deadline = document.issue_date

    Finances.list_unmatched_imported_transactions()
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
            Enum.sum(Enum.map(transactions, & &1.transaction_amount))
          )
          |> Map.put(:booking_date, Enum.at(transactions, -1).booking_date)

        {grouped_transaction, transactions}
    end)
    |> Enum.filter(fn {grouped_transaction, _transactions} ->
      grouped_transaction.transaction_amount == document.total_amount and
        Akin.compare(grouped_transaction.creditor_name, document.seller).jaro_winkler > 0.5
    end)
  end

  def match_all_good_candidates_for_unconnected_documents() do
    for similarity_threshold <- [0.8, 0.7, 0.6] do
      documents = Documents.list_unmatched_documents()

      documents
      |> Enum.map(fn document ->
        {document,
         get_potential_transactions_for_document(document,
           similarity_threshold: similarity_threshold,
           max_results: 5
         )}
      end)
      |> Enum.each(fn
        {document, [golden_candidate]} ->
          Documents.create_documents_imported_transactions_connection(
            Integer.to_string(document.id),
            Integer.to_string(golden_candidate.id)
          )

        _ ->
          nil
      end)
    end

    documents = Documents.list_unmatched_documents()

    documents
    |> Enum.each(fn document ->
      combo_matches = match_with_transaction_combo(document)

      case combo_matches do
        [{_grouped_transaction, transactions}] ->
          Enum.each(transactions, fn transaction ->
            Documents.create_documents_imported_transactions_connection(
              Integer.to_string(document.id),
              Integer.to_string(transaction.id)
            )
          end)

        _ ->
          nil
      end
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
