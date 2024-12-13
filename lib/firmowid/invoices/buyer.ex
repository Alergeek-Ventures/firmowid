defmodule Firmowid.Invoices.Buyer do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "buyers" do
    field :name, :string
    field :description, :string
    field :country, :string
    field :buyer_type, Ecto.Enum, values: [:individual, :company]
    field :nip, :string
    field :display_name, :string
    field :surname, :string
    field :street, :string
    field :house_number, :string
    field :apartment_number, :string
    field :postal_code, :string
    field :city, :string
    field :email, :string
    field :phone, :string
    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(buyer, attrs) do
    buyer
    |> cast(attrs, [
      :buyer_type,
      :nip,
      :display_name,
      :name,
      :surname,
      :street,
      :house_number,
      :apartment_number,
      :postal_code,
      :city,
      :country,
      :email,
      :phone,
      :description
    ])
    |> validate_required([
      :buyer_type,
      :nip,
      :display_name,
      :street,
      :postal_code,
      :city,
      :country
    ])
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
  end
end
