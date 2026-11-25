defmodule Firmowid.Invoicing.Actions.IssueFromApi do
  @moduledoc """
  Issues an invoice for another system's order through the `:issue` action, or returns the
  invoice the order already has.

  API issuances of one organization run one at a time: each holds a lock on the organization
  for its transaction, so two requests for the same order cannot both find no invoice, and two
  orders cannot take the same next number. An invoice issued in the app at the same moment
  does not take the lock; if it takes the number first, the request fails on the duplicate
  number and its retry gets the next one. The invoice is numbered in the requested sequence
  and dated today, like every issued invoice.

  An API key may run this action, but not `:issue` and the actions it runs: once this action is
  authorized, the invoice is issued as the key's admin, under that person's policies.
  """

  use Ash.Resource.Actions.Implementation

  alias Ecto.Adapters.SQL
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.SalesInvoice.Numbering
  alias Firmowid.LocalDate
  alias Firmowid.Repo

  @buyer_fields [
    :buyer_type,
    :buyer_id,
    :buyer_full_name,
    :buyer_given_name,
    :buyer_surname,
    :buyer_address,
    :buyer_country,
    :buyer_email,
    :buyer_phone
  ]

  @invoice_fields [
    :sale_date,
    :paid_on,
    :due_date,
    :payment_method,
    :currency,
    :seller_account_number,
    :invoice_note,
    :should_send_emails
  ]

  @impl true
  def run(input, _opts, context) do
    opts = Ash.Context.to_opts(context)
    external_id = input.arguments.external_id

    with :ok <- lock_issuance(context.tenant) do
      case Invoicing.get_sales_invoice_by_external_id(
             external_id,
             Keyword.put(opts, :not_found_error?, false)
           ) do
        {:ok, %SalesInvoice{} = invoice} -> {:ok, invoice}
        {:ok, nil} -> issue(input.arguments, opts)
        {:error, error} -> {:error, error}
      end
    end
  end

  # `:issue` runs actions, such as queueing the KSeF submission, that a key may not call itself.
  defp without_api_key(%{__metadata__: metadata} = actor),
    do: %{actor | __metadata__: Map.drop(metadata, [:using_api_key?, :api_key])}

  defp without_api_key(actor), do: actor

  defp lock_issuance(organization_id) do
    lock_key = "sales_invoice_issuance:#{organization_id}"

    with {:ok, _result} <-
           SQL.query(Repo, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [lock_key]),
         do: :ok
  end

  defp issue(arguments, opts) do
    today = LocalDate.today()

    invoice_number =
      opts
      |> Numbering.read_all_invoice_numbers()
      |> Numbering.next_number(arguments.numbering_format, today, arguments[:numbering_series])

    invoice_input =
      arguments
      |> Map.take(@buyer_fields ++ @invoice_fields)
      |> Map.merge(%{
        invoice_type: if(arguments.buyer_country == "PL", do: :poland, else: :foreign),
        invoice_number: invoice_number,
        sale_date: arguments[:sale_date] || today,
        sales_invoice_items:
          arguments.items
          |> Enum.with_index()
          |> Enum.map(fn {item, index} -> Map.put(item, :index, index) end)
      })

    Invoicing.issue_sales_invoice(
      %{input: invoice_input},
      Keyword.merge(opts,
        actor: without_api_key(opts[:actor]),
        private_arguments: %{external_id: arguments.external_id}
      )
    )
  end
end
