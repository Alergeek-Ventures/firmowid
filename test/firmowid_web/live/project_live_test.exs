defmodule FirmowidWeb.ProjectLiveTest do
  use FirmowidWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures
  alias Firmowid.Repo
  alias Firmowid.Timetracker

  describe "Project index page" do
    setup %{conn: conn} do
      user = admin_fixture()
      project1 = project_fixture(%{name: "Test Project 1"})
      project2 = project_fixture(%{name: "Test Project 2"})

      %{
        conn: log_in_user(conn, user),
        user: user,
        project1: project1,
        project2: project2
      }
    end

    test "renders projects page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/czasosledz/projekty")

      assert html =~ "Wszyscy współpracownicy"
      assert html =~ "Wybierz projekt"
    end

    test "shows project selector with available projects", %{
      conn: conn,
      project1: project1,
      project2: project2
    } do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty")

      assert has_element?(lv, "option", project1.name)
      assert has_element?(lv, "option", project2.name)
    end

    test "selects project and shows project details", %{conn: conn, project1: project1} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty")

      result =
        lv
        |> form("form[phx-change='select_project']", %{selected_project: project1.id})
        |> render_change()

      assert result =~ project1.name
      assert result =~ "Nad tym projektem pracują"
    end

    test "redirects if user lacks permissions", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      {:error, {:redirect, %{to: redirected_path}}} = live(conn, ~p"/czasosledz/projekty")
      assert redirected_path == ~p"/czasosledz"
    end
  end

  describe "Project name editing" do
    setup %{conn: conn} do
      user = admin_fixture()
      project = project_fixture(%{name: "Original Project Name"})

      %{
        conn: log_in_user(conn, user),
        user: user,
        project: project
      }
    end

    test "enables project name editing", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty/#{project.id}")

      lv
      |> element("button[phx-click='edit_name']")
      |> render_click()

      assert has_element?(lv, "input[name='project[name]']")
    end

    test "saves updated project name", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty/#{project.id}")

      lv
      |> element("button[phx-click='edit_name']")
      |> render_click()

      new_name = "Updated Project Name"

      result =
        lv
        |> form("form[phx-submit='save']", %{project: %{name: new_name}})
        |> render_submit()

      assert result =~ new_name
      updated_project = Timetracker.get_project!(project.id)
      assert updated_project.name == new_name
      html = render(lv)
      assert html =~ new_name
      assert html =~ "Nad tym projektem pracują"
    end

    test "validates project name", %{conn: conn, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty/#{project.id}")

      lv
      |> element("button[phx-click='edit_name']")
      |> render_click()

      result =
        lv
        |> form("form[phx-change='validate']", %{project: %{name: ""}})
        |> render_change()

      assert result =~ "can&#39;t be blank"
    end
  end

  describe "Project user management" do
    setup %{conn: conn} do
      admin = admin_fixture()
      user1 = user_in_org_fixture(admin.organization_id, %{email: "user1@example.com"})
      user2 = user_in_org_fixture(admin.organization_id, %{email: "user2@example.com"})
      user3 = user_in_org_fixture(admin.organization_id, %{email: "user3@example.com"})
      user4 = user_in_org_fixture(admin.organization_id, %{email: "user4@example.com"})
      Repo.put_org_id(admin.organization_id)
      project = project_fixture(%{name: "Test Project", organization_id: admin.organization_id})
      Timetracker.add_user_to_project(user1.id, project.id)
      Timetracker.add_user_to_project(user2.id, project.id)
      Timetracker.add_user_to_project(user3.id, project.id)
      # not adding user 4 to project
      %{
        conn: log_in_user(conn, admin),
        admin: admin,
        project: project,
        user1: user1,
        user2: user2,
        user3: user3,
        user4: user4
      }
    end

    test "shows users assigned to project", %{
      conn: conn,
      project: project,
      user1: user1,
      user2: user2,
      user3: user3
    } do
      {:ok, _lv, html} = live(conn, ~p"/czasosledz/projekty/#{project.id}")
      assert html =~ "Nad tym projektem pracują"
      assert html =~ user1.email
      assert html =~ user2.email
      assert html =~ user3.email
    end

    test "enables user editing mode", %{
      conn: conn,
      project: project,
      user1: user1,
      user2: user2,
      user3: user3
    } do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty/#{project.id}")

      lv
      |> element("button[phx-click='edit_users']")
      |> render_click()

      assert has_element?(lv, "button[phx-click='save_users']")
      assert has_element?(lv, "select[name='user_id']")
      assert has_element?(lv, "button[phx-click='delete_user'][phx-value-user_id='#{user1.id}']")
      assert has_element?(lv, "button[phx-click='delete_user'][phx-value-user_id='#{user2.id}']")
      assert has_element?(lv, "button[phx-click='delete_user'][phx-value-user_id='#{user3.id}']")
    end

    test "adds user to project", %{conn: conn, project: project, user1: user1, user4: user4} do
      {:ok, lv, html} = live(conn, ~p"/czasosledz/projekty/#{project.id}")

      # first check if one of original users is still here
      assert html =~ user1.email

      lv
      |> element("button[phx-click='edit_users']")
      |> render_click()

      lv
      |> form("form[phx-change='add_user']", %{user_id: user4.id})
      |> render_change()

      updated_html =
        lv
        |> element("button[phx-click='save_users']")
        |> render_click()

      # Verify if user4 was added to project
      assert updated_html =~ user1.email
      assert updated_html =~ user4.email
    end

    test "removes user from project without hours - user disappears", %{
      conn: conn,
      project: project,
      user1: user1
    } do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty/#{project.id}")

      lv
      |> element("button[phx-click='edit_users']")
      |> render_click()

      lv
      |> element("button[phx-click='delete_user'][phx-value-user_id='#{user1.id}']")
      |> render_click()

      lv
      |> element("button[phx-click='save_users']")
      |> render_click()

      refute has_element?(lv, "span", user1.email)
    end

    test "removes user from project with hours - user still visible in separate list", %{
      conn: conn,
      user3: user3,
      project: project
    } do
      # create a session for user3 in this project to simulate hours worked
      start_time = DateTime.utc_now() |> DateTime.add(-1, :hour)
      end_time = DateTime.utc_now()

      _session =
        session_fixture(%{
          user_id: user3.id,
          project_id: project.id,
          start_datetime: start_time,
          end_datetime: end_time
        })

      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty/#{project.id}")

      # Verify user3 is initially visible
      assert has_element?(lv, "span", user3.email)

      # remove user3 from project
      lv
      |> element("button[phx-click='edit_users']")
      |> render_click()

      lv
      |> element("button[phx-click='delete_user'][phx-value-user_id='#{user3.id}']")
      |> render_click()

      lv
      |> element("button[phx-click='save_users']")
      |> render_click()

      # Verify user is still visible in the UI in the "Nad tym projektem wcześniej pracowali" section
      assert has_element?(lv, "h2", "Nad tym projektem wcześniej pracowali")
      assert has_element?(lv, "span", user3.email)
    end
  end

  describe "Employee salary management" do
    setup %{conn: conn} do
      admin = admin_fixture()
      user1 = user_in_org_fixture(admin.organization_id, %{email: "emp1@example.com"})
      Repo.put_org_id(admin.organization_id)

      project =
        project_fixture(%{name: "Emp Salary Project", organization_id: admin.organization_id})

      Timetracker.add_user_to_project(user1.id, project.id)

      %{
        conn: log_in_user(conn, admin),
        admin: admin,
        user1: user1,
        project: project
      }
    end

    test "displays no rate message for user without salary", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty")

      lv
      |> element("button[phx-click='edit_all_users']")
      |> render_click()

      assert has_element?(lv, "div", "Brak stawki")
    end

    test "shows employee edit mode for all users", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty")

      lv
      |> element("button[phx-click='edit_all_users']")
      |> render_click()

      assert has_element?(lv, "button", "Edytuj")
    end

    test "enables salary editing for specific user", %{conn: conn, user1: user1} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty")

      lv
      |> element("button[phx-click='edit_all_users']")
      |> render_click()

      lv
      |> element("button[phx-click='edit_employee_salary'][phx-value-user_id='#{user1.id}']")
      |> render_click()

      assert has_element?(lv, "input[name='employee_salary_form_#{user1.id}[hourly_rate]']")

      assert has_element?(
               lv,
               "input[name='employee_salary_form_#{user1.id}[salary_type]'][value='hourly']"
             )
    end

    test "cancels salary editing", %{conn: conn, user1: user1} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty")

      lv
      |> element("button[phx-click='edit_all_users']")
      |> render_click()

      lv
      |> element("button[phx-click='edit_employee_salary'][phx-value-user_id='#{user1.id}']")
      |> render_click()

      lv
      |> element(
        "button[phx-click='cancel_edit_employee_salary'][phx-value-user_id='#{user1.id}']"
      )
      |> render_click()

      refute has_element?(lv, "input[name='employee_salary_form_#{user1.id}[hourly_rate]']")
      assert has_element?(lv, "button", "Edytuj")
    end

    test "adds new salary", %{conn: conn, user1: user1} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty")

      lv
      |> element("button[phx-click='edit_all_users']")
      |> render_click()

      lv
      |> element("button[phx-click='edit_employee_salary'][phx-value-user_id='#{user1.id}']")
      |> render_click()

      # Zapisz and Anuluj buttons should appear in edit mode
      assert has_element?(lv, "button", "Zapisz")
      assert has_element?(lv, "button", "Anuluj")

      attrs = %{
        "employee_salary_form_#{user1.id}" => %{
          "salary_type" => "hourly",
          "hourly_rate" => "25.75"
        }
      }

      lv
      |> form("form[phx-submit='save_employee_salary'][phx-value-user_id='#{user1.id}']", attrs)
      |> render_submit()

      # verify if salary was added to view
      assert has_element?(lv, "div", "25.75 PLN/h")

      # verify if salary was added to database
      salary = Timetracker.get_latest_user_salary(user1.id)
      assert salary.hourly_rate == Decimal.new("25.75")

      # should already exit edit mode
      refute has_element?(lv, "button", "Zapisz")
      refute has_element?(lv, "button", "Anuluj")
    end

    test "submits valid and invalid salary forms", %{conn: conn, user1: user1} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty")

      lv
      |> element("button[phx-click='edit_all_users']")
      |> render_click()

      lv
      |> element("button[phx-click='edit_employee_salary'][phx-value-user_id='#{user1.id}']")
      |> render_click()

      valid_attrs = %{
        "employee_salary_form_#{user1.id}" => %{
          "salary_type" => "hourly",
          "hourly_rate" => "65.75"
        }
      }

      lv
      |> form(
        "form[phx-submit='save_employee_salary'][phx-value-user_id='#{user1.id}']",
        valid_attrs
      )
      |> render_submit()

      # Check that valid data was saved successfully
      salary_after_valid = Timetracker.get_latest_user_salary(user1.id)
      assert salary_after_valid.hourly_rate == Decimal.new("65.75")
      assert has_element?(lv, "div", "65.75 PLN/h")

      # Now try to change it to invalid value
      lv
      |> element("button[phx-click='edit_employee_salary'][phx-value-user_id='#{user1.id}']")
      |> render_click()

      invalid_attrs = %{
        "employee_salary_form_#{user1.id}" => %{
          "salary_type" => "hourly",
          "hourly_rate" => "-10.00"
        }
      }

      # this prints info about trying to save invalid salary to console like it should, we will capture it to avoid confusion
      ExUnit.CaptureLog.capture_log(fn ->
        lv
        |> form(
          "form[phx-submit='save_employee_salary'][phx-value-user_id='#{user1.id}']",
          invalid_attrs
        )
        |> render_submit()
      end)

      assert has_element?(lv, "form[phx-submit='save_employee_salary']")

      # Check that invalid data was not saved
      # invalid salary is not rendered
      refute has_element?(lv, "div", "-10.00 PLN/h")
      # older valid salary is still rendered
      assert has_element?(lv, "div", "65.75 PLN/h")
      salary_after_invalid = Timetracker.get_latest_user_salary(user1.id)
      assert salary_after_invalid.hourly_rate != -10.00
      # old salary should stay in database
      assert salary_after_invalid.hourly_rate == Decimal.new("65.75")
    end
  end

  describe "User hours summary and expansion" do
    setup %{conn: conn} do
      admin = admin_fixture()
      user = user_in_org_fixture(admin.organization_id, %{email: "emp1@example.com"})
      user_salary_fixture(%{user_id: user.id, hourly_rate: Decimal.new("50.00")})
      Repo.put_org_id(admin.organization_id)

      project =
        project_fixture(%{name: "Emp Salary Project", organization_id: admin.organization_id})

      Timetracker.add_user_to_project(user.id, project.id)

      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        title: "Session 1",
        start_datetime: DateTime.utc_now() |> DateTime.add(-7200, :second),
        end_datetime: DateTime.utc_now() |> DateTime.add(-3600, :second)
      })

      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        title: "Session 2",
        start_datetime: DateTime.utc_now() |> DateTime.add(-3600, :second),
        end_datetime: DateTime.utc_now()
      })

      %{
        conn: log_in_user(conn, admin),
        admin: admin,
        user: user,
        project: project
      }
    end

    test "expands user details in project view", %{conn: conn, project: project, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty/#{project.id}")

      updated_html =
        lv
        |> element("button[phx-click='toggle-user'][phx-value-id='#{user.id}']")
        |> render_click()

      assert has_element?(lv, "span", "Session 1")
      assert has_element?(lv, "span", "Session 2")

      assert has_element?(lv, "div", "2 h")
      refute has_element?(lv, "div", "0 h")
      assert updated_html =~ user.email
    end

    test "expands user summary in all users view", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz/projekty")

      lv
      |> element("button[phx-click='toggle-user-summary'][phx-value-id='#{user.id}']")
      |> render_click()

      # Should show the user profile summary component
      assert has_element?(lv, "div", "Łączny czas")
      assert has_element?(lv, "div", "Stawka")
      assert has_element?(lv, "div", "Wynagrodzenie")

      assert has_element?(lv, "div.font-medium.text-lg", "2 h")
      assert has_element?(lv, "div.font-medium.text-lg", "50.00 PLN/h")
      assert has_element?(lv, "div.font-bold.text-lg", "100.00 PLN")
    end
  end
end
