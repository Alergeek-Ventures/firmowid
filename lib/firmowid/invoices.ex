defmodule Firmowid.Invoices do
  alias Firmowid.Repo

  alias Firmowid.Invoices.Invoice

  def list_invoices do
    Repo.all(Invoice)
  end

  def get_invoice(organization_id, id) do
    Repo.get(Invoice, id, organization_id: organization_id)
    |> Repo.preload(:invoice_items, organization_id: organization_id)
  end

  def create_invoice(%Invoice{} = invoice, attrs) do
    invoice
    |> Invoice.changeset(attrs)
    |> Repo.insert()
  end

  def update_invoice(organization_id, %Invoice{} = invoice, attrs) do
    invoice
    |> Invoice.changeset(attrs)
    |> Repo.update(organization_id: organization_id)
  end

  def delete_invoice(organization_id, %Invoice{} = invoice) do
    Repo.delete(invoice, organization_id: organization_id)
  end

  def change_invoice(%Invoice{} = invoice, attrs \\ %{}) do
    Invoice.changeset(invoice, attrs)
  end
end
