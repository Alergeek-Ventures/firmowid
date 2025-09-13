defmodule Firmowid.SalesInvoices do
  @moduledoc false
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Firmowid.Accounts
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.SalesInvoices.SalesInvoicesTransactions

  def authorize(:read_sales_invoice, %{role: :admin}, _), do: true
  def authorize(:create_sales_invoice, %{role: :admin}, _), do: true

  def authorize(action, %{role: :admin, organization_id: org_id}, %{organization_id: org_id})
      when action in [:show, :update, :delete],
      do: true

  def authorize(_, _, _), do: false

  @sales_invoice_broadcast_topic "sales_invoice_broadcast_topic"

  def subscribe_sales_invoice_broadcast(organization_id) do
    Phoenix.PubSub.subscribe(
      Firmowid.PubSub,
      "#{@sales_invoice_broadcast_topic}:#{organization_id}"
    )
  end

  def broadcast_sales_invoice_list_updated(organization_id) do
    Phoenix.PubSub.broadcast(
      Firmowid.PubSub,
      "#{@sales_invoice_broadcast_topic}:#{organization_id}",
      :sales_invoice_list_updated
    )
  end

  def populate_logo_url(%SalesInvoice{} = sales_invoice) do
    loaded_invoice = Repo.preload(sales_invoice, :organization, skip_organization_id: true)
    organization = Accounts.get_organization_with_avatar(loaded_invoice.organization)
    %{loaded_invoice | logo_url: organization.avatar_url}
  end

  def populate_logo_url(nil), do: nil

  def search_sales_invoices(search_term) do
    SalesInvoice
    |> where(
      [i],
      ilike(i.invoice_number, ^"%#{search_term}%") or
        ilike(i.buyer_name, ^"%#{search_term}%") or
        ilike(i.buyer_display_name, ^"%#{search_term}%") or
        ilike(i.buyer_surname, ^"%#{search_term}%") or
        ilike(i.buyer_address, ^"%#{search_term}%") or
        ilike(i.buyer_nip, ^"%#{search_term}%") or
        ilike(i.buyer_pesel, ^"%#{search_term}%")
    )
    |> join(:left, [i], items in assoc(i, :sales_invoice_items))
    |> group_by([i], i.id)
    |> having([i, items], count(items.id) > 0)
    |> limit(15)
    |> order_by(desc: :updated_at)
    |> Repo.all()
    |> Repo.preload(:sales_invoice_items)
  end

  @doc """
  Unmatched invoices - due in a given date range, but
  without a match and not skipped.
  """
  def list_unmatched_sales_invoices do
    list_unmatched_sales_invoices(~D[1970-01-01], ~D[2999-12-31])
  end

  def list_unmatched_sales_invoices(from, to) do
    query =
      from si in SalesInvoice,
        left_join: sit in assoc(si, :transactions),
        where: is_nil(sit.id),
        where: si.due_date >= ^from,
        where: si.due_date <= ^to,
        where: si.skip_invoicing == false,
        order_by: [desc: :issue_date]

    query
    |> Repo.all()
    |> Repo.preload(:sales_invoice_items)
    |> Repo.preload(:transactions)
  end

  def list_sales_invoices(from, to) do
    SalesInvoice
    |> where(
      [d],
      d.issue_date >= ^from and d.issue_date <= ^to
    )
    |> order_by(desc: :issue_date)
    |> Repo.all()
    |> Repo.preload(:sales_invoice_items)
    |> Repo.preload(:transactions)
  end

  def list_invoices_issued_in_date_range(from, to) do
    SalesInvoice
    |> where(
      [d],
      d.issue_date >= ^from and d.issue_date <= ^to
    )
    |> order_by(desc: :issue_date)
    |> Repo.all()
  end

  @spec get_sales_invoice(UUIDv7.t()) :: SalesInvoice.t() | nil
  def get_sales_invoice(id) do
    SalesInvoice
    |> Repo.get(id)
    |> Repo.preload(:sales_invoice_items)
    |> Repo.preload(:transactions)
  end

  def get_sales_invoice!(id) do
    SalesInvoice
    |> Repo.get!(id)
    |> Repo.preload(:sales_invoice_items)
    |> Repo.preload(:transactions)
  end

  def get_sales_invoice_with_logo_url(id) do
    SalesInvoice
    |> Repo.get(id)
    |> Repo.preload(:sales_invoice_items)
    |> Repo.preload(:transactions)
    |> populate_logo_url()
  end

  def create_sales_invoices_transactions_connection(invoice_ids, transaction_ids, organization_id) do
    invoice_ids =
      if is_list(invoice_ids) do
        invoice_ids
      else
        [invoice_ids]
      end

    transaction_ids =
      if is_list(transaction_ids) do
        transaction_ids
      else
        [transaction_ids]
      end

    changesets =
      for invoice_id <- invoice_ids, transaction_id <- transaction_ids do
        SalesInvoicesTransactions.changeset(%{
          sales_invoice_id: invoice_id,
          transaction_id: transaction_id,
          organization_id: organization_id
        })
      end

    changesets
    |> Enum.reduce(Multi.new(), fn %{changes: data} = changeset, acc ->
      Multi.insert(acc, {data.sales_invoice_id, data.transaction_id}, changeset)
    end)
    |> Repo.transaction()
  end

  def delete_sales_invoices_transactions_connections(invoice_id) do
    query = where(from(SalesInvoicesTransactions), [c], c.sales_invoice_id == ^invoice_id)

    Repo.delete_all(query)
  end

  def toggle_skip_invoicing(id) do
    sales_invoice = get_sales_invoice(id)

    sales_invoice =
      sales_invoice
      |> SalesInvoice.changeset(%{skip_invoicing: !sales_invoice.skip_invoicing})
      |> Repo.update!()

    broadcast_sales_invoice_list_updated(sales_invoice.organization_id)

    sales_invoice
  end

  def get_latest_sales_invoice do
    SalesInvoice
    |> order_by(desc: :updated_at)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(:sales_invoice_items)
    |> populate_logo_url()
  end

  def get_next_invoice_number(date, opts \\ []) do
    year = date.year
    month = date.month
    omit_invoice_id = Keyword.get(opts, :omit_invoice_id, nil)

    # Get latest invoice from given month
    query =
      SalesInvoice
      |> where([i], fragment("date_part('year', ?)", i.issue_date) == ^year)
      |> where([i], fragment("date_part('month', ?)", i.issue_date) == ^month)
      |> order_by(desc: :invoice_number)
      |> limit(1)

    query =
      if omit_invoice_id do
        where(query, [i], i.id != ^omit_invoice_id)
      else
        query
      end

    latest_invoice = Repo.one(query)

    # Determine the starting number based on latest invoice in the month
    starting_num =
      case latest_invoice do
        nil ->
          # First invoice of the month
          1

        invoice ->
          # Extract current number and increment
          case Regex.run(~r/^(\d+)\/\d+\/\d+$/, invoice.invoice_number) do
            [_, current_num] ->
              String.to_integer(current_num) + 1

            nil ->
              # Fallback if pattern doesn't match
              1
          end
      end

    # Keep checking until we find a free number
    find_free_invoice_number(starting_num, month, year, omit_invoice_id)
  end

  defp find_free_invoice_number(num, month, year, omit_invoice_id) do
    # Format the invoice number
    invoice_number =
      "#{String.pad_leading("#{num}", 2, "0")}/#{String.pad_leading("#{month}", 2, "0")}/#{year}"

    # Check if this number already exists in the database
    query = where(SalesInvoice, [i], i.invoice_number == ^invoice_number)

    query =
      if omit_invoice_id do
        where(query, [i], i.id != ^omit_invoice_id)
      else
        query
      end

    if Repo.exists?(query) do
      # Number is taken, try the next one
      find_free_invoice_number(num + 1, month, year, omit_invoice_id)
    else
      # Number is free, return it
      invoice_number
    end
  end

  def create_sales_invoice(%SalesInvoice{} = invoice, attrs) do
    invoice
    |> SalesInvoice.changeset(attrs)
    |> Repo.insert()
  end

  def update_sales_invoice(%SalesInvoice{} = invoice, attrs) do
    invoice
    |> SalesInvoice.changeset(attrs)
    |> Repo.update()
  end

  def delete_sales_invoice(%SalesInvoice{} = invoice) do
    Repo.delete(invoice)
  end

  def list_sales_invoices_by_ids(ids, date_from \\ nil, date_to \\ nil) do
    query = where(SalesInvoice, [si], si.id in ^ids)

    query =
      if date_from do
        where(query, [si], si.issue_date >= ^date_from)
      else
        query
      end

    query =
      if date_to do
        where(query, [si], si.issue_date <= ^date_to)
      else
        query
      end

    query
    |> order_by(desc: :issue_date)
    |> Repo.all()
    |> Repo.preload(:sales_invoice_items)
    |> Repo.preload(:transactions)
  end
end
