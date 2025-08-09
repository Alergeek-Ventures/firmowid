defmodule Firmowid.Finances.BankAccount do
  use Firmowid.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "bank_accounts" do
    field :iban, :string
    field :gocardless_id, :string
    field :institution_id, :string
    field :institution_name, :string
    field :owner_name, :string
    field :currency, :string
    field :name, :string
    field :is_default, :boolean, default: false

    belongs_to :organization, Firmowid.Accounts.Organization
    belongs_to :requisition, Firmowid.BankData.Requisition

    has_many :transactions,
             Firmowid.Finances.Transaction

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(bank_account, attrs \\ %{}) do
    bank_account
    |> cast(attrs, [
      :iban,
      :organization_id,
      :requisition_id,
      :institution_id,
      :institution_name,
      :owner_name,
      :gocardless_id,
      :currency,
      :name,
      :is_default
    ])
    |> validate_required([:iban, :organization_id, :requisition_id])
  end
end
