defmodule Firmowid.SalesInvoices.SalesInvoice do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "sales_invoices" do
    field :invoice_type, Ecto.Enum, values: [:poland, :foreign], default: :poland

    field :invoice_number, :string
    field :sale_date, :date
    field :issue_date, :date
    field :due_date, :date
    field :payment_method, :string
    field :currency, :string
    field :is_basic_info_confirmed, :boolean, default: false

    field :seller_nip, :string
    field :seller_display_name, :string
    field :seller_address, :string
    field :seller_name, :string
    field :seller_surname, :string
    field :seller_account_number, :string
    field :is_seller_confirmed, :boolean, default: false

    field :buyer_type, Ecto.Enum, values: [:individual, :company], default: :company

    field :buyer_nip, :string
    field :buyer_display_name, :string
    field :buyer_name, :string
    field :buyer_surname, :string
    field :buyer_pesel, :string

    field :buyer_address, :string
    field :buyer_country, :string

    field :buyer_is_different_mail_address, :boolean, default: false
    field :buyer_mail_address, :string
    field :buyer_mail_country, :string

    field :buyer_email, :string
    field :buyer_phone, :string
    field :buyer_description, :string
    field :is_buyer_confirmed, :boolean, default: false

    field :are_sales_invoice_items_confirmed, :boolean, default: false

    field :is_cash_account, :boolean, default: false
    field :is_reverse_charge, :boolean, default: false

    field :skip_invoicing, :boolean, default: false

    has_many :sales_invoice_items, Firmowid.SalesInvoices.SalesInvoiceItem, on_replace: :delete

    many_to_many :transactions,
                 Firmowid.Finances.Transaction,
                 join_through: "sales_invoices_transactions"

    belongs_to :organization, Firmowid.Accounts.Organization
    belongs_to :buyer, Firmowid.SalesInvoices.Buyer

    timestamps()
  end

  def get_net_value(sales_invoice) do
    Enum.reduce(sales_invoice.sales_invoice_items, Decimal.new(0), fn item, acc ->
      Decimal.add(acc, Firmowid.SalesInvoices.SalesInvoiceItem.get_net_value(item))
    end)
  end

  def get_vat_value(sales_invoice) do
    Enum.reduce(sales_invoice.sales_invoice_items, Decimal.new(0), fn item, acc ->
      Decimal.add(acc, Firmowid.SalesInvoices.SalesInvoiceItem.get_vat_value(item))
    end)
  end

  def is_confirmed(sales_invoice) do
    sales_invoice.is_basic_info_confirmed &&
      sales_invoice.is_seller_confirmed &&
      sales_invoice.is_buyer_confirmed &&
      sales_invoice.are_sales_invoice_items_confirmed
  end

  def get_gross_value(sales_invoice) do
    Decimal.add(get_net_value(sales_invoice), get_vat_value(sales_invoice))
  end

  def get_currency_conversion_date(sales_invoice) do
    pick_date(
      sales_invoice.issue_date,
      sales_invoice.sale_date,
      Date.compare(sales_invoice.issue_date, sales_invoice.sale_date)
    )
  end

  defp pick_date(issue_date, _sale_date, :lt) do
    issue_date
  end

  defp pick_date(_issue_date, sale_date, _comp) do
    sale_date
  end

  def changeset(sales_invoice, attrs \\ %{}) do
    sales_invoice
    |> cast(attrs, [
      :invoice_type,
      :invoice_number,
      :sale_date,
      :issue_date,
      :due_date,
      :payment_method,
      :currency,
      :is_basic_info_confirmed,
      :is_seller_confirmed,
      :is_buyer_confirmed,
      :are_sales_invoice_items_confirmed,
      :is_cash_account,
      :is_reverse_charge,
      :skip_invoicing
    ])
    |> buyer_changeset(attrs)
    |> seller_changeset(attrs)
    |> cast_assoc(:sales_invoice_items,
      with: &Firmowid.SalesInvoices.SalesInvoiceItem.changeset/2,
      sort_param: :items_sort,
      drop_param: :items_drop
    )
    |> cast_based_on_type
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
    |> unique_constraint([:invoice_number, :organization_id],
        name: :sales_invoices_invoice_number_organization_id_index,
        message: "Invoice number already exists for this organization")
  end

  def seller_changeset(sales_invoice, attrs \\ %{}) do
    sales_invoice
    |> cast(attrs, [
      :seller_nip,
      :seller_display_name,
      :seller_address,
      :seller_name,
      :seller_surname,
      :seller_account_number
    ])
  end

  def buyer_changeset(sales_invoice, attrs \\ %{}) do
    sales_invoice
    |> cast(attrs, [
      :buyer_id,
      :buyer_type,
      :buyer_nip,
      :buyer_display_name,
      :buyer_name,
      :buyer_surname,
      :buyer_pesel,
      :buyer_address,
      :buyer_country,
      :buyer_is_different_mail_address,
      :buyer_mail_address,
      :buyer_mail_country,
      :buyer_email,
      :buyer_phone,
      :buyer_description
    ])
    |> cast_buyer_based_on_type
  end

  def cast_buyer_based_on_type(buyer) do
    case get_change(buyer, :buyer_type) do
      :individual ->
        buyer
        |> put_change(:buyer_nip, "")
        |> put_change(:buyer_display_name, "")

      :company ->
        buyer
        |> put_change(:buyer_pesel, nil)

      nil ->
        buyer
    end
  end

  def cast_based_on_type(sales_invoice) do
    case get_change(sales_invoice, :invoice_type) do
      :poland ->
        sales_invoice
        |> put_change(:currency, "PLN")
        |> put_change(:is_reverse_charge, false)
        |> put_change(:is_basic_info_confirmed, false)

      :foreign ->
        sales_invoice
        |> put_change(:is_cash_account, false)
        |> put_change(:is_basic_info_confirmed, false)

      nil ->
        sales_invoice
    end
  end
end
