defmodule Firmowid.Invoices.Seller do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "sellers" do
    field :name, :string
    field :country, :string
    field :nip, :string
    field :display_name, :string
    field :surname, :string
    field :street, :string
    field :house_number, :string
    field :apartment_number, :string
    field :postal_code, :string
    field :city, :string
    field :account_number, :string
    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(seller, attrs) do
    seller
    |> cast(attrs, [
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
      :account_number
    ])
    |> validate_required([
      :nip,
      :display_name,
      :street,
      :account_number
    ])
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
  end
end
