defmodule Firmowid.GoLimitless.Requisition do
  use Ecto.Schema
  import Ecto.Changeset

  schema "requisitions" do
    field :status,
          Ecto.Enum,
          values: [:pending, :accepted, :rejected]

    field :requisition_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(requisition, attrs) do
    requisition
    |> cast(attrs, [:requisition_id, :status])
    |> validate_required([:requisition_id, :status])
  end
end
