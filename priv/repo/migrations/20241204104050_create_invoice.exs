defmodule Firmowid.Repo.Migrations.CreateInvoice do
  use Ecto.Migration

  def change do
    create table(:invoices) do
      add :invoice_type, :string

      add :invoice_number, :string
      add :sale_date, :date
      add :issue_date, :date
      add :due_date, :date
      add :payment_method, :string
      add :currency, :string
      add :is_basic_info_confirmed, :boolean, default: false

      add :seller_nip, :string
      add :seller_display_name, :string
      add :seller_address, :string
      add :seller_account_number, :string
      add :seller_name, :string
      add :seller_surname, :string
      add :is_seller_confirmed, :boolean, default: false

      add :buyer_type, :string

      add :buyer_nip, :string
      add :buyer_display_name, :string
      add :buyer_name, :string
      add :buyer_surname, :string

      add :buyer_street, :string
      add :buyer_house_number, :string
      add :buyer_apartment_number, :string
      add :buyer_postal_code, :string
      add :buyer_city, :string
      add :buyer_country, :string

      add :buyer_email, :string
      add :buyer_phone, :string
      add :buyer_description, :string

      add :is_buyer_confirmed, :boolean, default: false

      add :are_invoice_items_confirmed, :boolean, default: false

      add :is_cash_account, :boolean, default: false
      add :is_reverse_charge, :boolean, default: false

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all,
            type: :uuid
          ),
          null: false

      timestamps(type: :utc_datetime)
    end

    create table(:invoice_items) do
      add :name, :string
      add :quantity, :decimal
      add :unit, :string
      add :unit_price, :decimal
      add :vat_rate, :decimal
      add :order, :integer

      add :invoice_id,
          references(:invoices,
            on_delete: :delete_all
          ),
          null: false

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all,
            type: :uuid
          ),
          null: false

      timestamps(type: :utc_datetime)
    end
  end
end
