defmodule FirmowidWeb.Inbox.Utilities.QueueTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.InvoicingFixtures

  alias Firmowid.Scope
  alias FirmowidWeb.Inbox.Utilities.Queue

  test "the month shows the income of the whole month, like the analysis" do
    admin = admin_fixture()
    scope = Scope.new!(admin, admin.member.organization_id)

    seed_sales_invoice!(
      %{
        invoice_number: "FV/1/11/2026",
        buyer_full_name: "Buyer",
        buyer_display_name: "Buyer",
        seller_display_name: "Our Company",
        sale_date: ~D[2026-11-20],
        issue_date: ~D[2026-11-20],
        due_date: ~D[2026-11-20],
        payment_method: :transfer,
        currency: "PLN",
        buyer_type: :company,
        skip_invoicing: true,
        sales_invoice_items: [
          %{name: "Service", quantity: 1, unit: "pcs", unit_price: Decimal.new("1000.00")}
        ]
      },
      scope: scope
    )

    analysis_month =
      Firmowid.Analysis.get_organization_totals(~D[2026-11-01], ~D[2026-11-30], [], scope)

    assert [%{side: :sales, value: income}, %{side: :cost}] = Queue.month(scope, ~D[2026-11-10])
    refute Decimal.equal?(analysis_month.total_income, 0)

    assert income ==
             Money.to_string!(Money.new(:PLN, analysis_month.total_income),
               fractional_digits: 0,
               minimum_grouping_digits: 1
             )
  end
end
