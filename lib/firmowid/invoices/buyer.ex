defmodule Firmowid.Invoices.Buyer do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "buyers" do
    field :buyer_type, Ecto.Enum, values: [:individual, :company], default: :company
    field :nip, :string
    field :display_name, :string
    field :name, :string
    field :surname, :string
    field :pesel, :string
    field :street, :string
    field :postal_code, :string
    field :city, :string
    field :country, :string
    field :email, :string
    field :phone, :string
    field :description, :string

    field :is_different_mail_address, :boolean, default: false
    field :mail_street, :string
    field :mail_postal_code, :string
    field :mail_city, :string
    field :mail_country, :string

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
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
      :pesel,
      :street,
      :postal_code,
      :city,
      :country,
      :email,
      :phone,
      :description,
      :is_different_mail_address,
      :mail_street,
      :mail_postal_code,
      :mail_city,
      :mail_country
    ])
    |> validate_required([
      :buyer_type,
      :street,
      :postal_code,
      :city,
      :country
    ])
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
  end

  def get_name(%{buyer_type: :individual, name: name, surname: surname}),
    do: "#{name} #{surname}"

  def get_name(%{buyer_type: :company, display_name: display_name}),
    do: display_name
end
