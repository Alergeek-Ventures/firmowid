defmodule FirmowidWeb.Management.Views.EmployeesTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Blobs.Blob
  alias Firmowid.Core
  alias Firmowid.Delegations
  alias Firmowid.Delegations.Delegation
  alias Firmowid.Payroll
  alias Firmowid.Payroll.MemberPayrollInput
  alias Firmowid.Payroll.MemberTaxDeclaration
  alias Firmowid.Payroll.UserEmploymentContract
  alias Firmowid.Payroll.UserSalary
  alias Firmowid.Repo
  alias Firmowid.Scope
  alias Firmowid.Timetracker.HoursRecord

  test "employee list updates without refresh after invite consumption", %{conn: conn} do
    admin = admin_fixture()
    email = unique_user_email()

    invite =
      Core.create_invite!(%{issued_by_id: admin.id},
        tenant: admin.member.organization_id,
        actor: admin
      )

    conn = log_in_user(conn, admin)
    {:ok, lv, html} = live(conn, ~p"/zarzadzanie/pracownicy")

    refute html =~ email

    invited_user =
      create_unassigned_employee!(email)

    invite = Core.get_invite!(invite.id, tenant: admin.member.organization_id, actor: admin)

    Core.consume_invite!(invite, %{name: "Nowy Pracownik"},
      tenant: admin.member.organization_id,
      actor: invited_user
    )

    assert_eventually(fn -> render(lv) =~ "Nowy Pracownik" end)
  end

  test "admin can set hourly rate for newly joined employee", %{conn: conn} do
    admin = admin_fixture()
    email = unique_user_email()

    invite =
      Core.create_invite!(%{issued_by_id: admin.id},
        tenant: admin.member.organization_id,
        actor: admin
      )

    invited_user =
      create_unassigned_employee!(email)

    invite = Core.get_invite!(invite.id, tenant: admin.member.organization_id, actor: admin)

    Core.consume_invite!(invite, %{name: "Nowy Pracownik"},
      tenant: admin.member.organization_id,
      actor: invited_user
    )

    conn = log_in_user(conn, admin)
    {:ok, lv, _html} = live(conn, ~p"/zarzadzanie/pracownicy")

    lv
    |> element("input[phx-click='toggle_wages_view']")
    |> render_click()

    lv
    |> element("button[phx-click='toggle_wage_editor']")
    |> render_click()

    lv
    |> form("form[phx-submit='save_wages']", %{
      "employee" => %{
        admin.id => %{"wage" => "0"},
        invited_user.id => %{"wage" => "123.45"}
      }
    })
    |> render_submit()

    [salary] =
      Payroll.list_salaries!(%{user_id: invited_user.id, active_at: Date.utc_today()},
        scope: current_scope(admin)
      )

    assert Decimal.eq?(salary.hourly_rate, Decimal.new("123.45"))
  end

  test "archived employee is hidden from active list and visible in archive", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{role: :employee})

    Core.archive_member!(employee.member, scope: current_scope(admin))

    conn = log_in_user(conn, admin)

    assert {:ok, _lv, active_html} = live(conn, ~p"/zarzadzanie/pracownicy")
    refute active_html =~ to_string(employee.email)

    assert {:ok, _lv, archived_html} = live(conn, ~p"/zarzadzanie/pracownicy/archiwum")
    assert archived_html =~ to_string(employee.email)
  end

  test "an admin sees employees' names and avatars from their members", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{name: "Jan Kowalski"})

    blob =
      Ash.Seed.seed!(Blob, %{
        organization_id: admin.member.organization_id,
        blob_path: "#{admin.member.organization_id}/employee-avatar.png",
        blob_checksum: "employee-avatar",
        original_filename: "employee-avatar.png"
      })

    Ash.Seed.update!(employee.member, %{avatar_blob_id: blob.id})

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/zarzadzanie/pracownicy")

    assert has_element?(lv, "a[href*='#{employee.id}']", "Jan Kowalski")
    assert has_element?(lv, "img[src*='#{blob.blob_path}']")
  end

  test "admin cannot archive themselves", %{conn: conn} do
    admin = admin_fixture(%{name: "Admin Self"})
    conn = log_in_user(conn, admin)

    {:ok, lv, _html} = live(conn, ~p"/zarzadzanie/pracownicy/#{admin.id}")

    lv
    |> element("button[phx-click='archive_employee']")
    |> render_click()

    assert render(lv) =~ "Nie możesz zarchiwizować własnego konta."
  end

  test "admin can archive another admin", %{conn: conn} do
    admin = admin_fixture()
    second_admin = user_in_org_fixture(admin.member.organization_id, %{role: :admin})

    conn = log_in_user(conn, admin)
    {:ok, lv, _html} = live(conn, ~p"/zarzadzanie/pracownicy/#{second_admin.id}")

    lv
    |> element("button[phx-click='archive_employee']")
    |> render_click()

    assert {:ok, _archive_lv, archive_html} = live(conn, ~p"/zarzadzanie/pracownicy/archiwum")
    assert archive_html =~ to_string(second_admin.email)
  end

  test "an admin's bank account edit lands on the employee's member", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{role: :employee})

    {:ok, lv, _html} =
      live(log_in_user(conn, admin), ~p"/zarzadzanie/pracownicy/#{employee.id}/profil")

    lv |> element("[phx-click=toggle_payout_editor]") |> render_click()

    lv
    |> form("#payout-form", %{
      "hourly_rate" => "100",
      "bank_account_number" => "PL23 1140 2004 0000 3002 0135 5362"
    })
    |> render_submit()

    assert Core.load_member(employee).member.bank_account_number ==
             "PL23 1140 2004 0000 3002 0135 5362"

    assert Core.load_member(admin).member.bank_account_number == nil
  end

  test "employee detail page shows projects and hours without the accurate payout feature", %{
    conn: conn
  } do
    admin = admin_fixture()

    employee =
      user_in_org_fixture(admin.member.organization_id, %{role: :employee, name: "Jan Kowalski"})

    Core.update_member_profile!(
      employee.member,
      %{phone: "+48 600 700 800", bank_account_number: "PL23 1140 2004 0000 3002 0135 5362"},
      actor: employee,
      tenant: admin.member.organization_id
    )

    project =
      project_fixture(%{organization_id: admin.member.organization_id, name: "Payroll Project"})

    user_project_fixture(employee.id, project.id, admin.member.organization_id)

    Delegations.create_delegation!(delegation_attrs(), scope: current_scope(employee))

    user_salary_fixture(%{
      organization_id: admin.member.organization_id,
      user_id: employee.id,
      hourly_rate: Decimal.new("100.00")
    })

    session_fixture(%{
      organization_id: admin.member.organization_id,
      project_id: project.id,
      user_id: employee.id,
      title: "April Session",
      start_datetime: ~U[2026-04-03 09:00:00Z],
      end_datetime: ~U[2026-04-03 12:00:00Z]
    })

    seed_hours_record!(employee.member.id, admin.member.organization_id, 4, 2026, 3)

    conn = log_in_user(conn, admin)

    assert {:ok, _lv, html} =
             live(conn, ~p"/zarzadzanie/pracownicy/#{employee.id}?miesiac=2026-04-01")

    assert html =~ "Jan Kowalski"
    assert html =~ "+48 600 700 800"
    assert html =~ "PL23 1140 2004 0000 3002 0135 5362"
    assert html =~ "Payroll Project"
    assert html =~ "3 h"
    refute html =~ "Kwota do wypłaty"
    assert html =~ "EWIDENCJA"
    assert html =~ "April Session"
    assert html =~ "Delegacje"
  end

  test "opening a month shows its saved-data payout without a calculator", %{conn: conn} do
    environment = Application.fetch_env!(:firmowid, :environment)
    on_exit(fn -> Application.put_env(:firmowid, :environment, environment) end)
    Application.put_env(:firmowid, :environment, :dev)

    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id)
    identity = %{member_id: employee.member.id, organization_id: admin.member.organization_id}

    blob =
      Ash.Seed.seed!(Blob, %{
        organization_id: admin.member.organization_id,
        blob_path: "payroll-contract.pdf",
        blob_checksum: "payroll-contract-#{employee.member.id}",
        original_filename: "umowa.pdf"
      })

    Ash.Seed.seed!(
      UserEmploymentContract,
      Map.merge(identity, %{
        blob_id: blob.id,
        salary: Money.new!(:PLN, 100),
        starts_at: ~D[2026-01-01],
        contract_type: :uop,
        status: :active
      })
    )

    Ash.Seed.seed!(
      UserSalary,
      Map.merge(identity, %{hourly_rate: Decimal.new(100), starts_at: ~U[2026-01-01 00:00:00Z]})
    )

    Ash.Seed.seed!(
      MemberTaxDeclaration,
      Map.merge(identity, %{
        received_on: ~D[2026-01-01],
        applies_from: ~D[2026-01-01],
        tax_residency: :poland,
        pit2: :one_twelfth,
        employee_costs: :standard,
        youth_relief: :waived,
        tax_mode: :standard,
        pit0: :none,
        preferential: :none,
        copyright_costs: false,
        ppk: :none
      })
    )

    Ash.Seed.seed!(
      MemberPayrollInput,
      Map.merge(identity, %{
        salary_month: ~D[2026-04-01],
        payout_date: ~D[2026-04-30],
        payout_date_basis: :planned,
        gross: Decimal.new(6000),
        prior_taxable_income: Decimal.new(0),
        prior_social_base: Decimal.new(0),
        employer_ppk_income: Decimal.new(0),
        single_payment: true,
        standard_pay: true
      })
    )

    conn = log_in_user(conn, admin)
    {:ok, view, _html} = live(conn, ~p"/zarzadzanie/pracownicy/#{employee.id}?miesiac=2026-04-01")
    expected = to_string(Money.new!(:PLN, "4420.43"))

    assert has_element?(view, "#monthly-payout", expected)
    assert has_element?(view, "#monthly-payout", "Kwota do wypłaty")
    refute has_element?(view, "button", "Oblicz")
    refute has_element?(view, "#employee-payout-calculator-form")

    {:ok, next_month, _html} =
      live(conn, ~p"/zarzadzanie/pracownicy/#{employee.id}?miesiac=2026-05-01")

    refute has_element?(next_month, "#monthly-payout", expected)
    assert has_element?(next_month, "#monthly-payout", "Uzupełnij dane pracownika")
  end

  test "management delegations are grouped by status and pending entries link to the command page",
       %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{role: :employee})

    pending_delegation =
      Ash.Seed.seed!(Delegation, %{
        id: Ash.UUIDv7.generate(),
        organization_id: admin.member.organization_id,
        member_id: employee.member.id,
        title: "Delegacja wymagająca podpisu",
        billing_month: ~D[2026-08-01],
        destination: "Kraków",
        transport_types: [:railway],
        purpose: "Spotkanie z klientem",
        expected_cost: Money.new(:PLN, 100),
        start_date: ~D[2026-08-10],
        end_date: ~D[2026-08-11],
        status: :pending,
        reference: "JK-2026-08-1"
      })

    Ash.Seed.seed!(Delegation, %{
      id: Ash.UUIDv7.generate(),
      organization_id: admin.member.organization_id,
      member_id: employee.member.id,
      title: "Delegacja w trakcie",
      billing_month: ~D[2026-08-01],
      destination: "Kraków",
      transport_types: [:railway],
      purpose: "Spotkanie z klientem",
      expected_cost: Money.new(:PLN, 100),
      start_date: ~D[2026-08-10],
      end_date: ~D[2026-08-11],
      status: :in_progress,
      reference: "JK-2026-08-2"
    })

    Ash.Seed.seed!(Delegation, %{
      id: Ash.UUIDv7.generate(),
      organization_id: admin.member.organization_id,
      member_id: employee.member.id,
      title: "Zakończony wyjazd służbowy",
      billing_month: ~D[2026-08-01],
      destination: "Kraków",
      transport_types: [:railway],
      purpose: "Spotkanie z klientem",
      expected_cost: Money.new(:PLN, 100),
      start_date: ~D[2026-08-10],
      end_date: ~D[2026-08-11],
      status: :complete,
      reference: "JK-2026-08-3"
    })

    {:ok, view, _html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/zarzadzanie/pracownicy/#{employee.id}/delegacje")

    assert has_element?(view, "h2", "Delegacje w toku")
    assert has_element?(view, "h2", "Poprzednie delegacje")

    assert has_element?(
             view,
             "a[href='/zarzadzanie/pracownicy/#{employee.id}/delegacje/#{pending_delegation.reference}']"
           )

    assert render(view) =~ "wymaga podpisu"
  end

  test "admin can open a pending delegation command page", %{conn: conn} do
    admin = admin_fixture()

    employee =
      user_in_org_fixture(admin.member.organization_id, %{role: :employee, name: "Jan Kowalski"})

    delegation =
      Ash.Seed.seed!(Delegation, %{
        id: Ash.UUIDv7.generate(),
        organization_id: admin.member.organization_id,
        member_id: employee.member.id,
        title: "Wyjazd do klienta",
        billing_month: ~D[2026-08-01],
        purpose: "Spotkanie z klientem",
        destination: "Kraków",
        transport_types: [:railway],
        expected_cost: Money.new(:PLN, 100),
        start_date: ~D[2026-08-10],
        end_date: ~D[2026-08-11],
        status: :pending,
        reference: "JK-2026-08-1"
      })

    {:ok, view, html} =
      conn
      |> log_in_user(admin)
      |> live(~p"/zarzadzanie/pracownicy/#{employee.id}/delegacje/#{delegation.reference}")

    assert html =~ "Polecenie wyjazdu służbowego"
    assert html =~ "Jan Kowalski"
    assert html =~ "2026-08-01"
    assert html =~ "Wygeneruj polecenie, aby móc je podpisać."
    assert has_element?(view, "#delegation-employee-avatar")
    assert has_element?(view, "input[disabled][name='delegation_command[amount]']")
    assert has_element?(view, "input[name='delegation_command[amount]'][value='0']")

    assert has_element?(view, "#delegation-billing-month")

    render_hook(view, "change-month", %{"month" => "2026-09-01"})

    assert Delegations.get_delegation!(delegation.id, scope: current_scope(admin)).billing_month ==
             ~D[2026-09-01]

    view
    |> element("#delegation-command-form")
    |> render_change(%{"delegation_command" => %{"advance" => "true", "amount" => "0"}})

    refute has_element?(view, "input[disabled][name='delegation_command[amount]']")
    assert has_element?(view, "input[name='delegation_command[amount]'][value='0']")

    view
    |> form("#delegation-command-form", %{
      "delegation_command" => %{"advance" => "false"}
    })
    |> render_submit()

    assert render(view) =~ "Bez zaliczki"
    assert has_element?(view, "button[disabled]", "Wygeneruj polecenie")

    render_hook(view, "change-month", %{"month" => "2026-10-01"})

    refute has_element?(view, "button[disabled]", "Wygeneruj polecenie")

    view
    |> element("#delegation-command-form")
    |> render_change(%{"delegation_command" => %{"advance" => "true", "amount" => "100"}})

    refute has_element?(view, "button[disabled]", "Wygeneruj polecenie")

    view
    |> form("#delegation-command-form", %{
      "delegation_command" => %{"advance" => "true", "amount" => "1300.00"}
    })
    |> render_submit()

    assert has_element?(view, "#signed-command-upload")
    assert render(view) =~ "Zaliczka: 1 300,00 zł"

    upload =
      file_input(view, "#signed-command-upload", :signed_command, [
        %{
          name: "podpisane-polecenie.pdf",
          content: "%PDF-1.4 signed",
          type: "application/pdf"
        }
      ])

    render_upload(upload, "podpisane-polecenie.pdf")

    assert {:error, {:live_redirect, %{to: redirect_path}}} =
             view |> form("#signed-command-upload") |> render_submit()

    assert redirect_path == ~p"/zarzadzanie/pracownicy/#{employee.id}/delegacje"

    approved = Delegations.get_delegation!(delegation.id, scope: current_scope(admin))
    assert approved.status == :in_progress
    assert Money.equal?(approved.advance_amount, Money.new(:PLN, 1300))
    assert approved.signed_command_filename == "podpisane-polecenie.pdf"
    assert approved.signed_command_blob_id
  end

  test "admin can restore archived employee from employee detail page", %{conn: conn} do
    admin = admin_fixture()

    employee =
      user_in_org_fixture(admin.member.organization_id, %{role: :employee, name: "Restore Me"})

    Core.archive_member!(employee.member, scope: current_scope(admin))

    conn = log_in_user(conn, admin)
    {:ok, lv, html} = live(conn, ~p"/zarzadzanie/pracownicy/#{employee.id}")

    assert html =~ "zarchiwizowany"
    assert html =~ "Przywróć pracownika"

    lv
    |> element("button[phx-click='unarchive_employee']")
    |> render_click()

    updated_html = render(lv)
    refute updated_html =~ "zarchiwizowany"
    assert updated_html =~ "Archiwizuj"

    assert {:ok, _active_lv, active_html} = live(conn, ~p"/zarzadzanie/pracownicy")
    assert active_html =~ "Restore Me"
  end

  test "restoring an employee who joined another organization keeps them in both",
       %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id, %{name: "Moved On"})
    Core.archive_member!(employee.member, scope: current_scope(admin))

    employee
    |> Core.load_member()
    |> then(
      &Core.create_organization!(%{nip: unique_nip(), name: "Nowa firma", owner_name: "Moved On"},
        actor: &1
      )
    )

    conn = log_in_user(conn, admin)
    {:ok, lv, _html} = live(conn, ~p"/zarzadzanie/pracownicy/#{employee.id}")

    html =
      lv
      |> element("button[phx-click='unarchive_employee']")
      |> render_click()

    refute html =~ "zarchiwizowany"
    assert html =~ "Archiwizuj"
    assert length(Core.list_active_members(employee)) == 2
  end

  test "an archived employee rejoins with a new invite and gets its role", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.member.organization_id)
    Core.archive_member!(employee.member, scope: current_scope(admin))

    invite =
      Core.create_invite!(%{issued_by_id: admin.id, role: :invoicing},
        tenant: admin.member.organization_id,
        actor: admin
      )

    {:ok, lv, _html} = conn |> log_in_user(employee) |> live(~p"/organizacja")

    lv
    |> form("#join_form", %{"name" => "Ada Lovelace", "code" => invite.invite_code})
    |> render_submit()

    member = Core.load_member(employee).member
    assert member.role == :invoicing
    assert is_nil(member.archived_at)

    {:ok, _lv, html} = conn |> log_in_user(admin) |> live(~p"/zarzadzanie/pracownicy")
    assert html =~ "Ada Lovelace"
  end

  defp current_scope(admin) do
    %Scope{actor: admin, tenant: admin.member.organization_id}
  end

  defp delegation_attrs do
    %{
      title: "Spotkanie z klientem",
      billing_month: ~D[2026-09-01],
      destination: "Kraków",
      transport_types: [:railway],
      purpose: "Spotkanie z klientem",
      expected_cost: Money.new(:PLN, 100),
      start_date: ~D[2026-09-10],
      end_date: ~D[2026-09-11]
    }
  end

  defp seed_hours_record!(member_id, organization_id, month, year, hours) do
    blob =
      Ash.Seed.seed!(Blob, %{
        blob_path: "/test/path/hours_record_#{System.unique_integer([:positive])}.pdf",
        blob_checksum: "hr-checksum-#{System.unique_integer([:positive])}",
        original_filename: "hours_record.pdf",
        organization_id: organization_id
      })

    Repo.insert!(
      %HoursRecord{
        id: Ash.UUIDv7.generate(),
        member_id: member_id,
        blob_id: blob.id,
        month: month,
        year: year,
        number_of_hours: hours,
        organization_id: organization_id
      },
      skip_organization_id: true
    )
  end

  defp assert_eventually(fun, attempts \\ 20)

  defp assert_eventually(fun, 0), do: assert(fun.())

  defp assert_eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(25)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp create_unassigned_employee!(email) do
    %{email: email, password: valid_user_password()}
    |> Core.register_with_password!(authorize?: false, actor: %{})
    |> Core.load_member()
  end
end
