defmodule Firmowid.Ash.Invoicing.Services.RecentMatchedEntriesTest do
  @moduledoc """
  Regression tests for the invoicing dashboard's matched-entry read model.
  """

  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoiceItem
  alias Firmowid.Ash.Invoicing.Services.RecentMatchedEntries
  alias Firmowid.Ash.Scope

  test "returns the root invoice when a correction is matched" do
    user = admin_fixture()
    scope = %Scope{actor: user, tenant: user.organization_id}
    today = Date.utc_today()

    root =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: "FV/ROOT/#{System.unique_integer([:positive])}",
        buyer_full_name: "Dashboard Buyer",
        seller_display_name: "Our Company",
        sale_date: today,
        issue_date: today,
        due_date: Date.add(today, 14),
        payment_method: :transfer,
        currency: "PLN",
        buyer_type: :company,
        organization_id: user.organization_id,
        ksef_invoice_kind: :vat
      })

    correction =
      Ash.Seed.seed!(SalesInvoice, %{
        invoice_number: "KOR/#{System.unique_integer([:positive])}",
        buyer_full_name: "Dashboard Buyer",
        seller_display_name: "Our Company",
        sale_date: today,
        issue_date: today,
        due_date: Date.add(today, 14),
        payment_method: :transfer,
        currency: "PLN",
        buyer_type: :company,
        organization_id: user.organization_id,
        ksef_invoice_kind: :kor,
        corrected_invoice_id: root.id
      })

    Ash.Seed.seed!(SalesInvoiceItem, %{
      sales_invoice_id: correction.id,
      organization_id: user.organization_id,
      index: 0,
      name: "Corrected service",
      quantity: Decimal.new("1"),
      unit: "szt.",
      unit_price: Decimal.new("100"),
      vat_rate: "23"
    })

    bank_account = bank_account_fixture!(user)

    transaction =
      Ash.Seed.seed!(Transaction, %{
        transaction_id: "TX-ROOT-CORRECTION-#{System.unique_integer([:positive])}",
        internal_transaction_id: "INT-TX-ROOT-CORRECTION-#{System.unique_integer([:positive])}",
        creditor_name: "Dashboard Buyer",
        creditor_account: "ACC123",
        debtor_name: "Our Company",
        debtor_account: "ACC456",
        amount: Money.new!("PLN", Decimal.new("100")),
        booking_date: today,
        value_date: today,
        remittance_information_unstructured: "Correction payment",
        bank_account_id: bank_account.id,
        organization_id: user.organization_id
      })

    Invoicing.connect_sales_invoice_transactions!(correction, [transaction.id], scope: scope)

    result = RecentMatchedEntries.list(today, today, scope)

    assert result.total_count == 1
    assert [%{entry: %SalesInvoice{id: root_id}}] = result.entries
    assert root_id == root.id
  end
end
