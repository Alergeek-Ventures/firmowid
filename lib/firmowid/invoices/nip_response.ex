defmodule NipResponse do
  @moduledoc """
  Embedded schema representing the complete response from the VAT registry
  """
  alias Firmowid.Invoices.NipResponsePerson
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :nip, :string
    field :status_vat, :string
    field :regon, :string
    field :pesel, :string
    field :krs, :string
    field :residence_address, :string
    field :working_address, :string
    field :registration_legal_date, :string
    field :registration_denial_date, :string
    field :registration_denial_basis, :string
    field :restoration_date, :string
    field :restoration_basis, :string
    field :removal_date, :string
    field :removal_basis, :string
    embeds_many :representatives, NipResponsePerson
    embeds_many :authorized_clerks, NipResponsePerson
    embeds_many :partners, NipResponsePerson
    field :account_numbers, {:array, :string}
    field :has_virtual_accounts, :boolean
  end

  def changeset(response, attrs) do
    response
    |> cast(attrs, [
      :name,
      :nip,
      :status_vat,
      :regon,
      :pesel,
      :krs,
      :residence_address,
      :working_address,
      :registration_legal_date,
      :registration_denial_date,
      :registration_denial_basis,
      :restoration_date,
      :restoration_basis,
      :removal_date,
      :removal_basis,
      :account_numbers,
      :has_virtual_accounts
    ])
    |> validate_status_vat()
    |> cast_embed(:representatives)
    |> cast_embed(:authorized_clerks)
    |> cast_embed(:partners)
  end

  defp validate_status_vat(changeset) do
    validate_inclusion(changeset, :status_vat, ["Czynny", "Zwolniony", "Niezarejestrowany"])
  end
end
