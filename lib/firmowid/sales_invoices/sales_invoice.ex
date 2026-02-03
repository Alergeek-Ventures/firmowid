defmodule Firmowid.SalesInvoices.SalesInvoice do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  alias Firmowid.SalesInvoices.Counterparty
  alias Firmowid.SalesInvoices.CountryCodes
  alias Firmowid.SalesInvoices.SalesInvoiceItem

  @type t :: %__MODULE__{}

  schema "sales_invoices" do
    field :invoice_type, Ecto.Enum, values: [:poland, :foreign], default: :poland

    field :invoice_number, :string
    field :sale_date, :date
    field :issue_date, :date
    field :due_date, :date
    field :payment_method, Ecto.Enum, values: ~w[cash card voucher check credit transfer mobile]a, default: :transfer
    field :currency, :string

    field :seller_nip, :string
    field :seller_display_name, :string
    field :seller_address, :string
    field :seller_name, :string
    field :seller_surname, :string
    field :seller_account_number, :string

    field :buyer_type, Ecto.Enum, values: [:individual, :company], default: :company

    field :buyer_id, :string
    # For companies: legal business name. For individuals: NULL
    field :buyer_full_name, :string
    # For individuals: first name. For companies: NULL
    field :buyer_given_name, :string
    field :buyer_surname, :string
    field :buyer_pesel, :string
    # Optional short/friendly display name for both types
    field :buyer_display_name, :string

    field :buyer_address, :string
    field :buyer_country, :string

    field :buyer_is_different_mail_address, :boolean, default: false
    field :buyer_mail_address, :string
    field :buyer_mail_country, :string

    field :buyer_email, :string
    field :buyer_phone, :string
    field :buyer_description, :string

    field :is_cash_account, :boolean, default: false
    field :is_reverse_charge, :boolean, default: false

    field :skip_invoicing, :boolean, default: false

    field :logo_url, :string, virtual: true
    field :total_amount, :decimal, virtual: true
    field :due_date_days, :integer, virtual: true

    field :item_names, :string

    # KSeF submission tracking
    field :ksef_number, :string
    field :ksef_session_reference_number, :string
    field :locked_at, :utc_datetime

    # KSeF FA(3) fields
    field :ksef_invoice_kind, Ecto.Enum, values: [:vat, :kor], default: :vat

    belongs_to :corrected_invoice, __MODULE__
    has_many :corrections, __MODULE__, foreign_key: :corrected_invoice_id

    has_many :sales_invoice_items, SalesInvoiceItem,
      preload_order: [asc: :index],
      on_replace: :delete

    many_to_many :transactions,
                 Firmowid.Finances.Transaction,
                 join_through: "sales_invoices_transactions"

    belongs_to :counterparty, Counterparty
    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  def get_net_value(%{sales_invoice_items: items, currency: currency}) do
    currency
    |> Money.new(
      Enum.reduce(items, Decimal.new(0), fn item, acc ->
        Decimal.add(acc, SalesInvoiceItem.get_net_value(item))
      end)
    )
    |> Money.round()
    |> Money.to_decimal()
  end

  def get_vat_value(%{sales_invoice_items: items, currency: currency}) do
    currency
    |> Money.new(
      Enum.reduce(items, Decimal.new(0), fn item, acc ->
        Decimal.add(acc, SalesInvoiceItem.get_vat_value(item))
      end)
    )
    |> Money.round()
    |> Money.to_decimal()
  end

  def get_gross_value(sales_invoice) do
    sales_invoice.currency
    |> Money.new(Decimal.add(get_net_value(sales_invoice), get_vat_value(sales_invoice)))
    |> Money.round()
    |> Money.to_decimal()
  end

  @doc """
  Returns true if the invoice is a draft (has no invoice number assigned).

  Drafts are invoices saved mid-wizard before confirmation.
  They can be edited freely and don't appear in invoice numbering.
  """
  @spec draft?(t()) :: boolean()
  def draft?(%__MODULE__{invoice_number: nil}), do: true
  def draft?(%__MODULE__{invoice_number: _}), do: false

  @doc """
  Returns true if the invoice is confirmed (has an invoice number assigned).

  Confirmed invoices have completed the wizard flow and received a number.
  They can still be edited until locked/submitted to KSeF.
  """
  @spec confirmed?(t()) :: boolean()
  def confirmed?(%__MODULE__{invoice_number: nil}), do: false
  def confirmed?(%__MODULE__{invoice_number: _}), do: true

  def get_currency_conversion_date(sales_invoice) do
    pick_date(
      sales_invoice.issue_date,
      sales_invoice.sale_date,
      Date.compare(sales_invoice.issue_date, sales_invoice.sale_date)
    )
  end

  defp pick_date(issue_date, _sale_date, :lt) do
    issue_date
  end

  defp pick_date(_issue_date, sale_date, _comp) do
    sale_date
  end

  @spec buyer_id_type(map() | Ecto.Changeset.t()) :: :nip | :eu_vat | :other_id | :optional_id | :no_id
  def buyer_id_type(%{buyer_type: buyer_type, buyer_pesel: buyer_pesel, buyer_country: buyer_country}) do
    CountryCodes.tax_id_type(buyer_country, buyer_pesel, buyer_type)
  end

  # Fallback for maps without buyer_type (backwards compatibility)
  def buyer_id_type(%{buyer_pesel: buyer_pesel, buyer_country: buyer_country}) do
    buyer_id_type(%{buyer_type: nil, buyer_pesel: buyer_pesel, buyer_country: buyer_country})
  end

  def buyer_id_type(%Ecto.Changeset{} = changeset) do
    buyer_type = get_field(changeset, :buyer_type)
    buyer_pesel = get_field(changeset, :buyer_pesel)
    buyer_country = get_field(changeset, :buyer_country)

    buyer_id_type(%{buyer_type: buyer_type, buyer_pesel: buyer_pesel, buyer_country: buyer_country})
  end

  def changeset(sales_invoice, attrs \\ %{}) do
    sales_invoice
    |> check_if_locked()
    |> cast(attrs, [
      :invoice_type,
      :invoice_number,
      :sale_date,
      :issue_date,
      :due_date,
      :payment_method,
      :currency,
      :is_cash_account,
      :is_reverse_charge,
      :skip_invoicing,
      :ksef_invoice_kind,
      :counterparty_id
    ])
    |> buyer_changeset(attrs)
    |> seller_changeset(attrs)
    |> cast_assoc(:sales_invoice_items,
      with: &SalesInvoiceItem.changeset/2,
      sort_param: :items_sort,
      drop_param: :items_drop
    )
    |> cast_based_on_type()
    |> put_change(:organization_id, Firmowid.Repo.get_org_id())
    |> unique_constraint([:invoice_number, :organization_id],
      name: :sales_invoices_invoice_number_organization_id_index,
      message: "Invoice number already exists for this organization"
    )
  end

  def step1_changeset(sales_invoice, attrs \\ %{}) do
    sales_invoice
    |> cast(attrs, [
      :counterparty_id,
      :buyer_id,
      :buyer_type,
      :buyer_full_name,
      :buyer_given_name,
      :buyer_surname,
      :buyer_pesel,
      :buyer_address,
      :buyer_country,
      :buyer_email,
      :buyer_phone,
      :buyer_description,
      :buyer_display_name,
      # buyer infered fields:
      :invoice_type,
      :is_reverse_charge,
      :currency,
      :seller_account_number
    ])
    |> validate_required([:buyer_country, :buyer_address])
    |> validate_country_code(:buyer_country)
    |> validate_buyer_id()
    |> validate_buyer_id_required_for_ksef()
    |> validate_buyer_name_fields()
    |> cast_based_on_type()
  end

  def step2_changeset(sales_invoice, attrs \\ %{}) do
    sales_invoice
    |> cast(attrs, [:currency, :is_reverse_charge])
    |> cast_assoc(:sales_invoice_items,
      with: &SalesInvoiceItem.new_changeset/3,
      required: true,
      sort_param: :items_sort,
      drop_param: :items_drop
    )
    |> validate_required([:currency])
    |> validate_format(:currency, ~r/^[A-Z]{3}$/)
  end

  def step3_changeset(sales_invoice, attrs \\ %{}) do
    sales_invoice
    |> cast(attrs, [:sale_date, :due_date, :due_date_days, :payment_method, :seller_account_number])
    |> calculate_due_date()
    |> validate_required([:sale_date, :due_date, :payment_method, :seller_account_number])
  end

  defp calculate_due_date(changeset) do
    sale_date = get_field(changeset, :sale_date)
    due_date_days = get_field(changeset, :due_date_days)

    if sale_date && due_date_days do
      put_change(changeset, :due_date, Date.add(sale_date, due_date_days))
    else
      changeset
    end
  end

  def seller_changeset(sales_invoice, attrs \\ %{}) do
    cast(sales_invoice, attrs, [
      :seller_nip,
      :seller_display_name,
      :seller_address,
      :seller_name,
      :seller_surname,
      :seller_account_number
    ])
  end

  def buyer_changeset(sales_invoice, attrs \\ %{}) do
    sales_invoice
    |> cast(attrs, [
      :buyer_type,
      :buyer_id,
      :buyer_full_name,
      :buyer_given_name,
      :buyer_surname,
      :buyer_pesel,
      :buyer_address,
      :buyer_country,
      :buyer_is_different_mail_address,
      :buyer_mail_address,
      :buyer_mail_country,
      :buyer_email,
      :buyer_phone,
      :buyer_description,
      :buyer_display_name
    ])
    |> validate_country_code(:buyer_country)
    |> validate_buyer_id()
    |> cast_buyer_based_on_type()
  end

  defp validate_country_code(changeset, field) do
    changeset
    |> update_change(field, &CountryCodes.normalize/1)
    |> validate_change(field, fn ^field, value ->
      if CountryCodes.valid_country?(value) do
        []
      else
        [{field, "musi być prawidłowym kodem ISO kraju"}]
      end
    end)
  end

  def cast_buyer_based_on_type(buyer) do
    case get_change(buyer, :buyer_type) do
      :individual ->
        # Clear company-specific fields for individuals
        buyer
        |> put_change(:buyer_id, "")
        |> put_change(:buyer_full_name, nil)

      :company ->
        # Clear individual-specific fields for companies
        buyer
        |> put_change(:buyer_pesel, nil)
        |> put_change(:buyer_given_name, nil)
        |> put_change(:buyer_surname, nil)

      nil ->
        buyer
    end
  end

  # Validates that the correct name fields are present based on buyer_type
  defp validate_buyer_name_fields(changeset) do
    buyer_type = get_field(changeset, :buyer_type)

    case buyer_type do
      :company ->
        validate_required(changeset, [:buyer_full_name], message: "nazwa firmy jest wymagana")

      :individual ->
        changeset
        |> validate_required([:buyer_given_name], message: "imię jest wymagane")
        |> validate_required([:buyer_surname], message: "nazwisko jest wymagane")

      _ ->
        changeset
    end
  end

  defp validate_buyer_id(changeset) do
    # Validate format based on buyer type, but don't require buyer_id here.
    # Required validation happens in validate_buyer_id_required_for_ksef/1 for KSeF submission.
    case buyer_id_type(changeset) do
      :nip ->
        validate_format(changeset, :buyer_id, ~r/^(\d{10})?$/, message: "musi być 10-cyfrowym numerem NIP")

      :optional_id ->
        # US: tax ID is optional, validate length only if provided
        validate_length(changeset, :buyer_id, max: 50, message: "musi mieć maksymalnie 50 znaków")

      _ ->
        validate_length(changeset, :buyer_id, max: 50, message: "musi mieć maksymalnie 50 znaków")
    end
  end

  # Validates that buyer_id is present when required for KSeF submission.
  # This is used in step1_changeset to catch missing IDs early in the Creator flow.
  # Individuals with PESEL (:no_id) don't need a tax ID.
  # US buyers (:optional_id) have optional tax ID (KSeF supports BrakID for them).
  defp validate_buyer_id_required_for_ksef(changeset) do
    case buyer_id_type(changeset) do
      :no_id ->
        # Individual with PESEL - no tax ID required
        changeset

      :optional_id ->
        # US: tax ID is optional - KSeF supports BrakID for non-EU buyers
        changeset

      _other ->
        # Companies and foreign buyers need an ID for KSeF
        validate_required(changeset, [:buyer_id])
    end
  end

  def cast_based_on_type(sales_invoice) do
    case get_change(sales_invoice, :invoice_type) do
      :poland ->
        sales_invoice
        |> put_change(:currency, "PLN")
        |> put_change(:is_reverse_charge, false)

      :foreign ->
        put_change(sales_invoice, :is_cash_account, false)

      nil ->
        sales_invoice
    end
  end

  @doc """
  Changeset for updating only KSeF-specific fields.
  This bypasses the lock check since it's used to update KSeF tracking data.
  """
  def ksef_update_changeset(sales_invoice, attrs) do
    cast(sales_invoice, attrs, [:ksef_number, :ksef_session_reference_number, :locked_at])
  end

  @doc """
  Validates that all fields required for KSeF submission are present and valid.

  This is a read-only validation changeset - it doesn't modify the invoice,
  only checks if it meets KSeF requirements. Use this before submitting to KSeF
  to catch validation errors early (before they reach the KSeF API).

  Required fields for KSeF FA(3):
  - Seller: nip, display_name or (name + surname), address
  - Buyer: country (always required for Adres block), address
  - Buyer identification: depends on buyer_id_type
  - Invoice: invoice_number, issue_date, currency, payment_method

  Returns a changeset with errors if validation fails.
  """
  @spec ksef_submission_changeset(t()) :: Ecto.Changeset.t()
  def ksef_submission_changeset(%__MODULE__{} = sales_invoice) do
    sales_invoice
    |> change()
    |> validate_required([
      # Seller fields
      :seller_nip,
      :seller_address,
      # Buyer fields - country is ALWAYS required when buyer_address is present
      :buyer_country,
      :buyer_address,
      # Invoice fields
      :invoice_number,
      :issue_date,
      :currency,
      :payment_method
    ])
    |> validate_seller_name()
    |> validate_buyer_identification()
    |> validate_country_code(:buyer_country)
  end

  defp validate_seller_name(changeset) do
    seller_display_name = get_field(changeset, :seller_display_name)
    seller_name = get_field(changeset, :seller_name)
    seller_surname = get_field(changeset, :seller_surname)

    has_display_name = is_binary(seller_display_name) and seller_display_name != ""
    has_full_name = is_binary(seller_name) and is_binary(seller_surname)

    if has_display_name or has_full_name do
      changeset
    else
      add_error(changeset, :seller_display_name, "lub imię i nazwisko sprzedawcy jest wymagane")
    end
  end

  defp validate_buyer_identification(changeset) do
    case buyer_id_type(changeset) do
      :no_id ->
        # Individual with PESEL - no tax ID required
        changeset

      :optional_id ->
        # US: tax ID is optional - KSeF supports BrakID for non-EU buyers
        changeset

      :nip ->
        changeset
        |> validate_required([:buyer_id], message: "NIP nabywcy jest wymagany dla polskich firm")
        |> validate_format(:buyer_id, ~r/^\d{10}$/, message: "musi być 10-cyfrowym numerem NIP")

      :eu_vat ->
        validate_required(changeset, [:buyer_id], message: "numer VAT-EU nabywcy jest wymagany")

      :other_id ->
        validate_required(changeset, [:buyer_id], message: "identyfikator nabywcy jest wymagany")
    end
  end

  @doc """
  Changeset for toggling skip_invoicing flag.
  This bypasses the full validation since we only update the skip flag.
  """
  def skip_invoicing_changeset(sales_invoice, attrs) do
    sales_invoice
    |> check_if_locked()
    |> cast(attrs, [:skip_invoicing])
  end

  def locked?(%__MODULE__{locked_at: nil}), do: false
  def locked?(%__MODULE__{locked_at: _}), do: true

  @doc """
  Returns true if the invoice can be deleted.

  An invoice cannot be deleted if:
  - It has been submitted to KSeF (has ksef_number), or
  - It is currently locked for KSeF submission (has locked_at)

  KSeF-submitted invoices can only be "cancelled" by issuing a correction invoice.
  """
  def deletable?(%__MODULE__{ksef_number: nil, locked_at: nil}), do: true
  def deletable?(%__MODULE__{}), do: false

  defp check_if_locked(%__MODULE__{locked_at: nil} = sales_invoice) do
    change(sales_invoice)
  end

  defp check_if_locked(%__MODULE__{locked_at: _locked_at} = sales_invoice) do
    sales_invoice
    |> change()
    |> add_error(:base, "Invoice is locked and cannot be modified")
  end

  @doc """
  Changeset for creating a correction invoice (KOR) based on an original invoice.

  The original invoice must be:
  - Submitted to KSeF (has ksef_number)
  - Locked (has locked_at)

  Seller and buyer data are automatically copied from the original invoice.
  """
  def correction_invoice_changeset(sales_invoice, corrected_invoice, attrs) do
    sales_invoice
    |> changeset(attrs)
    |> put_change(:ksef_invoice_kind, :kor)
    |> put_change(:corrected_invoice_id, corrected_invoice.id)
    |> validate_corrected_invoice(corrected_invoice)
    |> copy_from_corrected_invoice(corrected_invoice)
  end

  defp validate_corrected_invoice(changeset, corrected_invoice) do
    cond do
      is_nil(corrected_invoice) ->
        add_error(changeset, :corrected_invoice_id, "is required for correction invoices")

      is_nil(corrected_invoice.ksef_number) ->
        add_error(changeset, :corrected_invoice_id, "original invoice must be submitted to KSeF first")

      is_nil(corrected_invoice.locked_at) ->
        add_error(changeset, :corrected_invoice_id, "original invoice must be locked")

      true ->
        changeset
    end
  end

  defp copy_from_corrected_invoice(changeset, corrected_invoice) do
    changeset
    |> put_change(:seller_nip, corrected_invoice.seller_nip)
    |> put_change(:seller_display_name, corrected_invoice.seller_display_name)
    |> put_change(:seller_address, corrected_invoice.seller_address)
    |> put_change(:seller_name, corrected_invoice.seller_name)
    |> put_change(:seller_surname, corrected_invoice.seller_surname)
    |> put_change(:seller_account_number, corrected_invoice.seller_account_number)
    |> put_change(:buyer_type, corrected_invoice.buyer_type)
    |> put_change(:buyer_id, corrected_invoice.buyer_id)
    |> put_change(:buyer_full_name, corrected_invoice.buyer_full_name)
    |> put_change(:buyer_given_name, corrected_invoice.buyer_given_name)
    |> put_change(:buyer_surname, corrected_invoice.buyer_surname)
    |> put_change(:buyer_display_name, corrected_invoice.buyer_display_name)
    |> put_change(:buyer_address, corrected_invoice.buyer_address)
    |> put_change(:buyer_country, corrected_invoice.buyer_country)
    |> put_change(:currency, corrected_invoice.currency)
  end

  @doc """
  Returns true if the buyer is from an EU country.
  """
  @spec buyer_from_eu?(t()) :: boolean()
  def buyer_from_eu?(%__MODULE__{buyer_country: country}) when is_binary(country) do
    CountryCodes.eu_country?(country)
  end

  def buyer_from_eu?(_), do: false

  @doc """
  Returns the buyer's region (:eu, :non_eu, or :invalid).
  """
  @spec buyer_region(t()) :: :eu | :non_eu | :invalid
  def buyer_region(%__MODULE__{buyer_country: country}) when is_binary(country) do
    CountryCodes.region(country)
  end

  def buyer_region(_), do: :invalid
end
