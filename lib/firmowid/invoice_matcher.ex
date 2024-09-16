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

  import Ecto.Query, warn: false
  alias Akin

  alias Firmowid.Finances.ImportedTransaction

  alias Firmowid.Repo
  alias Firmowid.Documents
  alias Firmowid.Finances

  def get_invoice_matchers(from, to) do
    documents = Documents.list_documents_with_metadata(from, to)

    imported_transactions =
      Finances.list_imported_transactions(from, to, only_costs: true)
      |> Enum.filter(fn t ->
        Enum.all?(documents, fn d ->
          Enum.all?(d.imported_transactions, fn i -> i.transaction_id != t.transaction_id end)
        end)
      end)

    documents
    |> Enum.map(&from_document/1)
    |> Enum.concat(Enum.map(imported_transactions, &from_imported_transaction/1))
    |> Enum.sort_by(& &1.sale_date, :desc)
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
      sale_date: transaction.value_date,
      seller: transaction.creditor_name,
      skip_invoicing: transaction.skip_invoicing
    }
  end

  def get_potential_transactions_for_document(document, opts \\ []) do
    opts = Keyword.validate!(opts, siimilarity_threshold: 0.3, max_results: 5)

    similarity_threshold = Keyword.fetch!(opts, :siimilarity_threshold)
    max_results = Keyword.fetch!(opts, :max_results)

    # date range -> between issue_date and payment_deadline
    issue_date = document.issue_date |> Date.add(-1)
    payment_deadline = document.due_date |> Date.add(3)

    {min_amount, max_amount} =
      if document.currency == "PLN" do
        {document.total_amount, document.total_amount}
      else
        # amount - within 10% of total amount
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

    # transactions with exact amount (or in the range for non-PLN) that are between issue_date and payment_deadline
    candidates =
      ImportedTransaction
      |> where([i], i.booking_date >= ^issue_date and i.booking_date <= ^payment_deadline)
      |> where([i], i.transaction_amount >= ^min_amount and i.transaction_amount <= ^max_amount)
      |> Repo.all()

    # use Jaro-Winkler name similarity to check if seller matches
    candidates =
      candidates
      |> Enum.map(fn candidate_transaction ->
        similarity =
          Akin.compare(candidate_transaction.creditor_name, document.seller).jaro_winkler

        {candidate_transaction, similarity}
      end)
      |> Enum.filter(fn {_candidate, similarity} ->
        similarity > similarity_threshold
      end)
      |> Enum.sort_by(fn {_candidate, similarity} -> similarity end, :desc)
      |> Enum.map(fn {candidate, _similarity} -> candidate end)
      |> Enum.take(max_results)

    candidates
  end

  def match_all_good_candidates_for_unconnected_documents() do
    documents = Documents.list_unmatched_documents()

    for similarity_threshold <- [0.8, 0.7, 0.6] do
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
          dbg("Matched #{document.id} with #{golden_candidate.id}")

          Documents.create_documents_imported_transactions_connection(
            document.id,
            golden_candidate.id
          )

        _ ->
          nil
      end)
    end
  end
end
