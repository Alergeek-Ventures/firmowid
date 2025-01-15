defmodule Firmowid.SalesInvoices.NipResponsePerson do
  @moduledoc """
  Embedded schema representing a person entity (representative, clerk, or partner)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :company_name, :string
    field :first_name, :string
    field :last_name, :string
    field :pesel, :string
    field :nip, :string
  end

  def changeset(person, attrs) do
    person
    |> cast(attrs, [:company_name, :first_name, :last_name, :pesel, :nip])
  end
end
