defmodule Firmowid.SalesInvoices do
  import Ecto.Query, warn: false
  alias Firmowid.Repo

  alias Firmowid.SalesInvoices.SalesInvoice

  def list_sales_invoices do
    Repo.all(SalesInvoice)
  end

  def get_sales_invoice(id) do
    Repo.get(SalesInvoice, id)
    |> Repo.preload(:sales_invoice_items)
  end

  def get_latest_sales_invoice() do
    SalesInvoice
    |> order_by(desc: :updated_at)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(:sales_invoice_items)
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
