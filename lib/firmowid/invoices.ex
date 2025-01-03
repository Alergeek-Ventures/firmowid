defmodule Firmowid.Invoices do
  import Ecto.Query, warn: false
  alias Firmowid.Repo

  alias Firmowid.Invoices.Invoice

  def list_invoices do
    Repo.all(Invoice)
  end

  def get_invoice(id) do
    Repo.get(Invoice, id)
    |> Repo.preload(:invoice_items)
  end

  def get_latest_invoice() do
    Invoice
    |> order_by(desc: :updated_at)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(:invoice_items)
  end

  def create_invoice(%Invoice{} = invoice, attrs) do
    invoice
    |> Invoice.changeset(attrs)
    |> Repo.insert()
  end

  def update_invoice(%Invoice{} = invoice, attrs) do
    invoice
    |> Invoice.changeset(attrs)
    |> Repo.update()
  end

  def delete_invoice(%Invoice{} = invoice) do
    Repo.delete(invoice)
  end

  def change_invoice(%Invoice{} = invoice, attrs \\ %{}) do
    Invoice.changeset(invoice, attrs)
  end

  alias Firmowid.Invoices.Buyer

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

  alias Firmowid.Invoices.Seller

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
