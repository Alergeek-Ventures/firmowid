# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.Helpers do
  @moduledoc """
  Shared helpers for seed scripts: date utilities, idempotent insert helpers,
  and common data (Bytecraft seller info).

  Finance-related helpers use `Ash.Seed` which bypasses actions/validations
  and writes directly to the data layer — ideal for deterministic seed data.
  """

  alias Firmowid.Ash.Blobs.Blob, as: AshBlob
  alias Firmowid.Ash.Finances.BankAccount, as: AshBankAccount
  alias Firmowid.Ash.Finances.Requisition, as: AshRequisition
  alias Firmowid.Ash.Finances.Transaction, as: AshTransaction
  alias Firmowid.Ash.Invoicing.CostInvoice, as: AshCostInvoice
  alias Firmowid.Ash.Invoicing.CostInvoiceTransaction, as: AshCostInvoiceTransaction
  alias Firmowid.Ash.Invoicing.SalesInvoice, as: AshSalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem, as: AshSalesInvoiceItem
  alias Firmowid.Ash.Invoicing.SalesInvoiceTransaction, as: AshSalesInvoiceTransaction
  alias Firmowid.S3Client

  require Ash.Query

  @seed_actor %{id: "00000000-0000-0000-0000-000000000000", role: :admin}

  @string_key_to_atom %{
    "invoice_type" => :invoice_type,
    "issue_date" => :issue_date,
    "sale_date" => :sale_date,
    "due_date" => :due_date,
    "currency" => :currency,
    "buyer_display_name" => :buyer_display_name,
    "buyer_full_name" => :buyer_full_name,
    "buyer_address" => :buyer_address,
    "buyer_country" => :buyer_country,
    "buyer_id" => :buyer_id,
    "buyer_type" => :buyer_type,
    "payment_method" => :payment_method,
    "is_reverse_charge" => :is_reverse_charge,
    "is_cash_account" => :is_cash_account,
    "counterparty_id" => :counterparty_id,
    "invoice_number" => :invoice_number,
    "seller_display_name" => :seller_display_name,
    "seller_address" => :seller_address,
    "seller_nip" => :seller_nip,
    "seller_account_number" => :seller_account_number,
    "name" => :name,
    "quantity" => :quantity,
    "unit" => :unit,
    "unit_price" => :unit_price,
    "vat_rate" => :vat_rate
  }

  # A minimal valid single-page blank PDF used as placeholder content for seed blobs.
  # Each xref entry must be exactly 20 bytes (including the trailing \r\n).
  @minimal_pdf IO.iodata_to_binary([
                 "%PDF-1.4\n",
                 "1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n",
                 "2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n",
                 "3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<<>>>>endobj\n",
                 "xref\n0 4\n",
                 "0000000000 65535 f \r\n",
                 "0000000009 00000 n \r\n",
                 "0000000058 00000 n \r\n",
                 "0000000115 00000 n \r\n",
                 "trailer<</Size 4/Root 1 0 R>>\n",
                 "startxref\n206\n",
                 "%%EOF\n"
               ])

  # ---------------------------------------------------------------------------
  # Date helpers — all seed dates are relative to today so the dashboard
  # always shows data in the current month and the two preceding months.
  # ---------------------------------------------------------------------------

  def today, do: Date.utc_today()

  def date_this_month(day) do
    t = today()
    Date.new!(t.year, t.month, min(day, Date.days_in_month(t)))
  end

  def months_ago(months) do
    Date.shift(today(), month: -months)
  end

  def date_months_ago(months, day) do
    ref = months_ago(months)
    Date.new!(ref.year, ref.month, min(day, Date.days_in_month(ref)))
  end

  def month_prefix(months_back) do
    d = if months_back == 0, do: today(), else: months_ago(months_back)
    "#{String.pad_leading("#{d.month}", 2, "0")}/#{d.year}"
  end

  # ---------------------------------------------------------------------------
  # Bytecraft seller info — shared across all sales invoices
  # ---------------------------------------------------------------------------

  def bc_seller_info do
    %{
      "seller_display_name" => "Bytecraft Collective sp. z o.o.",
      "seller_address" => "ul. Marszałkowska 11/4, 00-624 Warszawa",
      "seller_nip" => "6161525811",
      "seller_account_number" => "PL61105000997603123456789012"
    }
  end

  # ---------------------------------------------------------------------------
  # Finance seed helpers — Ash.Seed (bypasses actions, goes to data layer)
  # ---------------------------------------------------------------------------

  def seed_requisition!(id, org_id) do
    Ash.Seed.upsert!(
      AshRequisition,
      %{id: id, organization_id: org_id},
      identity: :unique_id,
      tenant: org_id
    )
  end

  def seed_bank_account!(attrs, org_id) do
    Ash.Seed.upsert!(AshBankAccount, Map.put(attrs, :organization_id, org_id),
      identity: :unique_iban_per_org,
      tenant: org_id
    )
  end

  def seed_transaction!(attrs, org_id) do
    Ash.Seed.upsert!(
      AshTransaction,
      attrs
      |> normalize_transaction_dates()
      |> normalize_transaction_money()
      |> Map.put(:organization_id, org_id),
      identity: :unique_internal_tx_per_account,
      tenant: org_id
    )
  end

  def money!(currency, amount), do: Money.new!(currency, normalize_decimal(amount))

  defp normalize_transaction_dates(attrs) do
    booking_date = Map.get(attrs, :booking_date)
    value_date = Map.get(attrs, :value_date)

    attrs
    |> maybe_put_date(:booking_date, booking_date || value_date)
    |> maybe_put_date(:value_date, value_date || booking_date)
  end

  defp maybe_put_date(attrs, _field, nil), do: attrs

  defp maybe_put_date(attrs, field, value) do
    case Map.get(attrs, field) do
      nil -> Map.put(attrs, field, value)
      _present -> attrs
    end
  end

  defp normalize_transaction_money(attrs) do
    case Map.get(attrs, :amount) do
      %Money{} -> attrs
      {currency, amount} -> Map.put(attrs, :amount, money!(currency, amount))
      %{currency: currency, amount: amount} -> Map.put(attrs, :amount, money!(currency, amount))
      nil -> attrs
      _ -> attrs
    end
  end

  defp normalize_decimal(%Decimal{} = value), do: value
  defp normalize_decimal(value) when is_integer(value), do: Decimal.new(value)
  defp normalize_decimal(value) when is_float(value), do: Decimal.from_float(value)
  defp normalize_decimal(value) when is_binary(value), do: Decimal.new(value)
  defp normalize_decimal(_), do: nil

  # ---------------------------------------------------------------------------
  # Invoice seed helpers — Ash.Seed (bypasses actions, goes to data layer)
  # ---------------------------------------------------------------------------

  def get_or_create_sales_invoice(inv_number, org_id, attrs) do
    case find_sales_invoice(inv_number, org_id) do
      nil -> seed_sales_invoice!(inv_number, org_id, attrs)
      invoice -> invoice
    end
  end

  defp seed_sales_invoice!(inv_number, org_id, attrs) do
    {items_raw, invoice_attrs} = Map.pop(attrs, "sales_invoice_items", [])

    invoice_data =
      bc_seller_info()
      |> Map.merge(invoice_attrs)
      |> Map.put("invoice_number", inv_number)
      |> atomize_string_keys()
      |> Map.put(:organization_id, org_id)
      |> Map.put(:ksef_invoice_kind, :vat)

    invoice = Ash.Seed.seed!(AshSalesInvoice, invoice_data, tenant: org_id)

    Enum.with_index(items_raw, fn item_raw, index ->
      item_data =
        item_raw
        |> atomize_string_keys()
        |> Map.merge(%{
          sales_invoice_id: invoice.id,
          organization_id: org_id,
          index: index
        })
        |> ensure_decimal_fields([:quantity, :unit_price])

      Ash.Seed.seed!(AshSalesInvoiceItem, item_data, tenant: org_id)
    end)

    invoice
  end

  defp atomize_string_keys(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {Map.get(@string_key_to_atom, key, key), value}
      {key, value} -> {key, value}
    end)
  end

  defp ensure_decimal_fields(map, fields) do
    Enum.reduce(fields, map, fn field, acc ->
      case Map.get(acc, field) do
        %Decimal{} -> acc
        value when is_number(value) -> Map.put(acc, field, Decimal.new("#{value}"))
        value when is_binary(value) -> Map.put(acc, field, Decimal.new(value))
        _ -> acc
      end
    end)
  end

  def get_or_create_cost_invoice(invoice_identifier, org_id, attrs) do
    case find_cost_invoice(invoice_identifier, org_id) do
      nil ->
        checksum = :sha256 |> :crypto.hash("cost-invoice:#{invoice_identifier}:#{org_id}") |> Base.encode16(case: :lower)
        filename = "#{String.replace(invoice_identifier, "/", "-")}.pdf"

        blob =
          seed_blob!(
            %{
              blob_path: "seeds/cost-invoices/#{filename}",
              blob_checksum: checksum,
              original_filename: filename
            },
            org_id
          )

        Ash.Seed.seed!(
          AshCostInvoice,
          Map.merge(attrs, %{
            invoice_identifier: invoice_identifier,
            organization_id: org_id,
            blob_id: blob.id
          }),
          tenant: org_id
        )

      invoice ->
        invoice
    end
  end

  defp find_sales_invoice(inv_number, org_id) do
    query =
      AshSalesInvoice
      |> Ash.Query.filter(invoice_number == ^inv_number and organization_id == ^org_id)
      |> Ash.Query.limit(1)

    case Ash.read(query, tenant: org_id, actor: @seed_actor) do
      {:ok, [invoice | _]} -> invoice
      _ -> nil
    end
  end

  defp find_cost_invoice(invoice_identifier, org_id) do
    query =
      AshCostInvoice
      |> Ash.Query.filter(invoice_identifier == ^invoice_identifier and organization_id == ^org_id)
      |> Ash.Query.limit(1)

    case Ash.read(query, tenant: org_id, actor: @seed_actor) do
      {:ok, [invoice | _]} -> invoice
      _ -> nil
    end
  end

  def seed_blob!(attrs, org_id) do
    blob =
      Ash.Seed.upsert!(AshBlob, Map.put(attrs, :organization_id, org_id),
        identity: :unique_checksum_per_org,
        tenant: org_id
      )

    upload_seed_blob_to_s3!(blob.blob_path)

    blob
  end

  def connect_sales_invoice_transaction!(sales_invoice_id, transaction_id, org_id) do
    if !sales_invoice_transaction_exists?(sales_invoice_id, transaction_id, org_id) do
      Ash.Seed.seed!(
        AshSalesInvoiceTransaction,
        %{
          sales_invoice_id: sales_invoice_id,
          transaction_id: transaction_id,
          organization_id: org_id
        },
        tenant: org_id
      )
    end

    :ok
  end

  def connect_cost_invoice_transaction!(cost_invoice_id, transaction_id, org_id) do
    if !cost_invoice_transaction_exists?(cost_invoice_id, transaction_id, org_id) do
      Ash.Seed.seed!(
        AshCostInvoiceTransaction,
        %{
          cost_invoice_id: cost_invoice_id,
          transaction_id: transaction_id,
          organization_id: org_id
        },
        tenant: org_id
      )
    end

    :ok
  end

  defp sales_invoice_transaction_exists?(sales_invoice_id, transaction_id, org_id) do
    query =
      AshSalesInvoiceTransaction
      |> Ash.Query.filter(
        sales_invoice_id == ^sales_invoice_id and
          transaction_id == ^transaction_id and
          organization_id == ^org_id
      )
      |> Ash.Query.limit(1)

    case Ash.read(query, tenant: org_id, actor: @seed_actor) do
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end

  defp cost_invoice_transaction_exists?(cost_invoice_id, transaction_id, org_id) do
    query =
      AshCostInvoiceTransaction
      |> Ash.Query.filter(
        cost_invoice_id == ^cost_invoice_id and
          transaction_id == ^transaction_id and
          organization_id == ^org_id
      )
      |> Ash.Query.limit(1)

    case Ash.read(query, tenant: org_id, actor: @seed_actor) do
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end

  defp upload_seed_blob_to_s3!(blob_path) do
    S3Client.upload_binary!(@minimal_pdf, blob_path, content_type: "application/pdf")
  end
end
