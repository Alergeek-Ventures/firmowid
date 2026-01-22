defmodule Firmowid.SalesInvoices.SalesInvoice do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  alias Firmowid.SalesInvoices.CountryCodes
  alias Firmowid.SalesInvoices.SalesInvoiceItem

  @type t :: %__MODULE__{}

  schema "sales_invoices" do
    field :invoice_type, Ecto.Enum, values: [:poland, :foreign], default: :poland

    field :invoice_number, :string
    field :sale_date, :date
    field :issue_date, :date
    field :due_date, :date
    field :payment_method, :string
    field :currency, :string
    field :is_basic_info_confirmed, :boolean, default: false

    field :seller_nip, :string
    field :seller_display_name, :string
    field :seller_address, :string
    field :seller_name, :string
    field :seller_surname, :string
    field :seller_account_number, :string
    field :is_seller_confirmed, :boolean, default: false

    field :buyer_type, Ecto.Enum, values: [:individual, :company], default: :company

    field :buyer_id, :string
    field :buyer_display_name, :string
    field :buyer_name, :string
    field :buyer_surname, :string
    field :buyer_pesel, :string

    field :buyer_address, :string
    field :buyer_country, :string

    field :buyer_is_different_mail_address, :boolean, default: false
    field :buyer_mail_address, :string
    field :buyer_mail_country, :string

    field :buyer_email, :string
    field :buyer_phone, :string
    field :buyer_description, :string
    field :is_buyer_confirmed, :boolean, default: false

    field :are_sales_invoice_items_confirmed, :boolean, default: false

    field :is_cash_account, :boolean, default: false
    field :is_reverse_charge, :boolean, default: false

    field :skip_invoicing, :boolean, default: false

    field :logo_url, :string, virtual: true
    field :total_amount, :decimal, virtual: true

    field :item_names, :string

    # KSeF submission tracking
    field :ksef_number, :string
    field :ksef_session_reference_number, :string
    field :locked_at, :utc_datetime

    # KSeF FA(3) fields
    field :ksef_invoice_kind, Ecto.Enum, values: [:vat, :kor], default: :vat

    belongs_to :corrected_invoice, __MODULE__
    has_many :corrections, __MODULE__, foreign_key: :corrected_invoice_id

    has_many :sales_invoice_items, SalesInvoiceItem, on_replace: :delete

    many_to_many :transactions,
                 Firmowid.Finances.Transaction,
                 join_through: "sales_invoices_transactions"

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  def get_net_value(sales_invoice) do
    Enum.reduce(sales_invoice.sales_invoice_items, Decimal.new(0), fn item, acc ->
      Decimal.add(acc, SalesInvoiceItem.get_net_value(item))
    end)
  end

  def get_vat_value(sales_invoice) do
    Enum.reduce(sales_invoice.sales_invoice_items, Decimal.new(0), fn item, acc ->
      Decimal.add(acc, SalesInvoiceItem.get_vat_value(item))
    end)
  end

  def confirmed?(sales_invoice) do
    sales_invoice.is_basic_info_confirmed &&
      sales_invoice.is_seller_confirmed &&
      sales_invoice.is_buyer_confirmed &&
      sales_invoice.are_sales_invoice_items_confirmed
  end

  @spec get_gross_value(%__MODULE__{}) :: Decimal.t()
  def get_gross_value(sales_invoice) do
    Decimal.add(get_net_value(sales_invoice), get_vat_value(sales_invoice))
  end

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

  @spec buyer_id_type(map() | Ecto.Changeset.t()) :: :nip | :eu_vat | :other_id | :no_id
  def buyer_id_type(%{buyer_pesel: buyer_pesel, buyer_country: buyer_country}) do
    cond do
      not is_nil(buyer_pesel) and buyer_pesel != "" -> :no_id
      buyer_country == "PL" -> :nip
      CountryCodes.eu_country?(buyer_country) -> :eu_vat
      true -> :other_id
    end
  end

  def buyer_id_type(%Ecto.Changeset{} = changeset) do
    buyer_pesel = get_field(changeset, :buyer_pesel)
    buyer_country = get_field(changeset, :buyer_country)

    buyer_id_type(%{buyer_pesel: buyer_pesel, buyer_country: buyer_country})
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
      :is_basic_info_confirmed,
      :is_seller_confirmed,
      :is_buyer_confirmed,
      :are_sales_invoice_items_confirmed,
      :is_cash_account,
      :is_reverse_charge,
      :skip_invoicing,
      :ksef_invoice_kind
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
    |> prepare_changes(&ensure_sequential_invoice_number/1)
  end

  defp ensure_sequential_invoice_number(%{changes: %{is_basic_info_confirmed: true}} = changeset) do
    invoice_id = get_field(changeset, :id)
    invoice_number = get_field(changeset, :invoice_number)
    issue_date = get_field(changeset, :issue_date)

    month = String.pad_leading("#{issue_date.month}", 2, "0")
    year = issue_date.year

    expected_invoice_index =
      issue_date
      |> Firmowid.SalesInvoices.get_next_invoice_number(omit_invoice_id: invoice_id)
      |> get_invoice_number_index()

    current_invoice_index = get_invoice_number_index(invoice_number)

    # this allows for inserting outdated invoices
    if current_invoice_index > expected_invoice_index do
      Ecto.Changeset.add_error(
        changeset,
        :invoice_number,
        "Number faktury powinien być mniejszy. Oczekiwano: #{expected_invoice_index}/#{month}/#{year}"
      )
    else
      changeset
    end
  end

  defp ensure_sequential_invoice_number(changeset), do: changeset

  defp get_invoice_number_index(invoice_number) do
    invoice_number
    |> String.split("/")
    |> List.first()
    |> String.to_integer()
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
      :buyer_display_name,
      :buyer_name,
      :buyer_surname,
      :buyer_pesel,
      :buyer_address,
      :buyer_country,
      :buyer_is_different_mail_address,
      :buyer_mail_address,
      :buyer_mail_country,
      :buyer_email,
      :buyer_phone,
      :buyer_description
    ])
    |> validate_length(:buyer_country, is: 2)
    |> validate_format(:buyer_country, ~r/^[A-Z]{2}$/)
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
        buyer
        |> put_change(:buyer_id, "")
        |> put_change(:buyer_display_name, "")

      :company ->
        put_change(buyer, :buyer_pesel, nil)

      nil ->
        buyer
    end
  end

  defp validate_buyer_id(changeset) do
    buyer_confirmed? = get_field(changeset, :is_buyer_confirmed) == true

    changeset = if buyer_confirmed?, do: validate_required(changeset, [:buyer_id]), else: changeset

    case buyer_id_type(changeset) do
      :nip ->
        validate_format(changeset, :buyer_id, ~r/^(\d{10})?$/, message: "musi być 10-cyfrowym numerem NIP")

      _ ->
        validate_length(changeset, :buyer_id, max: 50, message: "musi mieć maksymalnie 50 znaków")
    end
  end

  def cast_based_on_type(sales_invoice) do
    case get_change(sales_invoice, :invoice_type) do
      :poland ->
        sales_invoice
        |> put_change(:currency, "PLN")
        |> put_change(:is_reverse_charge, false)
        |> put_change(:is_basic_info_confirmed, false)

      :foreign ->
        sales_invoice
        |> put_change(:is_cash_account, false)
        |> put_change(:is_basic_info_confirmed, false)

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
    |> put_change(:buyer_display_name, corrected_invoice.buyer_display_name)
    |> put_change(:buyer_name, corrected_invoice.buyer_name)
    |> put_change(:buyer_surname, corrected_invoice.buyer_surname)
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
