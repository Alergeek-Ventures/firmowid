defmodule Firmowid.Accounts.Organization do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "organizations" do
    field :identification_number, :string
    field :address, :string
    field :name, :string
    field :phone_number, :string
    field :organization_type, :string
    field :correspondence_name, :string
    field :correspondence_address, :string

    belongs_to :owner, Firmowid.Accounts.User
    has_many :users, Firmowid.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(organization, attrs \\ %{}) do
    organization
    |> cast(attrs, [
      :identification_number,
      :address,
      :name,
      :owner_id,
      :phone_number,
      :organization_type,
      :correspondence_name,
      :correspondence_address
    ])
    |> validate_required([:identification_number, :name, :owner_id])
    |> assoc_constraint(:owner)
  end

  def basic_info_changeset(organization, attrs \\ %{}) do
    organization
    |> cast(
      attrs,
      [:identification_number, :address, :name, :phone_number, :organization_type]
    )
    |> validate_required([:identification_number, :name])
  end

  def correspondence_changeset(organization, attrs \\ %{}) do
    organization
    |> cast(attrs, [:correspondence_name, :correspondence_address])
  end
end
