defmodule Firmowid.SalesInvoices do
  @moduledoc false
  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Firmowid.Accounts
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices.Buyer
  alias Firmowid.SalesInvoices.SalesInvoice
  alias Firmowid.SalesInvoices.SalesInvoicesTransactions

  def authorize(:read_sales_invoice, %{role: :admin}, _), do: true
  def authorize(:create_sales_invoice, %{role: :admin}, _), do: true
  def authorize(:create_buyer, %{role: :admin}, _), do: true
  def authorize(:update_buyer, %{role: :admin}, _), do: true

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

  def list_sales_invoices do
    Repo.all(SalesInvoice)
  end

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
    |> Repo.preload(:buyer)
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
    |> Repo.preload(:buyer)
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
    |> Repo.preload(:buyer)
  end

  def get_sales_invoice!(id) do
    SalesInvoice
    |> Repo.get!(id)
    |> Repo.preload(:sales_invoice_items)
    |> Repo.preload(:transactions)
    |> Repo.preload(:buyer)
  end

  def get_sales_invoice_with_logo_url(id) do
    SalesInvoice
    |> Repo.get(id)
    |> Repo.preload(:sales_invoice_items)
    |> Repo.preload(:transactions)
    |> Repo.preload(:buyer)
    |> populate_logo_url()
  end

  def create_sales_invoices_transactions_connection(invoice_id, transaction_id, organization_id) do
    %{
      sales_invoice_id: invoice_id,
      transaction_id: transaction_id,
      organization_id: organization_id
    }
    |> SalesInvoicesTransactions.changeset()
    |> Repo.insert!()
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

    # Get latest invoice from given month
    query =
      SalesInvoice
      |> where([i], fragment("date_part('year', ?)", i.issue_date) == ^year)
      |> where([i], fragment("date_part('month', ?)", i.issue_date) == ^month)
      |> order_by(desc: :invoice_number)
      |> limit(1)

    if_result =
      if omit_invoice_id = Keyword.get(opts, :omit_invoice_id, nil) do
        where(query, [i], i.id != ^omit_invoice_id)
      else
        query
      end

    latest_invoice = Repo.one(if_result)

    case latest_invoice do
      nil ->
        # First invoice of the month
        "01/#{String.pad_leading("#{month}", 2, "0")}/#{year}"

      invoice ->
        # Extract current number and increment
        case Regex.run(~r/^(\d+)\/\d+\/\d+$/, invoice.invoice_number) do
          [_, current_num] ->
            next_num = String.to_integer(current_num) + 1
            # Format with leading zeros to 2 digits
            "#{String.pad_leading("#{next_num}", 2, "0")}/#{String.pad_leading("#{month}", 2, "0")}/#{year}"

          nil ->
            # Fallback if pattern doesn't match
            "01/#{String.pad_leading("#{month}", 2, "0")}/#{year}"
        end
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

  def change_sales_invoice(%SalesInvoice{} = invoice, attrs \\ %{}) do
    SalesInvoice.changeset(invoice, attrs)
  end

  def create_or_update_buyer("", attr) do
    create_buyer(attr)
  end

  def create_or_update_buyer(nil, attr) do
    create_or_update_buyer("", attr)
  end

  def create_or_update_buyer(id, attr) do
    id |> get_buyer!() |> update_buyer(attr)
  end

  def list_buyers do
    Repo.all(Buyer)
  end

  def get_buyer!(id), do: Repo.get!(Buyer, id)

  def get_full_buyer_data_as_single_string(sales_invoice) do
    String.trim(
      "#{sales_invoice.buyer_nip}#{sales_invoice.buyer_pesel} - #{sales_invoice.buyer_display_name} #{sales_invoice.buyer_surname} #{sales_invoice.buyer_name} #{sales_invoice.buyer_address} #{sales_invoice.buyer_country}"
    )
  end

  def create_buyer(attrs \\ %{}) do
    %Buyer{}
    |> Buyer.changeset(attrs)
    |> Repo.insert()
  end

  def update_buyer(%Buyer{} = buyer, attrs) do
    buyer
    |> Buyer.changeset(attrs)
    |> Repo.update()
  end

  def delete_buyer(%Buyer{} = buyer) do
    Repo.delete(buyer)
  end

  def change_buyer(%Buyer{} = buyer, attrs \\ %{}) do
    Buyer.changeset(buyer, attrs)
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
    |> Repo.preload(:buyer)
    |> Repo.preload(:transactions)
  end
end
