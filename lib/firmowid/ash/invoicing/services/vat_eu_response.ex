defmodule Firmowid.Ash.Invoicing.Services.VatEuResponse do
  @moduledoc """
  Embedded schema representing the response from the EU VIES VAT API.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  @type t :: %__MODULE__{
          country_code: String.t() | nil,
          vat_number: String.t() | nil,
          request_date: String.t() | nil,
          valid: boolean() | nil,
          request_identifier: String.t() | nil,
          name: String.t() | nil,
          address: String.t() | nil,
          trader_name: String.t() | nil,
          trader_street: String.t() | nil,
          trader_postal_code: String.t() | nil,
          trader_city: String.t() | nil,
          trader_company_type: String.t() | nil,
          trader_name_match: String.t() | nil,
          trader_street_match: String.t() | nil,
          trader_postal_code_match: String.t() | nil,
          trader_city_match: String.t() | nil,
          trader_company_type_match: String.t() | nil
        }

  embedded_schema do
    field :country_code, :string
    field :vat_number, :string
    field :request_date, :string
    field :valid, :boolean
    field :request_identifier, :string
    field :name, :string
    field :address, :string
    field :trader_name, :string
    field :trader_street, :string
    field :trader_postal_code, :string
    field :trader_city, :string
    field :trader_company_type, :string
    field :trader_name_match, :string
    field :trader_street_match, :string
    field :trader_postal_code_match, :string
    field :trader_city_match, :string
    field :trader_company_type_match, :string
  end

  def changeset(response, attrs) do
    response
    |> cast(attrs, [
      :country_code,
      :vat_number,
      :request_date,
      :valid,
      :request_identifier,
      :name,
      :address,
      :trader_name,
      :trader_street,
      :trader_postal_code,
      :trader_city,
      :trader_company_type,
      :trader_name_match,
      :trader_street_match,
      :trader_postal_code_match,
      :trader_city_match,
      :trader_company_type_match
    ])
    |> validate_match(:trader_name_match)
    |> validate_match(:trader_street_match)
    |> validate_match(:trader_postal_code_match)
    |> validate_match(:trader_city_match)
    |> validate_match(:trader_company_type_match)
  end

  defp validate_match(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case value do
        nil ->
          []

        match when match in ["VALID", "INVALID", "NOT_PROCESSED"] ->
          []

        _ ->
          [{field, "is invalid"}]
      end
    end)
  end
end
