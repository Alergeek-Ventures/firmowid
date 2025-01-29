defmodule Firmowid.SalesInvoices do
  import Ecto.Query, warn: false
  alias Firmowid.Accounts
  alias Firmowid.Repo

  alias Firmowid.SalesInvoices.SalesInvoice

  def populate_logo_url(%SalesInvoice{} = sales_invoice) do
    with loaded_invoice <- Repo.preload(sales_invoice, :organization, skip_organization_id: true),
         organization <- Accounts.get_organization_with_avatar(loaded_invoice.organization) do
      Map.put(loaded_invoice, :logo_url, organization.avatar_url)
    end
  end

  def populate_logo_url(nil), do: nil

  def list_sales_invoices do
    Repo.all(SalesInvoice)
  end

  def list_unmatched_sales_invoices(from, to) do
    query =
      from si in SalesInvoice,
        left_join: sit in assoc(si, :transactions),
        where: is_nil(sit.id),
        where: si.issue_date >= ^from,
        where: si.due_date <= ^to,
        order_by: [desc: :issue_date]

    query
    |> Repo.all()
    |> Repo.preload(:sales_invoice_items)
    |> Repo.preload(:buyer)
  end

  def list_sales_invoices(from, to) do
    SalesInvoice
    |> where(
      [d],
      (d.issue_date >= ^from and d.issue_date <= ^to) or
        (d.due_date >= ^from and d.due_date <= ^to) or
        (d.sale_date >= ^from and d.sale_date <= ^to)
    )
    |> order_by(desc: :issue_date)
    |> Repo.all()
    |> Repo.preload(:sales_invoice_items)
    |> Repo.preload(:buyer)
    |> Repo.preload(:transactions)
  end

  def get_sales_invoice(id) do
    Repo.get(SalesInvoice, id)
    |> Repo.preload(:sales_invoice_items)
    |> populate_logo_url()
  end

  def get_latest_sales_invoice() do
    SalesInvoice
    |> order_by(desc: :updated_at)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(:sales_invoice_items)
    |> populate_logo_url()
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

  alias Firmowid.SalesInvoices.Buyer

  def create_or_update_buyer("", attr) do
    create_buyer(attr)
  end

  def create_or_update_buyer(nil, attr) do
    create_or_update_buyer("", attr)
  end

  def create_or_update_buyer(id, attr) do
    get_buyer!(id) |> update_buyer(attr)
  end

  def list_buyers() do
    Repo.all(Buyer)
  end

  def get_buyer!(id), do: Repo.get!(Buyer, id)

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

  alias Firmowid.SalesInvoices.Seller

  def create_or_update_seller("", attr) do
    create_seller(attr)
  end

  def create_or_update_seller(nil, attr) do
    create_or_update_seller("", attr)
  end

  def create_or_update_seller(id, attr) do
    get_seller!(id) |> update_seller(attr)
  end

  def list_sellers() do
    Repo.all(Seller)
  end

  def get_seller!(id),
    do: Repo.get!(Seller, id)

  def create_seller(attrs \\ %{}) do
    %Seller{}
    |> Seller.changeset(attrs)
    |> Repo.insert()
  end

  def update_seller(%Seller{} = seller, attrs) do
    seller
    |> Seller.changeset(attrs)
    |> Repo.update()
  end

  def delete_seller(%Seller{} = seller) do
    Repo.delete(seller)
  end

  def change_seller(%Seller{} = seller, attrs \\ %{}) do
    Seller.changeset(seller, attrs)
  end
end
