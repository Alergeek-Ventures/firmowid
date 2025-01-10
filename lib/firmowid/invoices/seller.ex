defmodule Firmowid.Invoices.Seller do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "sellers" do
    field :name, :string
    field :nip, :string
    field :display_name, :string
    field :surname, :string
    field :address, :string
    field :account_number, :string
    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  @doc false
  def changeset(seller, attrs) do
    seller
    |> cast(attrs, [
      :nip,
      :display_name,
      :name,
      :surname,
      :address,
      :account_number
    ])
    |> validate_required([
      :nip,
      :display_name,
      :address,
      :account_number
    ])
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
  end
end
