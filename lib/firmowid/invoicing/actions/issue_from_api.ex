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

  It runs as the caller, so the role of the API key's member or company account decides, as for
  `:issue` itself.
  """

  use Ash.Resource.Actions.Implementation

  alias Ecto.Adapters.SQL
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CountryCodes
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

  @result_load [
    :amount,
    :ksef_submission_status,
    sales_invoice_items: [:net_value, :vat_value, :gross_value]
  ]

  @impl true
  def run(input, _opts, context) do
    opts = Ash.Context.to_opts(context)
    external_id = input.arguments.external_id

    with :ok <- lock_issuance(context.tenant),
         {:ok, invoice} <- find_or_issue(external_id, input.arguments, opts) do
      # The caller learns the amount and the KSeF status of a new and of an earlier invoice alike.
      Ash.load(invoice, @result_load, opts)
    end
  end

  defp find_or_issue(external_id, arguments, opts) do
    case Invoicing.get_sales_invoice_by_external_id(
           external_id,
           Keyword.put(opts, :not_found_error?, false)
         ) do
      {:ok, %SalesInvoice{} = invoice} -> {:ok, invoice}
      {:ok, nil} -> issue(arguments, opts)
      {:error, error} -> {:error, error}
    end
  end

  defp lock_issuance(organization_id) do
    lock_key = "sales_invoice_issuance:#{organization_id}"

    with {:ok, _result} <-
           SQL.query(Repo, "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [lock_key]),
         do: :ok
  end

  defp issue(arguments, opts) do
    today = LocalDate.today()

    # An explicit null in the request means the default, like a missing field: the arguments
    # allow nil because JSON:API would otherwise require them in every request.
    numbering_format = arguments.numbering_format || :monthly

    # The invoice type follows the country, so the code is normalized before it decides.
    buyer_country =
      (arguments.buyer_country || "PL")
      |> String.trim()
      |> String.upcase()
      |> CountryCodes.normalize()

    invoice_number =
      opts
      |> Numbering.read_all_invoice_numbers()
      |> Numbering.next_number(numbering_format, today, arguments[:numbering_series])

    invoice_input =
      arguments
      |> Map.take(@buyer_fields ++ @invoice_fields)
      |> Map.merge(%{
        buyer_country: buyer_country,
        invoice_type: if(buyer_country == "PL", do: :poland, else: :foreign),
        invoice_number: invoice_number,
        sale_date: arguments[:sale_date] || today,
        sales_invoice_items:
          arguments.items
          |> Enum.with_index()
          |> Enum.map(fn {item, index} -> Map.put(item, :index, index) end)
      })

    Invoicing.issue_sales_invoice(
      %{input: invoice_input},
      Keyword.put(opts, :private_arguments, %{external_id: arguments.external_id})
    )
  end
end
