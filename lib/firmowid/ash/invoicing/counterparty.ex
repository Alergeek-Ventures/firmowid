defmodule Firmowid.Ash.Invoicing.Counterparty do
  @moduledoc """
  Ash resource for counterparties (buyers) linked to sales invoices.

  Stores buyer information reusable across invoices. Supports full CRUD,
  ParadeDB full-text search, and type-specific validations (NIP, EU VAT, etc.).

  ## Calculations

    * `:display_label` — human-friendly name (display_name > full_name > given_name surname)
    * `:tax_id_type` — `:nip | :eu_vat | :other_id | :optional_id | :no_id`

  ## Public functions

    * `validate_nip/2`, `validate_eu_vat/2`, `validate_optional_id/2` — changeset
      validators imported by the legacy `SalesInvoice` Ecto schema until Slice 7.
    * `display_label/1` — imperative version of the `:display_label` calculation.
    * `tax_id_type/1` — imperative version of the `:tax_id_type` calculation.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  import Ecto.Changeset, only: [validate_format: 4, validate_length: 3]

  alias Firmowid.Ash.Invoicing.Calculations.CounterpartyDisplayLabel
  alias Firmowid.Ash.Invoicing.Calculations.CounterpartyTaxIdType
  alias Firmowid.Ash.Invoicing.Changes.ValidateCounterparty
  alias Firmowid.Ash.Resource
  alias Firmowid.SalesInvoices.CountryCodes

  require Ash.Query
  require Resource

  postgres do
    table "counterparties"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :list_all, action: :list_all
    define :get, args: [:id], action: :by_id
    define :create
    define :update
    define :destroy

    define :search,
      args: [:search_term, {:optional, :type}, {:optional, :sort_by}, {:optional, :sort_order}]
  end

  actions do
    defaults [:read, :destroy]

    read :by_id do
      get_by [:id]
    end

    read :list_all do
      prepare build(sort: [list_all_order: :asc])
    end

    create :create do
      accept [
        :type,
        :tax_id,
        :full_name,
        :given_name,
        :surname,
        :pesel,
        :display_name,
        :address,
        :country,
        :is_different_mail_address,
        :mail_address,
        :mail_country,
        :email,
        :phone,
        :description
      ]

      change {ValidateCounterparty, []}
    end

    update :update do
      require_atomic? false

      accept [
        :type,
        :tax_id,
        :full_name,
        :given_name,
        :surname,
        :pesel,
        :display_name,
        :address,
        :country,
        :is_different_mail_address,
        :mail_address,
        :mail_country,
        :email,
        :phone,
        :description
      ]

      change {ValidateCounterparty, []}
    end

    read :search do
      description "Full-text search counterparties via ParadeDB."

      argument :search_term, :string
      argument :type, :atom, constraints: [one_of: [:individual, :company]]
      argument :sort_by, :atom, default: :name
      argument :sort_order, :atom, default: :asc, constraints: [one_of: [:asc, :desc]]

      prepare {Firmowid.Ash.Preparations.ParadeDBSearch,
               columns: ~w(display_name full_name given_name surname tax_id email),
               operator: :disjunction,
               argument: :search_term}

      prepare Firmowid.Ash.Invoicing.Preparations.CounterpartySearchSort

      filter expr(is_nil(^arg(:type)) or type == ^arg(:type))

      prepare build(limit: 25)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:update) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if always()
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :type, :atom,
      public?: true,
      constraints: [one_of: [:individual, :company]],
      default: :company

    attribute :tax_id, :string, public?: true
    attribute :full_name, :string, public?: true
    attribute :given_name, :string, public?: true
    attribute :surname, :string, public?: true
    attribute :pesel, :string, public?: true
    attribute :display_name, :string, public?: true
    attribute :address, :string, public?: true
    attribute :country, :string, public?: true
    attribute :is_different_mail_address, :boolean, public?: true, default: false
    attribute :mail_address, :string, public?: true
    attribute :mail_country, :string, public?: true
    attribute :email, :string, public?: true
    attribute :phone, :string, public?: true
    attribute :description, :string, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  calculations do
    calculate :display_label, :string, CounterpartyDisplayLabel
    calculate :tax_id_type, :atom, CounterpartyTaxIdType
    calculate :list_all_order, :string, expr(fragment("COALESCE(?, ?)", display_name, surname))
  end

  # ── Public functions (imperative API) ───────────────────────────────

  @doc """
  Returns the display label for a counterparty struct.

  Imperative version of the `:display_label` calculation. Used in templates
  that receive pre-loaded structs (e.g. management views).
  """
  @spec display_label(map()) :: String.t()
  def display_label(%{display_name: name}) when is_binary(name) and name != "", do: name
  def display_label(%{type: :company, full_name: name}) when is_binary(name), do: name

  def display_label(%{type: :individual, given_name: given_name, surname: surname}) do
    [given_name, surname]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  def display_label(_), do: ""

  @doc """
  Returns the tax ID type for a counterparty struct or changeset.
  """
  @spec tax_id_type(map() | Ecto.Changeset.t()) ::
          :nip | :eu_vat | :other_id | :optional_id | :no_id
  def tax_id_type(%{pesel: pesel, country: country}) do
    CountryCodes.tax_id_type(country, pesel)
  end

  def tax_id_type(%Ecto.Changeset{} = changeset) do
    pesel = Ecto.Changeset.get_field(changeset, :pesel)
    country = Ecto.Changeset.get_field(changeset, :country)
    tax_id_type(%{pesel: pesel, country: country})
  end

  @doc "Validates a Polish NIP format on the given changeset field."
  @spec validate_nip(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_nip(changeset, field) do
    validate_format(changeset, field, ~r/^[1-9]((\d[1-9])|([1-9]\d))\d{7}$/, message: "musi być numerem NIP")
  end

  @doc "Validates an EU VAT number format on the given changeset field."
  @spec validate_eu_vat(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_eu_vat(changeset, field) do
    validate_format(changeset, field, ~r/^(\d|[A-Z]|\+|\*){1,12}$/, message: "musi być numerem VAT-EU")
  end

  @doc "Validates optional ID length (max 50) on the given changeset field."
  @spec validate_optional_id(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_optional_id(changeset, field) do
    validate_length(changeset, field, max: 50, message: "musi mieć maksymalnie 50 znaków")
  end
end
