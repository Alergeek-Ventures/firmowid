# credo:disable-for-this-file ExDNA.Credo
defmodule FirmowidWeb.Invoicing.Transactions.Views.ShowTest do
  @moduledoc false
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Blobs.Blob
  alias Firmowid.Finances
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.CostInvoiceTransaction
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Invoicing.SalesInvoiceItem
  alias Firmowid.Payroll.UserEmploymentContract
  alias Firmowid.Payroll.UserSalary
  alias Firmowid.Scope
  alias Firmowid.Timetracker.HoursRecord
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.Session
  alias FirmowidWeb.Invoicing.Utilities.Navigation

  test "matches a net payout alternative using the contract from the salary month", %{conn: conn} do
    admin = admin_fixture()
    scope = Scope.new!(admin, admin.member.organization_id)

    project =
      Ash.Seed.seed!(Project, %{name: "Net salary", organization_id: scope.tenant})

    seed_salary_months!(admin, project, [{~D[2025-12-01], 100}])

    seed_salary_contract!(admin, :uz, ~D[2025-01-01])
    seed_salary_contract!(admin, :uop, ~D[2026-01-01])

    # 7,223.34 is outside the former 20% window around 10,000 gross.
    transaction = transaction_fixture!(admin, %{amount: Money.new!(:PLN, "-7223.34")})

    assert %{suggestions: [%{payout_variant: :uz_social, difference: difference}]} =
             Finances.suggest_transaction_salaries!(transaction.id, scope: scope)

    assert Money.zero?(difference)

    # The health-only alternative is preferred when its amount is closer.
    alternative = transaction_fixture!(admin, %{amount: Money.new!(:PLN, -8140)})

    assert %{suggestions: [%{payout_variant: :uz_health, difference: difference}]} =
             Finances.suggest_transaction_salaries!(alternative.id, scope: scope)

    assert Money.zero?(difference)

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/transakcje/#{alternative.id}")
    candidate = "#salary-suggestion-#{admin.id}-2025-12-01"
    assert has_element?(view, candidate, "Zlecenie — tylko zdrowotna")
    view |> element("#{candidate} button", "Zatwierdź") |> render_click()
    assert has_element?(view, "#salary-confirmation", "Zlecenie — tylko zdrowotna")

    assert [%{expected_amount: gross, payout_estimates: estimates}] =
             Finances.list_monthly_salaries!(~D[2025-12-01], scope: scope)

    assert gross == Money.new!(:PLN, 10_000)
    assert Enum.map(estimates, & &1.variant) == [:uz_health, :uz_social]
  end

  test "only proposes submitted unassigned salary months while preserving manual assignment", %{
    conn: conn
  } do
    admin = admin_fixture()
    scope = Scope.new!(admin, admin.member.organization_id)

    project =
      Ash.Seed.seed!(Project, %{
        name: "Submitted salary hours",
        organization_id: admin.member.organization_id
      })

    seed_salary_months!(
      admin,
      project,
      [{~D[2025-10-01], 10}, {~D[2025-11-01], 10}, {~D[2025-12-01], 10}],
      false
    )

    seed_hours_record!(admin, ~D[2025-11-01], 10, :withdrawn)
    submitted = seed_hours_record!(admin, ~D[2025-12-01], 10, :submitted)

    first = transaction_fixture!(admin, %{amount: Money.new!(:PLN, -1000)})
    second = transaction_fixture!(admin, %{amount: Money.new!(:PLN, -1000)})
    conn = log_in_user(conn, admin)
    {:ok, first_view, html} = live(conn, ~p"/transakcje/#{first.id}")

    assert salary_candidate_ids(html) == ["salary-suggestion-#{admin.id}-2025-12-01"]

    first_view
    |> element("#salary-suggestion-#{admin.id}-2025-12-01 button", "Zatwierdź")
    |> render_click()

    {:ok, second_view, _html} = live(conn, ~p"/transakcje/#{second.id}")
    refute has_element?(second_view, "#salary-suggestions")

    first_view |> element("#disconnect-salary") |> render_click()
    Ash.Seed.update!(submitted, %{submission_status: :withdrawn})

    {:ok, second_view, _html} = live(conn, ~p"/transakcje/#{second.id}")
    refute has_element?(second_view, "#salary-suggestions")

    assigned =
      Finances.connect_transaction_salary!(
        second,
        %{salary_user_id: admin.id, salary_month: ~D[2025-12-01]},
        scope: scope
      )

    assert assigned.salary_month == ~D[2025-12-01]
    assert assigned.salary_user_id == admin.id
  end

  test "restores a skipped transfer and assigns a salary once, repeatably, without overwriting" do
    admin = admin_fixture()
    scope = Scope.new!(admin, admin.member.organization_id)

    project =
      Ash.Seed.seed!(Project, %{
        name: "Salary hours",
        organization_id: admin.member.organization_id
      })

    seed_salary_months!(admin, project, [{~D[2025-12-01], 10}])

    skipped =
      transaction_fixture!(admin, %{amount: Money.new!(:PLN, -1000), skip_invoicing: true})

    other = transaction_fixture!(admin, %{amount: Money.new!(:PLN, -1000)})
    december = %{salary_user_id: admin.id, salary_month: ~D[2025-12-01]}

    assert %{suggestions: [%{user_id: user_id, month: ~D[2025-12-01]}], reason: nil} =
             Finances.suggest_transaction_salaries!(skipped.id, scope: scope)

    assert user_id == admin.id
    assert {:error, _} = Finances.connect_transaction_salary(skipped, december, scope: scope)

    restored = Finances.restore_transaction_for_matching!(skipped, scope: scope)

    assert Finances.restore_transaction_for_matching!(restored, scope: scope).skip_invoicing ==
             false

    assigned = Finances.connect_transaction_salary!(restored, december, scope: scope)

    assert Finances.connect_transaction_salary!(assigned, december, scope: scope).salary_month ==
             ~D[2025-12-01]

    assert {:error, _} = Finances.restore_transaction_for_matching(assigned, scope: scope)

    assert {:error, error} = Finances.connect_transaction_salary(other, december, scope: scope)
    assert Exception.message(error) =~ skipped.id

    assert %{suggestions: [], reason: :salaries_already_paid} =
             Finances.suggest_transaction_salaries!(other.id, scope: scope)

    assert [
             %{connected_transaction_id: connected_id, hours_submission_status: :submitted} =
               salary
           ] =
             Finances.list_monthly_salaries!(~D[2025-12-15], scope: scope)

    assert connected_id == skipped.id
    assert salary.expected_amount == Money.new!(:PLN, 1000)
  end

  test "prioritizes the payroll month and shows all candidates up to six months back", %{
    conn: conn
  } do
    admin = admin_fixture()

    project =
      Ash.Seed.seed!(Project, %{
        name: "Salary matching",
        organization_id: admin.member.organization_id
      })

    month_hours =
      for offset <- -7..1 do
        month = Date.shift(~D[2026-01-01], month: offset)
        {month, if(month == ~D[2025-12-01], do: 9, else: 10)}
      end

    seed_salary_months!(admin, project, month_hours)

    conn = log_in_user(conn, admin)

    for {date, expected_month} <- [
          {~D[2026-01-14], ~D[2025-12-01]},
          {~D[2026-01-15], ~D[2026-01-01]}
        ] do
      transaction =
        transaction_fixture!(admin, %{booking_date: date, amount: Money.new!(:PLN, -1000)})

      {:ok, view, html} = live(conn, ~p"/transakcje/#{transaction.id}")

      candidate_ids = salary_candidate_ids(html)

      assert length(candidate_ids) == 7
      assert hd(candidate_ids) == "salary-suggestion-#{admin.id}-#{expected_month}"
      assert has_element?(view, "#salary-suggestion-#{admin.id}-2025-07-01")
      refute has_element?(view, "#salary-suggestion-#{admin.id}-2025-06-01")
      refute has_element?(view, "#salary-suggestion-#{admin.id}-2026-02-01")

      view
      |> element("#salary-suggestion-#{admin.id}-#{expected_month} button", "Zatwierdź")
      |> render_click()

      assert has_element?(view, "#salary-confirmation")
      refute has_element?(view, "#salary-suggestions")

      view |> element("#disconnect-salary") |> render_click()
      assert has_element?(view, "#salary-suggestions")
    end
  end

  test "full recipient name outranks month and amount without excluding unnamed candidates", %{
    conn: conn
  } do
    admin = admin_fixture(%{name: "Łukasz Żółć"})

    project =
      Ash.Seed.seed!(Project, %{
        name: "Salary names",
        organization_id: admin.member.organization_id
      })

    [partial, unrelated, unnamed] =
      for name <- ["Adam Żółć", "Adam Nowak", nil] do
        employee = user_in_org_fixture(admin.member.organization_id, %{name: name})

        seed_salary_months!(employee, project, [{~D[2025-12-01], 10}])
        employee
      end

    seed_salary_months!(admin, project, [{~D[2025-12-01], 1}, {~D[2025-10-01], 10}])
    conn = log_in_user(conn, admin)

    for recipient <- ["ZOLC LUKASZ", "  ŁUKASZ, ŻÓŁĆ  ul. Testowa 12 "] do
      transaction =
        transaction_fixture!(admin, %{creditor_name: recipient, amount: Money.new!(:PLN, -1000)})

      {:ok, view, html} = live(conn, ~p"/transakcje/#{transaction.id}")

      ids = salary_candidate_ids(html)

      assert Enum.take(ids, 3) == [
               "salary-suggestion-#{admin.id}-2025-12-01",
               "salary-suggestion-#{admin.id}-2025-10-01",
               "salary-suggestion-#{partial.id}-2025-12-01"
             ]

      assert MapSet.new(Enum.drop(ids, 3)) ==
               MapSet.new([
                 "salary-suggestion-#{unrelated.id}-2025-12-01",
                 "salary-suggestion-#{unnamed.id}-2025-12-01"
               ])

      assert has_element?(
               view,
               "#salary-suggestion-#{unnamed.id}-2025-12-01",
               to_string(unnamed.email)
             )
    end

    for recipient <- ["Żółć", nil] do
      transaction =
        transaction_fixture!(admin, %{creditor_name: recipient, amount: Money.new!(:PLN, -1000)})

      {:ok, _view, html} = live(conn, ~p"/transakcje/#{transaction.id}")
      ids = salary_candidate_ids(html)

      assert length(ids) == 5
      assert hd(ids) != "salary-suggestion-#{admin.id}-2025-12-01"
      assert "salary-suggestion-#{admin.id}-2025-10-01" in ids
    end
  end

  test "accepts a difference of 1000 PLN but rejects amounts beyond the window" do
    admin = admin_fixture()
    scope = Scope.new!(admin, admin.member.organization_id)
    project = Ash.Seed.seed!(Project, %{name: "Payout tolerance", organization_id: scope.tenant})
    seed_salary_months!(admin, project, [{~D[2025-12-01], 10}])

    boundary = transaction_fixture!(admin, %{amount: Money.new!(:PLN, -2000)})
    outside = transaction_fixture!(admin, %{amount: Money.new!(:PLN, "-2000.01")})

    assert %{suggestions: [%{difference: difference}]} =
             Finances.suggest_transaction_salaries!(boundary.id, scope: scope)

    assert Money.equal?(difference, Money.new!(:PLN, 1000))

    assert %{suggestions: [], reason: :amount_out_of_range} =
             Finances.suggest_transaction_salaries!(outside.id, scope: scope)
  end

  test "shows zero state for an unmatched transaction", %{conn: conn} do
    admin = admin_fixture()

    transaction =
      transaction_fixture!(admin, %{remittance_information_unstructured: "Unmatched payment"})

    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/transakcje/#{transaction.id}")

    assert has_element?(view, "#transaction-show", "Brak rekomendacji")

    assert has_element?(
             view,
             "#transaction-show",
             "Firmowid nie znalazł jeszcze żadnych faktur, które potencjalnie pasowałyby do tej transakcji."
           )

    assert has_element?(view, "#transaction-show button[phx-click='toggle-invoicing']", "Pomiń")

    refute html =~ "Dopasowanie"
    refute html =~ "Transakcja pominięta"
  end

  test "shows skipped state for a skipped transaction", %{conn: conn} do
    admin = admin_fixture()
    transaction = transaction_fixture!(admin, %{skip_invoicing: true})
    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/transakcje/#{transaction.id}")

    assert has_element?(view, "#transaction-show", "Transakcja pominięta")

    assert has_element?(
             view,
             "#transaction-show",
             "Transakcja została pominięta w dopasowywaniu. Przywróć ją, jeśli jednak chcesz połączyć ją z dokumentem."
           )

    assert has_element?(view, "#transaction-show button[phx-click='toggle-invoicing']")

    refute html =~ "Brak rekomendacji"
    refute html =~ "Dopasowanie"
  end

  test "shows connected view when the transaction is linked to an invoice", %{conn: conn} do
    admin = admin_fixture()

    transaction =
      transaction_fixture!(admin, %{
        remittance_information_unstructured: "Supplier payment January"
      })

    invoice = cost_invoice_fixture!(admin)
    link_transaction_to_cost_invoice!(admin, transaction, invoice)
    conn = log_in_user(conn, admin)

    {:ok, view, html} = live(conn, ~p"/transakcje/#{transaction.id}")

    assert has_element?(view, "#transaction-show", "Dopasowanie")
    assert has_element?(view, "#transaction-show", "Komplet")
    assert has_element?(view, "#transaction-show", invoice.invoice_identifier)
    assert has_element?(view, "#transaction-show", invoice.seller_display_name)
    assert has_element?(view, "#transaction-show", "Faktura kosztowa")
    assert has_element?(view, "#transaction-show button[phx-click='unlink_all']")

    refute html =~ "Brak rekomendacji"
    refute html =~ "Transakcja pominięta"
  end

  test "suggests tenant-owned cost invoices and confirms and undoes a match from the transaction",
       %{conn: conn} do
    admin = admin_fixture()
    scope = Scope.new!(admin, admin.member.organization_id)
    transaction = transaction_fixture!(admin, %{})
    invoice = cost_invoice_fixture!(admin)
    skipped = cost_invoice_fixture!(admin, %{skip_invoicing: true})
    foreign = cost_invoice_fixture!(admin_fixture())
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/transakcje/#{transaction.id}")

    assert has_element?(view, "#invoice-suggestions", invoice.invoice_identifier)
    refute has_element?(view, "#invoice-suggestion-#{skipped.id}")
    refute has_element?(view, "#invoice-suggestion-#{foreign.id}")
    refute has_element?(view, "#transaction-show", "Brak rekomendacji")

    view
    |> element("#invoice-suggestion-#{invoice.id} button", "Zatwierdź")
    |> render_click()

    assert has_element?(view, "#transaction-show", "Komplet")
    refute has_element?(view, "#invoice-suggestions")

    assert %{transactions: [%{id: transaction_id}]} =
             Invoicing.get_cost_invoice!(invoice.id, load: [:transactions], scope: scope)

    assert transaction_id == transaction.id

    view |> element("button[phx-click='unlink_all']") |> render_click()

    assert has_element?(view, "#invoice-suggestions", invoice.invoice_identifier)
  end

  test "suggests confirmed sales invoices for an incoming transaction and confirms the match", %{
    conn: conn
  } do
    admin = admin_fixture()
    scope = Scope.new!(admin, admin.member.organization_id)

    transaction =
      transaction_fixture!(admin, %{
        amount: Money.new!(:PLN, 123),
        debtor_name: "Example customer"
      })

    invoice = sales_invoice_fixture!(admin)
    draft = sales_invoice_fixture!(admin, %{invoice_number: nil})
    conn = log_in_user(conn, admin)

    {:ok, view, _html} = live(conn, ~p"/transakcje/#{transaction.id}")

    assert has_element?(view, "#invoice-suggestions", invoice.invoice_number)
    refute has_element?(view, "#invoice-suggestion-#{draft.id}")

    view
    |> element("#invoice-suggestion-#{invoice.id} button", "Zatwierdź")
    |> render_click()

    assert has_element?(view, "#transaction-show", "Komplet")
    assert has_element?(view, "#transaction-show", "Faktura sprzedażowa")

    assert %{transactions: [%{id: transaction_id}]} =
             Invoicing.get_sales_invoice!(invoice.id, load: [:transactions], scope: scope)

    assert transaction_id == transaction.id
  end

  test "uses an allowlisted return_to path for back navigation", %{conn: conn} do
    admin = admin_fixture()

    transaction =
      transaction_fixture!(admin, %{
        remittance_information_unstructured: "Back navigation payment"
      })

    conn = log_in_user(conn, admin)
    raw_return_to = "/fakturowanie?miesiac=2026-01-15&filtr=faktury&widok=lista"
    origin_return_to = Navigation.return_to_path(raw_return_to)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/transakcje/#{transaction.id}?#{[powrot_do: raw_return_to]}"
      )

    assert html =~ ~s(href="#{String.replace(origin_return_to, "&", "&amp;")}")
  end

  test "preserves transaction return context in linked invoice navigation", %{conn: conn} do
    admin = admin_fixture()

    transaction =
      transaction_fixture!(admin, %{remittance_information_unstructured: "Linked return flow"})

    invoice = cost_invoice_fixture!(admin)
    link_transaction_to_cost_invoice!(admin, transaction, invoice)
    conn = log_in_user(conn, admin)

    raw_origin_return_to = "/fakturowanie?miesiac=2026-01-15&filtr=faktury&widok=lista"
    origin_return_to = Navigation.return_to_path(raw_origin_return_to)
    transaction_return_to = Navigation.transaction_show_path(transaction, origin_return_to)
    expected_invoice_path = Navigation.cost_invoice_show_path(invoice, transaction_return_to)

    {:ok, _view, html} =
      live(conn, ~p"/transakcje/#{transaction.id}?#{[powrot_do: raw_origin_return_to]}")

    assert html =~ ~s(href="#{expected_invoice_path}")
  end

  test "ignores a non-allowlisted return_to path for back navigation", %{conn: conn} do
    admin = admin_fixture()
    transaction = transaction_fixture!(admin, %{booking_date: ~D[2026-01-10]})
    conn = log_in_user(conn, admin)

    {:ok, _view, html} =
      live(conn, ~p"/transakcje/#{transaction.id}?#{[powrot_do: "https://example.com"]}")

    default_return_to =
      ~D[2026-01-10]
      |> Navigation.default_invoicing_path()
      |> String.replace("&", "&amp;")

    assert html =~ ~s(href="#{default_return_to}")
    refute html =~ "https://example.com"
  end

  defp salary_candidate_ids(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#salary-suggestions [id^='salary-suggestion-']")
    |> LazyHTML.attribute("id")
  end

  defp seed_salary_contract!(user, type, starts_at) do
    unique = System.unique_integer([:positive])

    blob =
      Ash.Seed.seed!(Blob, %{
        organization_id: user.member.organization_id,
        blob_path: "salary-contract-#{unique}.pdf",
        blob_checksum: "salary-contract-#{unique}",
        original_filename: "contract.pdf"
      })

    Ash.Seed.seed!(UserEmploymentContract, %{
      organization_id: user.member.organization_id,
      member_id: user.member.id,
      blob_id: blob.id,
      starts_at: starts_at,
      contract_type: type,
      salary: Money.new!(:PLN, 100),
      status: :active
    })
  end

  defp seed_salary_months!(user, project, month_hours, submit_hours? \\ true) do
    Ash.Seed.seed!(UserSalary, %{
      member_id: user.member.id,
      organization_id: user.member.organization_id,
      hourly_rate: Decimal.new(100),
      starts_at: ~U[2025-01-01 00:00:00Z]
    })

    Enum.each(month_hours, fn {month, hours} ->
      start = DateTime.new!(month, ~T[08:00:00], "Etc/UTC")

      Ash.Seed.seed!(Session, %{
        member_id: user.member.id,
        organization_id: user.member.organization_id,
        project_id: project.id,
        title: "Salary matching hours",
        start_datetime: start,
        end_datetime: DateTime.shift(start, hour: hours)
      })

      if submit_hours?, do: seed_hours_record!(user, month, hours, :submitted)
    end)
  end

  defp seed_hours_record!(user, month, hours, status) do
    unique = System.unique_integer([:positive])

    blob =
      Ash.Seed.seed!(Blob, %{
        organization_id: user.member.organization_id,
        blob_path: "salary-hours-#{unique}.pdf",
        blob_checksum: "salary-hours-#{unique}",
        original_filename: "hours.pdf"
      })

    Ash.Seed.seed!(HoursRecord, %{
      organization_id: user.member.organization_id,
      member_id: user.member.id,
      blob_id: blob.id,
      month: month.month,
      year: month.year,
      number_of_hours: hours,
      submission_status: status
    })
  end

  defp transaction_fixture!(admin, attrs) do
    unique = System.unique_integer([:positive])

    defaults = %{
      transaction_id: "TX-SHOW-#{unique}",
      internal_transaction_id: "INT-TX-SHOW-#{unique}",
      creditor_name: "Supplier Sp. z o.o.",
      creditor_account: "PL02114020040000300201355387",
      debtor_name: "Firmowid Sp. z o.o.",
      debtor_account: "PL61109010140000071219812874",
      amount: Money.new!("PLN", Decimal.new("-100.00")),
      booking_date: ~D[2026-01-10],
      value_date: ~D[2026-01-10],
      remittance_information_unstructured: "Payment January",
      bank_account_id: bank_account_fixture!(admin).id,
      skip_invoicing: false,
      organization_id: admin.member.organization_id
    }

    Ash.Seed.seed!(Transaction, Map.merge(defaults, attrs))
  end

  defp cost_invoice_fixture!(admin, attrs \\ %{}) do
    defaults = %{
      seller: "Supplier Sp. z o.o.",
      seller_display_name: "Supplier Sp. z o.o.",
      invoice_identifier: "CI/SHOW/#{System.unique_integer([:positive])}",
      description: "Cost invoice show test",
      sale_date: ~D[2026-01-10],
      issue_date: ~D[2026-01-10],
      due_date: ~D[2026-01-24],
      amount: Money.new!("PLN", Decimal.new("-100.00")),
      skip_invoicing: false,
      organization_id: admin.member.organization_id
    }

    Ash.Seed.seed!(CostInvoice, Map.merge(defaults, attrs))
  end

  defp sales_invoice_fixture!(admin, attrs \\ %{}) do
    invoice =
      Ash.Seed.seed!(
        SalesInvoice,
        Map.merge(
          %{
            invoice_number: "SI/SHOW/#{System.unique_integer([:positive])}",
            issue_date: ~D[2026-01-10],
            sale_date: ~D[2026-01-10],
            due_date: ~D[2026-01-24],
            currency: "PLN",
            buyer_full_name: "Example customer",
            seller_account_number: "PL61109010140000071219812874",
            organization_id: admin.member.organization_id
          },
          attrs
        )
      )

    Ash.Seed.seed!(SalesInvoiceItem, %{
      sales_invoice_id: invoice.id,
      organization_id: admin.member.organization_id,
      index: 0,
      name: "Programming service",
      quantity: Decimal.new(1),
      unit: "szt.",
      unit_price: Decimal.new(100),
      vat_rate: "23"
    })

    invoice
  end

  defp link_transaction_to_cost_invoice!(admin, transaction, invoice) do
    Ash.Seed.seed!(CostInvoiceTransaction, %{
      cost_invoice_id: invoice.id,
      transaction_id: transaction.id,
      organization_id: admin.member.organization_id
    })
  end
end
