# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.Helpers do
  @moduledoc """
  Shared helpers for seed scripts: date utilities, idempotent insert helpers,
  and common data (Bytecraft seller info).

  Finance-related helpers use `Ash.Seed` which bypasses actions/validations
  and writes directly to the data layer — ideal for deterministic seed data.
  """

  import Ecto.Query

  alias Firmowid.Ash.Blobs.Blob, as: AshBlob
  alias Firmowid.Ash.Finances.BankAccount, as: AshBankAccount
  alias Firmowid.Ash.Finances.Requisition, as: AshRequisition
  alias Firmowid.Ash.Finances.Transaction, as: AshTransaction
  alias Firmowid.Ash.Invoicing.CostInvoice, as: AshCostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice, as: AshSalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem, as: AshSalesInvoiceItem
  alias Firmowid.Repo

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
    case Ash.get(AshRequisition, id, tenant: org_id, authorize?: false, actor: %{}) do
      {:ok, existing} ->
        existing

      _ ->
        Ash.create!(AshRequisition, %{id: id},
          action: :persist,
          tenant: org_id,
          authorize?: false,
          actor: %{}
        )
    end
  end

  def seed_bank_account!(attrs, org_id) do
    Ash.Seed.upsert!(AshBankAccount, Map.put(attrs, :organization_id, org_id),
      identity: :unique_iban_per_org,
      tenant: org_id
    )
  end

  def seed_transaction!(attrs, org_id) do
    Ash.Seed.upsert!(AshTransaction, Map.put(attrs, :organization_id, org_id),
      identity: :unique_internal_tx_per_org,
      tenant: org_id
    )
  end

  # ---------------------------------------------------------------------------
  # Invoice seed helpers — Ash.Seed (bypasses actions, goes to data layer)
  # ---------------------------------------------------------------------------

  def get_or_create_sales_invoice(inv_number, org_id, attrs) do
    case Repo.one(
           from(si in AshSalesInvoice,
             where: si.invoice_number == ^inv_number and si.organization_id == ^org_id,
             limit: 1
           )
         ) do
      nil ->
        seed_sales_invoice!(inv_number, org_id, attrs)

      inv ->
        inv
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
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
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
    case Repo.one(
           from(ci in AshCostInvoice,
             where: ci.invoice_identifier == ^invoice_identifier and ci.organization_id == ^org_id,
             limit: 1
           )
         ) do
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

      ci ->
        ci
    end
  end

  def seed_blob!(attrs, org_id) do
    Ash.Seed.upsert!(AshBlob, Map.put(attrs, :organization_id, org_id),
      identity: :unique_checksum_per_org,
      tenant: org_id
    )
  end
end
