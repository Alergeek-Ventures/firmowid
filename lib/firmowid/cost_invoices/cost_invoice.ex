defmodule Firmowid.CostInvoices.CostInvoice do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "cost_invoices" do
    belongs_to :blob, Firmowid.Ash.Blobs.Blob
    belongs_to :inbound_email, Firmowid.CostInvoices.InboundEmail

    field :seller, :string
    field :seller_address, :string
    field :seller_display_name, :string
    field :account_number, :string

    field :sale_date, :date
    field :issue_date, :date
    field :due_date, :date

    field :total_amount, :decimal
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
    field :original_invoice_ksef_number, :string

    field :payment_method, Ecto.Enum, values: ~w(cash card voucher check loan bank_transfer mobile)a

    many_to_many :transactions,
                 Firmowid.Ash.Finances.Transaction,
                 join_through: "cost_invoices_transactions"

    has_many :correction_invoices, __MODULE__,
      foreign_key: :original_invoice_ksef_number,
      preload_order: [asc: :ksef_permanent_storage_date],
      references: :ksef_number

    belongs_to :original_invoice, __MODULE__,
      foreign_key: :original_invoice_ksef_number,
      references: :ksef_number,
      define_field: false

    has_many :entity_tags,
             {"cost_invoice_entity_tags", Firmowid.Ash.Analysis.EntityTag},
             foreign_key: :resource_id

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
      :original_invoice_ksef_number,
      :payment_method
    ])
    |> validate_required(
      [
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
      ],
      message: "nie może być puste"
    )
    |> validate_non_correction_total_amount_sign()
    |> check_constraint(:total_amount,
      name: :cost_invoices_non_correction_total_amount_non_positive,
      message: "jest nieprawidłowe"
    )
    |> foreign_key_constraint(:inbound_email_id, message: "nie istnieje")
    |> unique_constraint(:ksef_number, name: :cost_invoices_ksef_number_idx, message: "jest już zajęte")
  end

  defp validate_non_correction_total_amount_sign(changeset) do
    invoice_type = get_field(changeset, :invoice_type)
    total_amount = get_field(changeset, :total_amount)

    cond do
      invoice_type in [:kor, :kor_zal, :kor_roz] ->
        changeset

      is_nil(total_amount) or Decimal.gt?(total_amount, 0) ->
        add_error(changeset, :total_amount, "musi być mniejsze lub równe 0 dla faktur niebędących korektami")

      true ->
        changeset
    end
  end

  @doc """
  Returns true when invoice data was imported from KSeF FA(3) XML.
  """
  @spec ksef_imported?(t()) :: boolean()
  def ksef_imported?(%__MODULE__{ksef_downloaded_at: nil, ksef_permanent_storage_date: nil, ksef_number: nil}), do: false
  def ksef_imported?(%__MODULE__{}), do: true

  @doc """
  Returns true if the invoice can be deleted.
  """
  @spec deletable?(t()) :: boolean()
  def deletable?(%__MODULE__{} = invoice), do: not ksef_imported?(invoice)
end
