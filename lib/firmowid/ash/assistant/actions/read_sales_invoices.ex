defmodule Firmowid.Ash.Assistant.Actions.ReadSalesInvoices do
  @moduledoc """
  Bounded assistant search over sales invoices.
  """

  use Jido.Action,
    name: "list_sales_invoices",
    description:
      "Wyszukuje faktury sprzedażowe z obowiązkowym filtrem zawężającym i limitem bezpieczeństwa dla asystenta.",
    schema: [
      query: [type: :string],
      date_from: [type: :string],
      date_to: [type: :string],
      date_field: [type: :string],
      currency: [type: :string],
      amount_gt: [type: {:or, [:string, :integer, :float]}],
      amount_lt: [type: {:or, [:string, :integer, :float]}],
      reconciliation: [type: :string],
      buyer_type: [type: :string],
      is_cash: [type: :boolean],
      is_reverse_charge: [type: :boolean],
      kind: [type: :string],
      submission: [type: :string],
      limit: [type: :integer, default: 20]
    ],
    output_schema: [
      sales_invoices: [type: {:list, :map}, required: true],
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
             :reconciliation,
             :buyer_type,
             :is_cash,
             :is_reverse_charge,
             :kind,
             :submission
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
           ),
         {:ok, buyer_type} <-
           SearchSupport.parse_enum(
             params[:buyer_type],
             %{"company" => :company, "individual" => :individual},
             "buyer_type"
           ),
         {:ok, kind} <-
           SearchSupport.parse_enum(params[:kind], %{"kor" => :kor, "vat" => :vat}, "kind"),
         {:ok, submission} <-
           SearchSupport.parse_enum(
             params[:submission],
             %{"confirmed" => :confirmed, "draft" => :draft},
             "submission"
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
          buyer_type: buyer_type,
          is_cash: params[:is_cash],
          is_reverse_charge: params[:is_reverse_charge],
          kind: kind,
          submission: submission,
          limit: SearchSupport.normalized_limit(params[:limit], @max_limit)
        })

      serialized_invoices =
        args
        |> Invoicing.list_sales_invoices!(load: [:gross_value], scope: scope)
        |> Enum.map(&InvoiceSerialization.serialize_sales_invoice/1)

      {:ok, %{sales_invoices: serialized_invoices, count: length(serialized_invoices)}}
    end
  end

  def run(_params, _context), do: {:error, "Brakuje kontekstu uprawnień."}
end
