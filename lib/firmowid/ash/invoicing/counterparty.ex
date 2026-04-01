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
      args: [:search_term, {:optional, :type}, {:optional, :sort_by}, {:optional, :sort_order}],
      action: :search
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

    action :search, {:array, :struct} do
      constraints items: [instance_of: __MODULE__]
      description "Full-text search counterparties via ParadeDB."

      argument :search_term, :string
      argument :type, :atom, constraints: [one_of: [:individual, :company]]
      argument :sort_by, :atom, default: :name
      argument :sort_order, :atom, default: :asc, constraints: [one_of: [:asc, :desc]]

      run fn input, context ->
        import Ecto.Query

        search_term = input.arguments[:search_term]
        type = input.arguments[:type]
        sort_by = input.arguments[:sort_by]
        sort_order = input.arguments[:sort_order]
        org_id = context.tenant

        base = from(c in Firmowid.SalesInvoices.Counterparty, where: c.organization_id == ^org_id)

        {search_mode, query} = apply_search(base, search_term)
        query = apply_type_filter(query, type)
        query = apply_sorting(query, search_mode, sort_by, sort_order)
        query = limit(query, 25)

        ecto_rows = Firmowid.Repo.all(query, prepare: :unnamed)

        results =
          Enum.map(ecto_rows, fn row ->
            attrs =
              row
              |> Map.from_struct()
              |> Map.take([
                :id,
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
                :description,
                :inserted_at,
                :updated_at,
                :organization_id
              ])

            struct(__MODULE__, attrs)
          end)

        {:ok, results}
      end
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

    policy action(:search) do
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

  # ── Private helpers for search action ───────────────────────────────

  defp apply_search(query, nil), do: {:no_search, query}
  defp apply_search(query, ""), do: {:no_search, query}

  defp apply_search(query, search_term) do
    import Ecto.Query

    search_query =
      where(
        query,
        [c],
        fragment("? ||| ?", c.display_name, ^search_term) or
          fragment("? ||| ?", c.full_name, ^search_term) or
          fragment("? ||| ?", c.given_name, ^search_term) or
          fragment("? ||| ?", c.surname, ^search_term) or
          fragment("? ||| ?", c.tax_id, ^search_term) or
          fragment("? ||| ?", c.email, ^search_term)
      )

    {:search, search_query}
  end

  defp apply_type_filter(query, nil), do: query

  defp apply_type_filter(query, type) when type in [:individual, :company] do
    import Ecto.Query

    where(query, [c], c.type == ^type)
  end

  defp apply_type_filter(query, _), do: query

  defp apply_sorting(query, :search, _sort_by, _order) do
    import Ecto.Query

    order_by(query, [c], fragment("pdb.score(?) DESC", c.id))
  end

  defp apply_sorting(query, :no_search, :name, order) do
    import Ecto.Query

    order_by(query, [c], [{^order, fragment("COALESCE(?, ?)", c.given_name, c.full_name)}])
  end

  defp apply_sorting(query, :no_search, :display_name, order) do
    import Ecto.Query

    order_by(query, [c], [{^order, fragment("COALESCE(?, ?)", c.full_name, c.given_name)}])
  end

  defp apply_sorting(query, :no_search, :created_at, order) do
    import Ecto.Query

    order_by(query, [c], [{^order, c.inserted_at}])
  end

  defp apply_sorting(query, :no_search, _, order) do
    apply_sorting(query, :no_search, :name, order)
  end
end
