defmodule Firmowid.SalesInvoices.SalesInvoiceItem do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  schema "sales_invoice_items" do
    field :name, :string, default: ""
    # max 6 decimal places
    field :quantity, :decimal, default: 1
    field :unit, :string, default: "szt."
    field :unit_price, :decimal, default: 0
    field :vat_rate, :decimal, default: 0

    belongs_to :sales_invoice, Firmowid.SalesInvoices.SalesInvoice
    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  def get_net_value(sales_invoice_item) do
    Decimal.mult(sales_invoice_item.unit_price, sales_invoice_item.quantity)
  end

  def get_vat_value(sales_invoice_item) do
    Decimal.mult(get_net_value(sales_invoice_item), Decimal.div(sales_invoice_item.vat_rate, 100))
  end

  def get_gross_value(sales_invoice_item) do
    Decimal.add(get_net_value(sales_invoice_item), get_vat_value(sales_invoice_item))
  end

  def changeset(sales_invoice_item, attrs \\ %{}) do
    sales_invoice_item
    |> cast(attrs, [
      :name,
      :quantity,
      :unit,
      :unit_price,
      :vat_rate
    ])
    |> cast_assoc(:sales_invoice)
    # Note: quantity is not validated >= 0 because correction invoices (KOR)
    # require negative quantities to represent reversed items
    |> validate_number(:unit_price, greater_than_or_equal_to: 0)
    # VAT rate shouldnt be more like enum?
    |> validate_number(:vat_rate, greater_than_or_equal_to: 0)
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
  end
end
