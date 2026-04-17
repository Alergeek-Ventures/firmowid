defmodule FirmowidWeb.Timetracker.Views.IndexTest do
  use FirmowidWeb.ConnCase, async: true

  import Ecto.Query
  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures
  import Phoenix.LiveViewTest

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
        project: project
      }
    end

    test "starts new session", %{conn: conn, user: user, project: project} do
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
      current_session = get_current_session(user.id)
      assert current_session.title == title
      assert current_session.project_id == project.id
      assert is_nil(current_session.end_datetime)
    end

    test "saves new session without end time", %{conn: conn, user: user, project: project} do
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
      current_session = get_current_session(user.id)
      assert current_session.title == title
      assert current_session.project_id == project.id
      assert is_nil(current_session.end_datetime)
    end

    test "saves new session", %{conn: conn, user: user, project: project} do
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
      [current_session] = list_user_sessions(user.id)
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

  # Helper: fetch the running (no end_datetime) session for a user
  defp get_current_session(user_id) do
    Session
    |> where([s], s.user_id == ^user_id and is_nil(s.end_datetime))
    |> order_by([s], desc: s.start_datetime)
    |> limit(1)
    |> Repo.one()
  end

  # Helper: list all sessions for a user
  defp list_user_sessions(user_id) do
    Session
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], desc: s.start_datetime)
    |> Repo.all()
  end
end
