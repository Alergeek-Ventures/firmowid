defmodule Firmowid.SalesInvoices.SalesInvoice do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  alias Firmowid.Ksef.VatRate
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

    # todo: rename to buyer_tax_id
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

    field :share_token, :string

    # KSeF submission tracking
    field :ksef_number, :string
    field :ksef_session_reference_number, :string
    field :locked_at, :utc_datetime

    # KSeF FA(3) fields
    field :ksef_invoice_kind, Ecto.Enum, values: [:vat, :kor], default: :vat
    field :correction_reason, :string

    belongs_to :corrected_invoice, __MODULE__

    has_many :corrections, __MODULE__,
      foreign_key: :corrected_invoice_id,
      preload_order: [asc_nulls_last: :locked_at, asc: :inserted_at]

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

  # rename to buyer_tax_id_type
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
      :correction_reason,
      :counterparty_id
    ])
    |> validate_length(:correction_reason, max: 256)
    |> buyer_changeset(attrs)
    |> seller_changeset(attrs)
    |> cast_assoc(:sales_invoice_items,
      with: &SalesInvoiceItem.changeset/3,
      sort_param: :items_sort,
      drop_param: :items_drop
    )
    |> normalize_reverse_charge_item_vat_rate()
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
      with: &SalesInvoiceItem.changeset/3,
      required: true,
      sort_param: :items_sort,
      drop_param: :items_drop
    )
    |> normalize_reverse_charge_item_vat_rate()
    |> validate_required([:currency])
    |> validate_format(:currency, ~r/^[A-Z]{3}$/)
  end

  defp normalize_reverse_charge_item_vat_rate(changeset) do
    is_reverse_charge = get_field(changeset, :is_reverse_charge)
    target_rate = if is_reverse_charge, do: "oo", else: fallback_vat_rate_for_non_reverse_charge(changeset)

    case fetch_change(changeset, :sales_invoice_items) do
      {:ok, changed_items} ->
        {normalized_items, _changed?} =
          normalize_item_changesets(changed_items, is_reverse_charge, target_rate)

        changeset = %{changeset | changes: Map.put(changeset.changes, :sales_invoice_items, normalized_items)}

        %{
          changeset
          | params: update_items_in_params(changeset.params, &normalize_item_params(&1, is_reverse_charge, target_rate))
        }

      :error ->
        item_changesets = get_assoc(changeset, :sales_invoice_items, :changeset)

        {normalized_items, changed?} =
          normalize_item_changesets(item_changesets, is_reverse_charge, target_rate)

        changeset =
          if changed? do
            %{changeset | changes: Map.put(changeset.changes, :sales_invoice_items, normalized_items)}
          else
            changeset
          end

        %{
          changeset
          | params: update_items_in_params(changeset.params, &normalize_item_params(&1, is_reverse_charge, target_rate))
        }
    end
  end

  defp fallback_vat_rate_for_non_reverse_charge(changeset) do
    buyer_country = get_field(changeset, :buyer_country)
    buyer_id_type = buyer_id_type(changeset)

    case VatRate.available_rates(buyer_country, buyer_id_type) do
      {:fixed, rate} -> rate
      {:select, _rates, default_rate} -> default_rate
    end
  end

  defp normalize_item_changesets(item_changesets, is_reverse_charge, target_rate) do
    Enum.map_reduce(item_changesets, false, fn item_changeset, changed? ->
      {normalized_item, item_changed?} =
        normalize_item_changeset(item_changeset, is_reverse_charge, target_rate)

      {normalized_item, changed? or item_changed?}
    end)
  end

  defp normalize_item_changeset(item_changeset, is_reverse_charge, target_rate) do
    current_rate = get_field(item_changeset, :vat_rate)
    normalized_rate = normalize_rate(current_rate, is_reverse_charge, target_rate)

    if normalized_rate == current_rate do
      {item_changeset, false}
    else
      updated =
        item_changeset
        |> put_change(:vat_rate, normalized_rate)
        |> case do
          %Ecto.Changeset{action: nil} = changeset -> %{changeset | action: :update}
          changeset -> changeset
        end

      {updated, true}
    end
  end

  defp update_items_in_params(nil, _normalizer), do: nil

  defp update_items_in_params(%{"sales_invoice_items" => _} = params, normalizer) do
    Map.update!(params, "sales_invoice_items", &normalize_items_container(&1, normalizer))
  end

  defp update_items_in_params(params, _normalizer), do: params

  defp normalize_items_container(items, normalizer) when is_map(items) do
    Map.new(items, fn {key, item_params} -> {key, normalizer.(item_params)} end)
  end

  defp normalize_items_container(items, normalizer) when is_list(items) do
    Enum.map(items, normalizer)
  end

  defp normalize_items_container(items, _normalizer), do: items

  defp normalize_item_params(item_params, is_reverse_charge, target_rate) when is_map(item_params) do
    cond do
      Map.has_key?(item_params, "vat_rate") ->
        current_rate = Map.get(item_params, "vat_rate")
        Map.put(item_params, "vat_rate", normalize_rate(current_rate, is_reverse_charge, target_rate))

      Map.has_key?(item_params, :vat_rate) ->
        current_rate = Map.get(item_params, :vat_rate)
        Map.put(item_params, :vat_rate, normalize_rate(current_rate, is_reverse_charge, target_rate))

      true ->
        item_params
    end
  end

  defp normalize_item_params(item_params, _is_reverse_charge, _target_rate), do: item_params

  defp normalize_rate(_current_rate, true, target_rate), do: target_rate
  defp normalize_rate("oo", false, target_rate), do: target_rate
  defp normalize_rate(current_rate, false, _target_rate), do: current_rate

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

  def prepare_correction_invoice_changeset(original_invoice, reference_invoice) do
    base_attrs =
      reference_invoice
      |> Map.take([
        :seller_nip,
        :seller_display_name,
        :seller_address,
        :seller_name,
        :seller_surname,
        :seller_account_number,
        :counterparty_id,
        :buyer_type,
        :buyer_id,
        :buyer_full_name,
        :buyer_given_name,
        :buyer_surname,
        :buyer_display_name,
        :buyer_address,
        :buyer_country,
        :buyer_is_different_mail_address,
        :buyer_mail_address,
        :buyer_mail_country,
        :buyer_email,
        :buyer_phone,
        :buyer_description,
        :buyer_pesel,
        :invoice_type,
        :sale_date,
        :due_date,
        :payment_method,
        :currency,
        :is_reverse_charge,
        :is_cash_account
      ])
      |> Map.put(:organization_id, original_invoice.organization_id)
      |> Map.put(:ksef_invoice_kind, :kor)
      |> Map.put(:corrected_invoice_id, original_invoice.id)
      |> maybe_put_due_date_days(reference_invoice)

    items =
      Enum.map(
        reference_invoice.sales_invoice_items,
        &Map.take(&1, [:index, :name, :quantity, :unit, :unit_price, :vat_rate])
      )

    %__MODULE__{}
    |> change(base_attrs)
    |> put_assoc(:sales_invoice_items, items)
  end

  defp maybe_put_due_date_days(attrs, %{sale_date: sale_date, due_date: due_date})
       when not is_nil(sale_date) and not is_nil(due_date) do
    Map.put(attrs, :due_date_days, Date.diff(due_date, sale_date))
  end

  defp maybe_put_due_date_days(attrs, _reference), do: attrs

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
  This bypasses full validation and lock checks since we only update the skip flag.
  """
  def skip_invoicing_changeset(sales_invoice, attrs) do
    cast(sales_invoice, attrs, [:skip_invoicing])
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

  @doc """
  Returns true if the invoice can be edited (navigated to the edit page).

  An invoice is NOT editable if:
  - It is a VAT invoice that already has correction invoices (corrections must
    be made from the latest correction instead).
  - It is a KOR invoice that is not the latest correction of its parent
    (only the latest snapshot can be edited).

  Draft invoices and confirmed-but-not-locked invoices are always editable.

  Requires the `corrections` association to be preloaded for VAT invoices.
  For KOR invoices, requires `corrected_invoice` with its `corrections` preloaded.
  """
  @spec editable?(t()) :: boolean()
  def editable?(%__MODULE__{ksef_invoice_kind: :kor} = invoice) do
    latest_correction = List.last(invoice.corrected_invoice.corrections)

    latest_correction != nil and latest_correction.id == invoice.id
  end

  def editable?(%__MODULE__{ksef_invoice_kind: :vat, corrections: corrections}) do
    Enum.empty?(corrections)
  end

  def editable?(%__MODULE__{invoice_number: nil}), do: true
  def editable?(%__MODULE__{locked_at: nil}), do: true
  def editable?(%__MODULE__{}), do: false

  defp check_if_locked(%__MODULE__{locked_at: nil} = sales_invoice) do
    change(sales_invoice)
  end

  defp check_if_locked(%__MODULE__{locked_at: _locked_at} = sales_invoice) do
    sales_invoice
    |> change()
    |> add_error(:base, "Invoice is locked and cannot be modified")
  end

  defp check_if_locked(%Ecto.Changeset{data: %__MODULE__{}} = changeset) do
    case get_field(changeset, :locked_at) do
      nil -> changeset
      _locked_at -> add_error(changeset, :base, "Invoice is locked and cannot be modified")
    end
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
