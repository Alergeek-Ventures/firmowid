defmodule Firmowid.Finances.ImportedTransaction do
  use Firmowid.Schema
  import Ecto.Changeset

  alias Firmowid.Documents

  schema "imported_transactions" do
    # imported data
    field :transaction_id, :string
    field :internal_transaction_id, :string
    field :creditor_name, :string
    field :creditor_account, :string
    field :debtor_name, :string
    field :debtor_account, :string
    field :transaction_amount, :decimal
    field :transaction_currency, :string
    field :booking_date, :date
    field :value_date, :date
    field :remittance_information_unstructured, :string

    # firmowid data
    field :skip_invoicing, :boolean, default: false

    belongs_to :bank_account,
               Firmowid.Finances.BankAccount

    many_to_many :document_transactions,
                 Documents.Document,
                 join_through: "documents_imported_transactions",
                 join_keys: [
                   imported_transaction_id: :id,
                   document_id: :id
                 ]

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(imported_transaction, attrs) do
    imported_transaction
    |> cast(attrs, [
      :transaction_id,
      :internal_transaction_id,
      :creditor_name,
      :creditor_account,
      :debtor_name,
      :debtor_account,
      :transaction_amount,
      :transaction_currency,
      :booking_date,
      :value_date,
      :remittance_information_unstructured,
      :transaction_id,
      :skip_invoicing,
      :bank_account_id,
      :organization_id
    ])
    |> validate_required([
      :creditor_name,
      :creditor_account,
      :debtor_name,
      :debtor_account,
      :transaction_amount,
      :transaction_currency,
      :booking_date,
      :bank_account_id,
      :organization_id
    ])
  end
end
