defmodule Firmowid.Repo.Migrations.CreateInvoice do
  use Ecto.Migration

  def change do
    create table(:buyers) do
      add :buyer_type, :string

      add :nip, :string
      add :pesel, :string
      add :display_name, :string
      add :name, :string
      add :surname, :string

      add :address, :string, null: false
      add :country, :string, null: false

      add :email, :string
      add :phone, :string
      add :description, :string

      add :is_different_mail_address, :boolean, null: false, default: false
      add :mail_address, :string
      add :mail_country, :string

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all
          ),
          null: false

      timestamps()
    end

    create table(:sellers) do
      add :nip, :string
      add :display_name, :string
      add :name, :string
      add :surname, :string

      add :address, :string

      add :account_number, :string

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all
          ),
          null: false

      timestamps()
    end

    create table(:sales_invoices) do
      add :invoice_type, :string, null: false

      add :invoice_number, :string
      add :sale_date, :date
      add :issue_date, :date
      add :due_date, :date
      add :payment_method, :string
      add :currency, :string, null: false
      add :is_basic_info_confirmed, :boolean, default: false, null: false

      add :seller_id, references(:sellers, on_delete: :nilify_all)
      add :seller_nip, :string
      add :seller_display_name, :string
      add :seller_address, :string
      add :seller_account_number, :string
      add :seller_name, :string
      add :seller_surname, :string
      add :is_seller_confirmed, :boolean, default: false, null: false

      add :buyer_id, references(:buyers, on_delete: :nilify_all)
      add :buyer_type, :string, null: false

      add :buyer_nip, :string
      add :buyer_pesel, :string
      add :buyer_display_name, :string
      add :buyer_name, :string
      add :buyer_surname, :string

      add :buyer_address, :string
      add :buyer_country, :string

      add :buyer_email, :string
      add :buyer_phone, :string
      add :buyer_description, :string

      add :buyer_is_different_mail_address, :boolean, null: false, default: false
      add :buyer_mail_address, :string
      add :buyer_mail_country, :string

      add :is_buyer_confirmed, :boolean, default: false, null: false

      add :are_sales_invoice_items_confirmed, :boolean, default: false, null: false

      add :is_cash_account, :boolean, default: false, null: false
      add :is_reverse_charge, :boolean, default: false, null: false

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all
          ),
          null: false

      timestamps()
    end

    create table(:sales_invoice_items) do
      add :name, :string, null: false
      add :quantity, :decimal, null: false
      add :unit, :string, null: false
      add :unit_price, :decimal, null: false
      add :vat_rate, :decimal

      add :sales_invoice_id,
          references(:sales_invoices, on_delete: :delete_all),
          null: false

      add :organization_id,
          references(:organizations,
            on_delete: :delete_all
          ),
          null: false

      timestamps()
    end
  end
end
