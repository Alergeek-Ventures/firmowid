defmodule Firmowid.SalesInvoices.Counterparty do
  @moduledoc """
  Represents a counterparty (buyer) entity that can be linked to sales invoices.

  A counterparty stores all the buyer information and can be reused across multiple
  invoices. This allows for easier management of recurring buyers and provides
  a single source of truth for buyer data.
  """
  use Firmowid.Schema

  import Ecto.Changeset

  alias Firmowid.SalesInvoices.CountryCodes
  alias Firmowid.SalesInvoices.SalesInvoice

  @type t :: %__MODULE__{}

  schema "counterparties" do
    field :type, Ecto.Enum, values: [:individual, :company], default: :company
    field :tax_id, :string
    field :display_name, :string
    field :name, :string
    field :surname, :string
    field :pesel, :string

    field :address, :string
    field :country, :string

    field :is_different_mail_address, :boolean, default: false
    field :mail_address, :string
    field :mail_country, :string

    field :email, :string
    field :phone, :string
    field :description, :string

    belongs_to :organization, Firmowid.Accounts.Organization
    has_many :sales_invoices, SalesInvoice

    timestamps()
  end

  @doc """
  Creates a changeset for a counterparty.
  """
  def changeset(counterparty, attrs \\ %{}) do
    counterparty
    |> cast(attrs, [
      :type,
      :tax_id,
      :display_name,
      :name,
      :surname,
      :pesel,
      :address,
      :country,
      :is_different_mail_address,
      :mail_address,
      :mail_country,
      :email,
      :phone,
      :description
    ])
    |> validate_required([:type])
    |> validate_country_code(:country)
    |> validate_country_code(:mail_country)
    |> validate_tax_id()
    |> cast_based_on_type()
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
  end

  defp validate_country_code(changeset, field) do
    changeset
    |> update_change(field, &CountryCodes.normalize/1)
    |> validate_change(field, fn ^field, value ->
      if is_nil(value) or CountryCodes.valid_country?(value) do
        []
      else
        [{field, "musi być prawidłowym kodem ISO kraju"}]
      end
    end)
  end

  @spec tax_id_type(map() | Ecto.Changeset.t()) :: :nip | :eu_vat | :other_id | :no_id
  def tax_id_type(%{pesel: pesel, country: country}) do
    cond do
      not is_nil(pesel) and pesel != "" -> :no_id
      country == "PL" -> :nip
      CountryCodes.eu_country?(country) -> :eu_vat
      true -> :other_id
    end
  end

  def tax_id_type(%Ecto.Changeset{} = changeset) do
    pesel = get_field(changeset, :pesel)
    country = get_field(changeset, :country)

    tax_id_type(%{pesel: pesel, country: country})
  end

  defp validate_tax_id(changeset) do
    case tax_id_type(changeset) do
      :nip ->
        validate_format(changeset, :tax_id, ~r/^(\d{10})?$/, message: "musi być 10-cyfrowym numerem NIP")

      _ ->
        validate_length(changeset, :tax_id, max: 50, message: "musi mieć maksymalnie 50 znaków")
    end
  end

  defp cast_based_on_type(changeset) do
    case get_change(changeset, :type) do
      :individual ->
        changeset
        |> put_change(:tax_id, "")
        |> put_change(:display_name, "")

      :company ->
        put_change(changeset, :pesel, nil)

      nil ->
        changeset
    end
  end

  @doc """
  Returns true if the counterparty is from an EU country.
  """
  @spec from_eu?(t()) :: boolean()
  def from_eu?(%__MODULE__{country: country}) when is_binary(country) do
    CountryCodes.eu_country?(country)
  end

  def from_eu?(_), do: false

  @doc """
  Returns the counterparty's region (:eu, :non_eu, or :invalid).
  """
  @spec region(t()) :: :eu | :non_eu | :invalid
  def region(%__MODULE__{country: country}) when is_binary(country) do
    CountryCodes.region(country)
  end

  def region(_), do: :invalid

  @doc """
  Returns the full name for display purposes.
  For companies, returns the display_name.
  For individuals, returns "name surname".
  """
  @spec display_label(t()) :: String.t()
  def display_label(%__MODULE__{type: :company, display_name: name}) when is_binary(name), do: name

  def display_label(%__MODULE__{type: :individual, name: name, surname: surname}) do
    [name, surname]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  def display_label(_), do: ""
end
