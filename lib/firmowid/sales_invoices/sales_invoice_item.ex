defmodule Firmowid.SalesInvoices.SalesInvoiceItem do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  alias Firmowid.Ksef.VatRate

  schema "sales_invoice_items" do
    field :index, :integer
    field :name, :string, default: ""
    # max 6 decimal places
    field :quantity, :decimal
    field :unit, :string, default: "szt."
    field :unit_price, :decimal
    # KSeF TStawkaPodatku code: "23", "8", "5", "zw", "oo", "np I", "np II", etc.
    field :vat_rate, :string

    field :net_value, :decimal, virtual: true
    field :gross_value, :decimal, virtual: true

    belongs_to :sales_invoice, Firmowid.SalesInvoices.SalesInvoice
    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  def get_net_value(sales_invoice_item) do
    if sales_invoice_item.unit_price && sales_invoice_item.quantity do
      Decimal.mult(sales_invoice_item.unit_price, sales_invoice_item.quantity)
    else
      Decimal.new(0)
    end
  end

  def get_vat_value(sales_invoice_item) do
    if sales_invoice_item.unit_price && sales_invoice_item.quantity do
      numeric_rate = VatRate.to_numeric(sales_invoice_item.vat_rate)
      Decimal.mult(get_net_value(sales_invoice_item), Decimal.div(numeric_rate, 100))
    else
      Decimal.new(0)
    end
  end

  def get_gross_value(sales_invoice_item) do
    Decimal.add(get_net_value(sales_invoice_item), get_vat_value(sales_invoice_item))
  end

  def changeset(sales_invoice_item, attrs \\ %{}, index \\ nil) do
    sales_invoice_item
    |> cast(attrs, [
      :name,
      :quantity,
      :unit,
      :unit_price,
      :vat_rate
    ])
    |> cast_assoc(:sales_invoice)
    |> validate_required([:name, :quantity, :unit, :unit_price, :vat_rate])
    |> validate_inclusion(:vat_rate, VatRate.valid_rates())
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
    |> put_change(:index, index)
    |> then(fn changeset ->
      if changeset.valid? do
        item = apply_changes(changeset)

        changeset
        |> put_change(:net_value, get_net_value(item))
        |> put_change(:gross_value, get_gross_value(item))
      else
        changeset
        |> put_change(:net_value, Decimal.new(0))
        |> put_change(:gross_value, Decimal.new(0))
      end
    end)
  end
end
