defmodule Firmowid.Ash.Assistant.Actions.ReadTransactions do
  @moduledoc """
  Bounded assistant search over bank transactions.
  """

  use Jido.Action,
    name: "list_transactions",
    description: "Wyszukuje transakcje z obowiązkowym filtrem zawężającym i limitem bezpieczeństwa dla asystenta.",
    schema: [
      query: [type: :string],
      date_from: [type: :string],
      date_to: [type: :string],
      reconciliation: [type: :string],
      currency: [type: :string],
      amount_gt: [type: {:or, [:string, :integer, :float]}],
      amount_lt: [type: {:or, [:string, :integer, :float]}],
      limit: [type: :integer, default: 20]
    ],
    output_schema: [
      transactions: [type: {:list, :map}, required: true],
      count: [type: :non_neg_integer, required: true]
    ]

  import Ash.Expr

  alias Firmowid.Ash.Assistant.Actions.SearchSupport
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Scope

  require Ash.Query

  @max_limit 25

  @impl true
  def run(params, %{scope: %Scope{} = scope}) do
    with :ok <-
           SearchSupport.require_narrowing_filter(params, [
             :query,
             :date_from,
             :date_to,
             :reconciliation,
             :currency,
             :amount_gt,
             :amount_lt
           ]),
         {:ok, date_from} <- SearchSupport.parse_date(params[:date_from]),
         {:ok, date_to} <- SearchSupport.parse_date(params[:date_to]),
         {:ok, amount_gt} <- SearchSupport.parse_decimal(params[:amount_gt]),
         {:ok, amount_lt} <- SearchSupport.parse_decimal(params[:amount_lt]),
         {:ok, reconciliation} <-
           SearchSupport.parse_enum(
             params[:reconciliation],
             %{"matched" => :matched, "pending" => :pending, "skipped" => :skipped},
             "reconciliation"
           ),
         :ok <- require_currency_for_amount_filters(params[:currency], amount_gt, amount_lt) do
      args =
        SearchSupport.compact_args(%{
          query: params[:query],
          date_from: date_from,
          date_to: date_to,
          reconciliation: reconciliation,
          currency: params[:currency]
        })

      transactions =
        Transaction
        |> Ash.Query.for_read(:read, args, scope: scope)
        |> maybe_filter_amount(:amount_gt, amount_gt)
        |> maybe_filter_amount(:amount_lt, amount_lt)
        |> Ash.Query.limit(SearchSupport.normalized_limit(params[:limit], @max_limit))
        |> Ash.Query.load([:amount])
        |> Ash.read!(scope: scope)

      serialized_transactions = Enum.map(transactions, &serialize_transaction/1)
      {:ok, %{transactions: serialized_transactions, count: length(serialized_transactions)}}
    end
  end

  def run(_params, _context), do: {:error, "Brakuje kontekstu uprawnień."}

  defp maybe_filter_amount(query, _field, nil), do: query

  defp maybe_filter_amount(query, :amount_gt, value), do: Ash.Query.filter(query, expr(amount[:amount] >= ^value))

  defp maybe_filter_amount(query, :amount_lt, value), do: Ash.Query.filter(query, expr(amount[:amount] <= ^value))

  defp require_currency_for_amount_filters(_currency, nil, nil), do: :ok

  defp require_currency_for_amount_filters(currency, _amount_gt, _amount_lt) when currency in [nil, ""] do
    {:error, "Filtry kwotowe wymagają podania parametru currency."}
  end

  defp require_currency_for_amount_filters(_currency, _amount_gt, _amount_lt), do: :ok

  defp serialize_transaction(transaction) do
    %{
      id: transaction.id,
      creditor_name: transaction.creditor_name,
      debtor_name: transaction.debtor_name,
      booking_date: transaction.booking_date,
      value_date: transaction.value_date,
      currency: transaction.amount |> Money.to_currency_code() |> Atom.to_string(),
      amount: to_string(transaction.amount),
      remittance_information_unstructured: transaction.remittance_information_unstructured,
      skip_invoicing: transaction.skip_invoicing
    }
  end
end
