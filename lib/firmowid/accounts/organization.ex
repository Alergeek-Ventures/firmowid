defmodule Firmowid.Accounts.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "organizations" do
    field :identification_number, :string
    field :address, :string
    field :name, :string
    field :slug, :string
    belongs_to :owner, Firmowid.Accounts.User, type: :binary_id

    has_many :users, Firmowid.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(organization, attrs \\ %{}) do
    organization
    |> cast(attrs, [:identification_number, :address, :name, :slug, :owner_id])
    |> validate_required([:identification_number, :name, :slug, :owner_id])
    |> assoc_constraint(:owner)
    |> unique_constraint(:slug)
  end
end
