defmodule Firmowid.Finances.ImportedTransaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:transaction_id, :binary_id, autogenerate: false}
  @derive {Phoenix.Param, key: :transaction_id}
  schema "imported_transactions" do
    field :internal_transaction_id, :string
    field :creditor_name, :string
    field :creditor_account, :string
    field :debtor_name, :string
    field :debtor_account, :string
    field :transaction_amount, :float
    field :transaction_currency, :string
    field :booking_date, :date
    field :value_date, :date
    field :remittance_information_unstructured, :string

    belongs_to :bank_account,
               Firmowid.Finances.BankAccount

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(imported_transaction, attrs) do
    imported_transaction
    |> cast(attrs, [
      :transaction_id,
      :debtor_name,
      :debtor_account,
      :transaction_amount,
      :transaction_currency,
      :bank_transaction_code,
      :booking_date,
      :value_date,
      :remittance_information_unstructured
    ])
    |> validate_required([
      :transaction_id,
      :debtor_name,
      :debtor_account,
      :transaction_amount,
      :transaction_currency,
      :bank_transaction_code,
      :booking_date,
      :value_date,
      :remittance_information_unstructured
    ])
  end
end
