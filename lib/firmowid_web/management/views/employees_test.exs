defmodule FirmowidWeb.Management.Views.EmployeesTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord
  alias Firmowid.Repo

  test "employee list updates without refresh after invite consumption", %{conn: conn} do
    admin = admin_fixture()
    email = unique_user_email()

    invite =
      Core.create_invite!(%{issued_by_id: admin.id},
        tenant: admin.organization_id,
        actor: admin
      )

    conn = log_in_user(conn, admin)
    {:ok, lv, html} = live(conn, ~p"/zarzadzanie/pracownicy")

    refute html =~ email

    invited_user =
      create_unassigned_employee!(email)

    invite = Core.get_invite!(invite.id, tenant: admin.organization_id, actor: admin)

    Core.consume_invite!(invite, %{user_id: invited_user.id}, tenant: admin.organization_id)

    assert_eventually(fn -> render(lv) =~ email end)
  end

  test "admin can set hourly rate for newly joined employee", %{conn: conn} do
    admin = admin_fixture()
    email = unique_user_email()

    invite =
      Core.create_invite!(%{issued_by_id: admin.id},
        tenant: admin.organization_id,
        actor: admin
      )

    invited_user =
      create_unassigned_employee!(email)

    invite = Core.get_invite!(invite.id, tenant: admin.organization_id, actor: admin)

    Core.consume_invite!(invite, %{user_id: invited_user.id}, tenant: admin.organization_id)

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

    salary =
      %{active_at: Date.utc_today()}
      |> Payroll.list_salaries!(scope: current_scope(admin))
      |> Enum.find(&(&1.user_id == invited_user.id))

    assert salary
    assert Decimal.eq?(salary.hourly_rate, Decimal.new("123.45"))
  end

  test "archived employee is hidden from active list and visible in archive", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.organization_id, %{role: :employee})

    Core.archive_user!(employee, %{}, scope: current_scope(admin))

    conn = log_in_user(conn, admin)

    assert {:ok, _lv, active_html} = live(conn, ~p"/zarzadzanie/pracownicy")
    refute active_html =~ to_string(employee.email)

    assert {:ok, _lv, archived_html} = live(conn, ~p"/zarzadzanie/pracownicy/archiwum")
    assert archived_html =~ to_string(employee.email)
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
    second_admin = user_in_org_fixture(admin.organization_id, %{role: :admin})

    conn = log_in_user(conn, admin)
    {:ok, lv, _html} = live(conn, ~p"/zarzadzanie/pracownicy/#{second_admin.id}")

    lv
    |> element("button[phx-click='archive_employee']")
    |> render_click()

    assert {:ok, _archive_lv, archive_html} = live(conn, ~p"/zarzadzanie/pracownicy/archiwum")
    assert archive_html =~ to_string(second_admin.email)
  end

  test "employee detail page shows payroll and project summary for selected month", %{conn: conn} do
    admin = admin_fixture()

    employee = user_in_org_fixture(admin.organization_id, %{role: :employee})

    employee =
      Core.update_profile!(
        employee,
        %{
          name: "Jan Kowalski",
          phone: "+48 600 700 800",
          bank_account_number: "PL44 1140 2004 0000 3002 0135 5362"
        },
        actor: employee,
        tenant: admin.organization_id
      )

    project = project_fixture(%{organization_id: admin.organization_id, name: "Payroll Project"})
    user_project_fixture(employee.id, project.id, admin.organization_id)

    user_salary_fixture(%{
      organization_id: admin.organization_id,
      user_id: employee.id,
      hourly_rate: Decimal.new("100.00")
    })

    session_fixture(%{
      organization_id: admin.organization_id,
      project_id: project.id,
      user_id: employee.id,
      title: "April Session",
      start_datetime: ~U[2026-04-03 09:00:00Z],
      end_datetime: ~U[2026-04-03 12:00:00Z]
    })

    seed_hours_record!(employee.id, admin.organization_id, 4, 2026, 3)

    conn = log_in_user(conn, admin)

    assert {:ok, _lv, html} =
             live(conn, ~p"/zarzadzanie/pracownicy/#{employee.id}?miesiac=2026-04-01")

    assert html =~ "Jan Kowalski"
    assert html =~ "+48 600 700 800"
    assert html =~ "PL44 1140 2004 0000 3002 0135 5362"
    assert html =~ "Payroll Project"
    assert html =~ "3 godz."
    assert html =~ "Wynagrodzenie"
    assert html =~ "EWIDENCJA"
    assert html =~ "April Session"
  end

  test "admin can restore archived employee from employee detail page", %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.organization_id, %{role: :employee, name: "Restore Me"})

    Core.archive_user!(employee, %{}, scope: current_scope(admin))

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
    assert active_html =~ to_string(employee.email)
  end

  defp current_scope(admin) do
    %Scope{actor: admin, tenant: admin.organization_id}
  end

  defp seed_hours_record!(user_id, organization_id, month, year, hours) do
    blob =
      Ash.Seed.seed!(Blob, %{
        blob_path: "/test/path/hours_record_#{System.unique_integer([:positive])}.pdf",
        blob_checksum: "hr-checksum-#{System.unique_integer([:positive])}",
        original_filename: "hours_record.pdf",
        organization_id: organization_id
      })

    Repo.insert!(
      %AshHoursRecord{
        id: Ash.UUIDv7.generate(),
        user_id: user_id,
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
    Core.register_with_password!(%{email: email, password: valid_user_password()},
      authorize?: false,
      actor: %{}
    )
  end
end
