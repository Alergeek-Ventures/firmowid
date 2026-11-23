defmodule FirmowidWeb.Inbox.Views.IndexTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Scope
  alias Firmowid.Timetracker

  test "an admin without KSeF lands on the inbox, which leads to the KSeF settings", %{conn: conn} do
    admin = admin_fixture()
    conn = log_in_user(conn, admin)

    assert {:error, {:live_redirect, %{to: "/skrzynka"}}} = live(conn, ~p"/fakturowanie")

    {:ok, view, _html} = live(conn, ~p"/skrzynka")
    assert has_element?(view, "#item-ksef-disconnected", "nie wystawisz faktur sprzedażowych")
    assert has_element?(view, ~s(#item-ksef-disconnected a[href="/ustawienia/ksef"]))
  end

  test "a pending leave request leads the admin to the employee's leaves", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{name: "Jan Kowalski"})

    request =
      Timetracker.create_leave_request!(
        %{
          starts_on: Date.add(Date.utc_today(), 10),
          ends_on: Date.add(Date.utc_today(), 12),
          reason: :rest
        },
        scope: %Scope{actor: employee, tenant: employee.member.organization_id}
      )

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/skrzynka")

    assert {:ok, leaves_view, _html} =
             view
             |> element("#item-leave-#{request.id} a")
             |> render_click()
             |> follow_redirect(conn |> recycle() |> log_in_user(admin))

    assert render(leaves_view) =~ "Jan Kowalski"
  end

  test "an overdue cost invoice shows the amount and term after its corrections", %{conn: conn} do
    admin = admin_fixture()
    organization_id = admin.member.organization_id
    today = "Europe/Warsaw" |> DateTime.now!() |> DateTime.to_date()
    days_ago = &Date.add(today, -&1)

    plain = seed_cost_invoice!(organization_id, "FV/A", days_ago.(20), "-100.00")

    # A correction without a payment term leaves the corrected invoice's term in force.
    one = seed_cost_invoice!(organization_id, "FV/B", days_ago.(30), "-2000.00")
    seed_correction!(one, "KOR/B1", days_ago.(10), nil, "500.00")

    # The latest correction that states a term sets it; every correction counts in the amount.
    two = seed_cost_invoice!(organization_id, "FV/C", days_ago.(40), "-1000.00")
    seed_correction!(two, "KOR/C1", days_ago.(35), days_ago.(25), "0.00")
    seed_correction!(two, "KOR/C2", days_ago.(5), nil, "150.00")

    # A correction that moves the term past today takes the invoice off the overdue list.
    moved = seed_cost_invoice!(organization_id, "FV/D", days_ago.(15), "-300.00")
    seed_correction!(moved, "KOR/D1", days_ago.(16), Date.add(today, 10), "0.00")

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/skrzynka")

    assert overdue_item(view, plain) =~ ~r/FV\/A.*#{date(days_ago.(20))}.*100,00/s
    refute overdue_item(view, plain) =~ "KOR"

    assert overdue_item(view, one) =~ ~r/FV\/B.*KOR\/B1.*#{date(days_ago.(30))}.*1\s500,00/su

    assert overdue_item(view, two) =~ ~r/FV\/C.*KOR\/C2.*#{date(days_ago.(25))}.*850,00/s
    refute overdue_item(view, two) =~ "KOR/C1"

    refute has_element?(view, "#item-overdue-cost-#{moved.id}")
  end

  defp overdue_item(view, invoice), do: view |> element("#item-overdue-cost-#{invoice.id}") |> render()

  defp date(date), do: Regex.escape(Calendar.strftime(date, "%d.%m.%Y"))

  defp seed_cost_invoice!(organization_id, number, due_date, amount) do
    Ash.Seed.seed!(CostInvoice, %{
      seller: "Acme Sp. z o.o.",
      seller_display_name: "Acme",
      issue_date: Date.add(due_date, -14),
      sale_date: Date.add(due_date, -14),
      due_date: due_date,
      amount: Money.new!("PLN", amount),
      payment_method: :bank_transfer,
      invoice_type: :vat,
      invoice_identifier: number,
      skip_invoicing: false,
      organization_id: organization_id,
      ksef_number: "KSEF-#{number}-#{System.unique_integer([:positive])}",
      ksef_permanent_storage_date: NaiveDateTime.new!(Date.add(due_date, -14), ~T[12:00:00])
    })
  end

  defp seed_correction!(original, number, issue_date, due_date, amount) do
    Ash.Seed.seed!(CostInvoice, %{
      seller: original.seller,
      seller_display_name: original.seller_display_name,
      issue_date: issue_date,
      sale_date: issue_date,
      due_date: due_date,
      amount: Money.new!("PLN", amount),
      invoice_type: :kor,
      invoice_identifier: number,
      original_invoice_ksef_number: original.ksef_number,
      skip_invoicing: false,
      organization_id: original.organization_id,
      ksef_number: "KSEF-#{number}-#{System.unique_integer([:positive])}",
      ksef_permanent_storage_date: NaiveDateTime.new!(issue_date, ~T[12:00:00])
    })
  end
end
