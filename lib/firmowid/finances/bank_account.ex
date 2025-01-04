defmodule Firmowid.Finances.BankAccount do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bank_accounts" do
    field :iban, :string
    field :gocardless_id, :string
    belongs_to :organization, Firmowid.Accounts.Organization, type: :binary_id
    belongs_to :requisition, Firmowid.BankData.Requisition

    has_many :imported_transactions,
             Firmowid.Finances.ImportedTransaction

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bank_account, attrs \\ %{}) do
    bank_account
    |> cast(attrs, [:iban, :organization_id, :requisition_id, :gocardless_id])
    |> validate_required([:iban, :organization_id, :requisition_id])
  end
end
