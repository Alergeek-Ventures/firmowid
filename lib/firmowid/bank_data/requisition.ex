defmodule Firmowid.BankData.Requisition do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  schema "requisitions" do
    field :status,
          Ecto.Enum,
          values: [:pending, :accepted, :rejected]

    has_many :bank_accounts, Firmowid.Finances.BankAccount, on_delete: :delete_all

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(requisition, attrs \\ %{}) do
    requisition
    |> cast(attrs, [:status, :organization_id])
    |> validate_required([:status, :organization_id])
  end
end
