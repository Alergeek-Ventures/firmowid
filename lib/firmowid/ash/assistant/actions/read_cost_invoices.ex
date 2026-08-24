defmodule Firmowid.Ash.Assistant.Actions.ReadCostInvoices do
  @moduledoc """
  Bounded assistant search over cost invoices.
  """

  use Jido.Action,
    name: "list_cost_invoices",
    description: "Wyszukuje faktury kosztowe z obowiązkowym filtrem zawężającym i limitem bezpieczeństwa dla asystenta.",
    schema: [
      query: [type: :string],
      date_from: [type: :string],
      date_to: [type: :string],
      date_field: [type: :string],
      currency: [type: :string],
      amount_gt: [type: {:or, [:string, :integer, :float]}],
      amount_lt: [type: {:or, [:string, :integer, :float]}],
      reconciliation: [type: :string],
      limit: [type: :integer, default: 20]
    ],
    output_schema: [
      cost_invoices: [type: {:list, :map}, required: true],
      count: [type: :non_neg_integer, required: true]
    ]

  alias Firmowid.Ash.Assistant.Actions.InvoiceSerialization
  alias Firmowid.Ash.Assistant.Actions.SearchSupport
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Scope

  @max_limit 25

  @impl true
  def run(params, %{scope: %Scope{} = scope}) do
    with :ok <-
           SearchSupport.require_narrowing_filter(params, [
             :query,
             :date_from,
             :date_to,
             :currency,
             :amount_gt,
             :amount_lt,
             :reconciliation
           ]),
         {:ok, date_from} <- SearchSupport.parse_date(params[:date_from]),
         {:ok, date_to} <- SearchSupport.parse_date(params[:date_to]),
         {:ok, amount_gt} <- SearchSupport.parse_decimal(params[:amount_gt]),
         {:ok, amount_lt} <- SearchSupport.parse_decimal(params[:amount_lt]),
         {:ok, date_field} <-
           SearchSupport.parse_enum(
             params[:date_field],
             %{
               "any" => :any,
               "due_date" => :due_date,
               "issue_date" => :issue_date,
               "sale_date" => :sale_date
             },
             "date_field"
           ),
         {:ok, reconciliation} <-
           SearchSupport.parse_enum(
             params[:reconciliation],
             %{"matched" => :matched, "pending" => :pending, "skipped" => :skipped},
             "reconciliation"
           ) do
      args =
        SearchSupport.compact_args(%{
          query: params[:query],
          date_from: date_from,
          date_to: date_to,
          date_field: date_field,
          currency: params[:currency],
          amount_gt: amount_gt,
          amount_lt: amount_lt,
          reconciliation: reconciliation,
          limit: SearchSupport.normalized_limit(params[:limit], @max_limit)
        })

      serialized_invoices =
        args
        |> Invoicing.list_cost_invoices!(load: [:effective_amount], scope: scope)
        |> Enum.map(&InvoiceSerialization.serialize_cost_invoice/1)

      {:ok, %{cost_invoices: serialized_invoices, count: length(serialized_invoices)}}
    end
  end

  def run(_params, _context), do: {:error, "Brakuje kontekstu uprawnień."}
end
