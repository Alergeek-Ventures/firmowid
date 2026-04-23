defmodule FirmowidWeb.Management.Views.EmployeesTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Payroll.UserSalary, as: AshUserSalary
  alias Firmowid.Ash.Scope

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

    salaries = AshUserSalary.as_of!(Date.utc_today(), scope: current_scope(admin))
    salary = Enum.find(salaries, &(&1.user_id == invited_user.id))

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

  defp current_scope(admin) do
    %Scope{actor: admin, tenant: admin.organization_id}
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
