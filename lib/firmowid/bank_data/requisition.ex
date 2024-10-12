defmodule Firmowid.BankData.Requisition do
  use Ecto.Schema
  import Ecto.Changeset

  schema "requisitions" do
    field :status,
          Ecto.Enum,
          values: [:pending, :accepted, :rejected]

    field :requisition_id, :string

    has_many :bank_accounts, Firmowid.Finances.BankAccount, on_delete: :delete_all

    belongs_to :organization, Firmowid.Accounts.Organization, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(requisition, attrs) do
    requisition
    |> cast(attrs, [:requisition_id, :status, :organization_id])
    |> validate_required([:requisition_id, :status, :organization_id])
  end
end
