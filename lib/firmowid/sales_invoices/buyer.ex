defmodule Firmowid.SalesInvoices.Buyer do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "buyers" do
    field :buyer_type, Ecto.Enum, values: [:individual, :company], default: :company
    field :nip, :string
    field :display_name, :string
    field :name, :string
    field :surname, :string
    field :pesel, :string
    field :address, :string
    field :country, :string
    field :email, :string
    field :phone, :string
    field :description, :string

    field :is_different_mail_address, :boolean, default: false
    field :mail_address, :string
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
      :address,
      :country,
      :email,
      :phone,
      :description,
      :is_different_mail_address,
      :mail_address,
      :mail_country
    ])
    |> validate_required([
      :buyer_type,
      :address,
      :country
    ])
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
  end

  def get_name(%{buyer_type: :individual, name: name, surname: surname}),
    do: "#{name} #{surname}"

  def get_name(%{buyer_type: :company, display_name: display_name}),
    do: display_name
end
