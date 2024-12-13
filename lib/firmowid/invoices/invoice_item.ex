defmodule Firmowid.Invoices.InvoiceItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "invoice_items" do
    field :name, :string, default: ""
    field :quantity, :decimal, default: 1
    field :unit, :string, default: "szt."
    field :unit_price, :decimal, default: 0
    field :vat_rate, :decimal, default: 0
    field :order, :integer, default: 0

    belongs_to :invoice, Firmowid.Invoices.Invoice
    belongs_to :organization, Firmowid.Accounts.Organization, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def get_net_value(invoice_item) do
    Decimal.mult(invoice_item.unit_price, invoice_item.quantity)
  end

  def get_vat_value(invoice_item) do
    Decimal.mult(get_net_value(invoice_item), Decimal.div(invoice_item.vat_rate, 100))
  end

  def get_gross_value(invoice_item) do
    Decimal.add(get_net_value(invoice_item), get_vat_value(invoice_item))
  end

  def changeset(invoice_item, attrs \\ %{}) do
    invoice_item
    |> cast(attrs, [
      :name,
      :quantity,
      :unit,
      :unit_price,
      :vat_rate,
      :order
    ])
    |> cast_assoc(:invoice)
    |> validate_number(:quantity, greater_than_or_equal_to: 0)
    |> validate_number(:unit_price, greater_than_or_equal_to: 0)
    |> validate_number(:vat_rate, greater_than_or_equal_to: 0)
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
  end
end
