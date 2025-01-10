defmodule Firmowid.Accounts.Organization do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "organizations" do
    field :identification_number, :string
    field :address, :string
    field :name, :string

    belongs_to :owner, Firmowid.Accounts.User

    has_many :users, Firmowid.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(organization, attrs \\ %{}) do
    organization
    |> cast(attrs, [:identification_number, :address, :name, :owner_id])
    |> validate_required([:identification_number, :name, :owner_id])
    |> assoc_constraint(:owner)
  end
end
