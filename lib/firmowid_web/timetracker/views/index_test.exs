defmodule FirmowidWeb.Timetracker.Views.IndexTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker.Session
  alias Firmowid.Repo

  describe "Timetracker page works" do
    test "renders timetracker page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(admin_fixture())
        |> live(~p"/czasosledz")

      assert html =~ "Zarządzanie"
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/czasosledz")

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/zaloguj"
    end
  end

  describe "session management" do
    setup %{conn: conn} do
      user = user_fixture()
      project = project_fixture(%{name: "Test Project", organization_id: user.organization_id})
      user_project_fixture(user.id, project.id, user.organization_id)

      %{
        conn: log_in_user(conn, user),
        user: user,
        scope: %Scope{actor: user, tenant: user.organization_id},
        project: project
      }
    end

    test "starts new session", %{conn: conn, scope: scope, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      title = "Test Session"

      result =
        lv
        |> form("#session_form", %{
          session_form: %{
            "project_id" => project.id,
            "title" => title
          }
        })
        |> render_submit()

      assert result =~ title
      current_session = Session.get_current!(scope: scope)
      assert current_session.title == title
      assert current_session.project_id == project.id
      assert is_nil(current_session.end_datetime)
    end

    test "saves new session without end time", %{conn: conn, scope: scope, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      title = "Test Session"

      lv |> element("#toggle_extended_form") |> render_click()

      result =
        lv
        |> form("#session_form", %{
          session_form: %{
            "project_id" => project.id,
            "title" => title,
            "date" => "2021-01-01",
            "start_time" => "14:00",
            "end_time" => nil
          }
        })
        |> render_submit()

      assert result =~ title
      assert result =~ "14:00"
      current_session = Session.get_current!(scope: scope)
      assert current_session.title == title
      assert current_session.project_id == project.id
      assert is_nil(current_session.end_datetime)
    end

    test "saves new session", %{conn: conn, scope: scope, project: project} do
      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      title = "Test Session"

      lv |> element("#toggle_extended_form") |> render_click()

      result =
        lv
        |> form("#session_form", %{
          session_form: %{
            "project_id" => project.id,
            "title" => title,
            "date" => "2021-01-01",
            "start_time" => "09:00",
            "end_time" => "17:00"
          }
        })
        |> render_submit()

      assert result =~ title
      assert result =~ "09:00"
      assert result =~ "17:00"
      [current_session] = Session.list_user_sessions!(scope: scope)
      assert current_session.title == title
      assert current_session.project_id == project.id
      assert current_session.end_datetime
    end

    test "pauses active session", %{conn: conn, user: user, project: project} do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Test Session",
          start_datetime: DateTime.utc_now(),
          organization_id: user.organization_id
        })

      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      result =
        lv
        |> element("button", "Stop")
        |> render_click()

      assert result =~ "Test Session"
      ended_session = Repo.get!(Session, session.id)
      assert ended_session.end_datetime
    end

    test "ignores stale validate_and_update after current session ends", %{
      conn: conn,
      user: user,
      scope: scope,
      project: project
    } do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Test Session",
          start_datetime: DateTime.utc_now(),
          organization_id: user.organization_id
        })

      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      lv
      |> element("button", "Stop")
      |> render_click()

      result =
        render_change(lv, "validate_and_update", %{
          "session_form" => %{
            "project_id" => project.id,
            "title" => "Stale update"
          }
        })

      assert result =~ "Stale update"

      ended_session = Repo.get!(Session, session.id)
      assert ended_session.end_datetime
      assert is_nil(Session.get_current!(scope: scope))
    end

    test "deletes session", %{conn: conn, user: user, project: project} do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          organization_id: user.organization_id
        })

      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      lv
      |> element("button[phx-click='delete_session'][phx-value-id='#{session.id}']")
      |> render_click()

      assert is_nil(Repo.get(Session, session.id))
    end

    test "edits session", %{conn: conn, user: user, project: project} do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Old Title",
          organization_id: user.organization_id
        })

      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      new_title = "Updated Title"

      result =
        lv
        |> form("#edit-session-form-#{session.id}", %{
          sessions_form: %{
            "title" => new_title
          }
        })
        |> render_submit()

      assert result =~ new_title
      updated_session = Repo.get!(Session, session.id)
      assert updated_session.title == new_title
    end

    test "edits an adjacent session through the minute-only form", %{
      conn: conn,
      user: user,
      project: project
    } do
      date = Date.utc_today()

      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        title: "First session",
        start_datetime: DateTime.new!(date, ~T[09:00:42], "Etc/UTC"),
        end_datetime: DateTime.new!(date, ~T[10:00:17], "Etc/UTC"),
        organization_id: user.organization_id
      })

      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Second session",
          start_datetime: DateTime.new!(date, ~T[10:00:00], "Etc/UTC"),
          end_datetime: DateTime.new!(date, ~T[11:00:00], "Etc/UTC"),
          organization_id: user.organization_id
        })

      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      local_start_datetime = DateTime.shift_zone!(session.start_datetime, "Europe/Warsaw")
      local_end_datetime = DateTime.shift_zone!(session.end_datetime, "Europe/Warsaw")

      result =
        lv
        |> form("#edit-session-form-#{session.id}", %{
          sessions_form: %{
            "ids" => [session.id],
            "title" => "Edited second session",
            "project_id" => project.id,
            "start_end_times" => %{
              "0" => %{
                "id" => session.id,
                "date" => Date.to_iso8601(DateTime.to_date(local_start_datetime)),
                "start_time" => Calendar.strftime(local_start_datetime, "%H:%M"),
                "end_time" => Calendar.strftime(local_end_datetime, "%H:%M")
              }
            }
          }
        })
        |> render_submit()

      assert result =~ "Edited second session"

      assert Repo.get!(Session, session.id).start_datetime == session.start_datetime
    end

    test "suggest previous project", %{conn: conn, user: user, project: project} do
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        title: "Test Session",
        start_datetime: DateTime.utc_now(),
        organization_id: user.organization_id
      })

      {:ok, _lv, html} = live(conn, ~p"/czasosledz")

      assert html =~
               "<option selected=\"\" value=\"#{project.id}\">"
    end
  end

  describe "project visibility" do
    test "shows no projects message for normal user", %{conn: conn} do
      user = user_fixture()

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/czasosledz")

      assert html =~ "Nie masz przypisanych projektów"
      assert html =~ "Poproś administratora o przypisanie Cię do projektu"
    end

    test "shows project management link for superuser", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(admin_fixture())
        |> live(~p"/czasosledz")

      assert html =~ "Przejdź do zarządzania projektami"
    end
  end
end
