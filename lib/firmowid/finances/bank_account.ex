defmodule Firmowid.Finances.BankAccount do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bank_accounts" do
    field :iban, :string

    has_many :imported_transactions,
             Firmowid.Finances.ImportedTransaction

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bank_account, attrs) do
    bank_account
    |> cast(attrs, [:iban])
    |> validate_required([:iban])
  end
end
