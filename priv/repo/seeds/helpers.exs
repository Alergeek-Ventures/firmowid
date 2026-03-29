# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Firmowid.Seeds.Helpers do
  @moduledoc """
  Shared helpers for seed scripts: date utilities, idempotent insert helpers,
  and common data (Bytecraft seller info).
  """

  import Ecto.Query

  alias Firmowid.Blobs
  alias Firmowid.CostInvoices
  alias Firmowid.Finances.BankAccount
  alias Firmowid.Finances.Transaction
  alias Firmowid.Repo
  alias Firmowid.SalesInvoices

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
  # Idempotent insert helpers
  # ---------------------------------------------------------------------------

  def get_or_insert_txn(itid, org_id, attrs) do
    existing =
      Repo.one(
        from(t in Transaction,
          where:
            t.internal_transaction_id == ^itid and
              t.organization_id == ^org_id,
          limit: 1
        )
      )

    case existing do
      nil ->
        now = DateTime.truncate(DateTime.utc_now(), :second)

        Repo.insert!(
          struct!(
            Transaction,
            Map.merge(attrs, %{
              id: Ecto.UUID.generate(),
              internal_transaction_id: itid,
              organization_id: org_id,
              inserted_at: now,
              updated_at: now
            })
          )
        )

      txn ->
        txn
    end
  end

  def get_or_create_sales_invoice(inv_number, org_id, attrs) do
    case Repo.one(
           from(si in SalesInvoices.SalesInvoice,
             where: si.invoice_number == ^inv_number and si.organization_id == ^org_id,
             limit: 1
           )
         ) do
      nil ->
        {:ok, inv} =
          SalesInvoices.create_sales_invoice(
            %SalesInvoices.SalesInvoice{organization_id: org_id},
            Map.merge(bc_seller_info(), Map.put(attrs, "invoice_number", inv_number))
          )

        inv

      inv ->
        inv
    end
  end

  def get_or_create_cost_invoice(invoice_identifier, org_id, attrs) do
    case Repo.one(
           from(ci in CostInvoices.CostInvoice,
             where: ci.invoice_identifier == ^invoice_identifier and ci.organization_id == ^org_id,
             limit: 1
           )
         ) do
      nil ->
        Repo.insert!(
          struct!(
            CostInvoices.CostInvoice,
            Map.merge(attrs, %{
              invoice_identifier: invoice_identifier,
              organization_id: org_id
            })
          )
        )

      ci ->
        ci
    end
  end

  def get_or_create_blob(id, attrs) do
    case Repo.get(Blobs.Blob, id) do
      nil -> Repo.insert!(struct!(Blobs.Blob, Map.put(attrs, :id, id)))
      existing -> existing
    end
  end

  def get_or_create_bank_account(id, attrs) do
    Repo.get(BankAccount, id) ||
      Repo.insert!(struct!(BankAccount, Map.put(attrs, :id, id)))
  end
end
