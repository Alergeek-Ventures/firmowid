defmodule Firmowid.CostInvoices.CostInvoice do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "cost_invoices" do
    belongs_to :blob, Firmowid.Blobs.Blob
    belongs_to :inbound_email, Firmowid.CostInvoices.InboundEmail

    field :seller, :string
    field :seller_address, :string
    field :seller_display_name, :string
    field :account_number, :string

    field :sale_date, :date
    field :issue_date, :date
    field :due_date, :date

    field :total_amount, :decimal
    # NOTE: FA(3) schema contains VAT breakdown fields (P_13_1 through P_13_11 for
    # net amounts by rate, P_14_1 through P_14_5 for VAT amounts). These are not
    # stored individually - only the total P_15 is captured in total_amount.
    # Future: Consider adding vat_breakdown JSONB field if detailed VAT needed.
    field :currency, :string

    field :description, :string
    field :invoice_identifier, :string

    field :skip_invoicing, :boolean, default: false

    field :blob_url, :string, virtual: true

    field :ksef_number, :string
    field :ksef_permanent_storage_date, :naive_datetime
    field :ksef_downloaded_at, :utc_datetime_usec

    # probably useless
    field :seller_nip, :string
    field :seller_country_code, :string
    field :seller_email, :string
    field :seller_phone, :string

    field :invoice_type, Ecto.Enum, values: ~w(vat kor zal roz upr kor_zal kor_roz)a
    field :original_invoice_number, :string

    field :payment_method, Ecto.Enum, values: ~w(cash card voucher check loan bank_transfer mobile)a

    many_to_many :transactions,
                 Firmowid.Finances.Transaction,
                 join_through: "cost_invoices_transactions"

    has_many :correction_invoices, __MODULE__,
      foreign_key: :original_invoice_number,
      references: :ksef_number

    belongs_to :original_invoice, __MODULE__,
      foreign_key: :original_invoice_number,
      references: :ksef_number,
      define_field: false

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  @doc false
  def changeset(document, attrs \\ %{}) do
    document
    |> cast(attrs, [
      :blob_id,
      :inbound_email_id,
      :seller,
      :seller_address,
      :seller_display_name,
      :account_number,
      :sale_date,
      :issue_date,
      :due_date,
      :total_amount,
      :currency,
      :description,
      :invoice_identifier,
      :skip_invoicing,
      :organization_id,
      :ksef_number,
      :ksef_permanent_storage_date,
      :ksef_downloaded_at,
      :seller_nip,
      :seller_country_code,
      :seller_email,
      :seller_phone,
      :invoice_type,
      :original_invoice_number,
      :payment_method
    ])
    |> validate_required([
      :seller,
      :seller_display_name,
      :sale_date,
      :issue_date,
      :total_amount,
      :currency,
      :description,
      :invoice_identifier,
      :skip_invoicing,
      :organization_id
    ])
    |> foreign_key_constraint(:inbound_email_id)
    |> unique_constraint(:ksef_number, name: :cost_invoices_ksef_number_idx)
  end
end
