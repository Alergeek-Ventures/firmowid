defmodule Firmowid.Invoices.Invoice do
  use Ecto.Schema
  import Ecto.Changeset

  schema "invoices" do
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

    field :buyer_type, Ecto.Enum, values: [:individual, :company]

    field :buyer_nip, :string
    field :buyer_display_name, :string
    field :buyer_name, :string
    field :buyer_surname, :string

    field :buyer_street, :string
    field :buyer_house_number, :string
    field :buyer_apartment_number, :string
    field :buyer_postal_code, :string
    field :buyer_city, :string
    field :buyer_country, :string

    field :buyer_email, :string
    field :buyer_phone, :string
    field :buyer_description, :string
    field :is_buyer_confirmed, :boolean, default: false

    field :are_invoice_items_confirmed, :boolean, default: false

    field :is_cash_account, :boolean, default: false
    field :is_reverse_charge, :boolean, default: false

    has_many :invoice_items, Firmowid.Invoices.InvoiceItem, on_replace: :delete
    belongs_to :organization, Firmowid.Accounts.Organization, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def get_net_value(invoice) do
    Enum.reduce(invoice.invoice_items, Decimal.new(0), fn item, acc ->
      Decimal.add(acc, Firmowid.Invoices.InvoiceItem.get_net_value(item))
    end)
  end

  def get_vat_value(invoice) do
    Enum.reduce(invoice.invoice_items, Decimal.new(0), fn item, acc ->
      Decimal.add(acc, Firmowid.Invoices.InvoiceItem.get_vat_value(item))
    end)
  end

  def get_gross_value(invoice) do
    Decimal.add(get_net_value(invoice), get_vat_value(invoice))
  end

  def get_currency_conversion_date(invoice) do
    pick_date(
      invoice.issue_date,
      invoice.sale_date,
      Date.compare(invoice.issue_date, invoice.sale_date)
    )
  end

  defp pick_date(issue_date, _sale_date, :lt) do
    issue_date
  end

  defp pick_date(_issue_date, sale_date, _comp) do
    sale_date
  end

  def get_address_line_1(invoice) do
    address =
      case [
        invoice.buyer_street,
        invoice.buyer_house_number
      ] do
        [nil, nil] -> ""
        [street, nil] -> street
        [nil, _house_number] -> ""
        [street, house_number] -> street <> " " <> house_number
      end

    case invoice.buyer_apartment_number do
      nil ->
        address

      apartment_number ->
        address <> "/" <> apartment_number
    end
  end

  def get_address_line_2(invoice) do
    Enum.join(
      [
        invoice.buyer_postal_code,
        invoice.buyer_city
      ]
      |> Enum.reject(&is_nil/1),
      " "
    )
    |> case do
      "" -> nil
      address -> address
    end
  end

  def get_address_lines(invoice) do
    Enum.join(
      [get_address_line_1(invoice), get_address_line_2(invoice)] |> Enum.reject(&is_nil/1),
      ", "
    )
  end

  def changeset(invoice, attrs \\ %{}) do
    invoice
    |> cast(attrs, [
      :invoice_type,
      :organization_id,
      :invoice_number,
      :sale_date,
      :issue_date,
      :due_date,
      :payment_method,
      :currency,
      :is_basic_info_confirmed,
      :seller_nip,
      :seller_display_name,
      :seller_address,
      :seller_name,
      :seller_surname,
      :seller_account_number,
      :is_seller_confirmed,
      :buyer_type,
      :buyer_nip,
      :buyer_display_name,
      :buyer_name,
      :buyer_surname,
      :buyer_street,
      :buyer_house_number,
      :buyer_apartment_number,
      :buyer_postal_code,
      :buyer_city,
      :buyer_country,
      :buyer_email,
      :buyer_phone,
      :buyer_description,
      :is_buyer_confirmed,
      :are_invoice_items_confirmed,
      :is_cash_account,
      :is_reverse_charge
    ])
    |> cast_assoc(:invoice_items,
      with: &Firmowid.Invoices.InvoiceItem.changeset/2,
      sort_param: :items_sort,
      drop_param: :items_drop
    )
    |> cast_based_on_type
  end

  def cast_based_on_type(invoice) do
    case get_change(invoice, :invoice_type) do
      :poland ->
        invoice
        |> put_change(:currency, "PLN")
        |> put_change(:is_reverse_charge, false)
        |> put_change(:is_basic_info_confirmed, false)

      :foreign ->
        invoice
        |> put_change(:is_cash_account, false)
        |> put_change(:is_basic_info_confirmed, false)

      nil ->
        invoice
    end
  end
end
