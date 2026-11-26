defmodule FirmowidWeb.Timetracker.Views.IndexTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Repo
  alias Firmowid.Scope
  alias Firmowid.Timetracker.Session

  describe "Timetracker page works" do
    test "renders timetracker page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_user(admin_fixture())
        |> live(~p"/czasosledz")

      assert html =~ "Czasośledź"
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

      project =
        project_fixture(%{name: "Test Project", organization_id: user.member.organization_id})

      user_project_fixture(user.id, project.id, user.member.organization_id)

      %{
        conn: log_in_user(conn, user),
        user: user,
        scope: %Scope{actor: user, tenant: user.member.organization_id},
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
            "title" => title
          }
        })
        |> render_submit(%{session_form: %{"project_id" => project.id}})

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
            "title" => title,
            "date" => "2021-01-01",
            "start_time" => "14:00",
            "end_time" => nil
          }
        })
        |> render_submit(%{session_form: %{"project_id" => project.id}})

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
            "title" => title,
            "date" => "2021-01-01",
            "start_time" => "09:00",
            "end_time" => "17:00"
          }
        })
        |> render_submit(%{session_form: %{"project_id" => project.id}})

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
          organization_id: user.member.organization_id
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

    test "ends a legacy active session without a self-conflict", %{
      conn: conn,
      user: user,
      project: project
    } do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Legacy active session",
          start_datetime: ~U[2025-04-01 09:00:00Z],
          organization_id: user.member.organization_id
        })

      Repo.query!(
        "UPDATE sessions SET start_datetime = $1 WHERE id::text = $2",
        [~U[2025-04-01 09:00:42Z], session.id]
      )

      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      lv
      |> form("#session_form", %{session_form: %{}})
      |> render_submit()

      # Stopping sets the end only: moving the start to its minute could run into
      # the session that ended just before it.
      ended_session = Repo.get!(Session, session.id)
      assert ended_session.start_datetime == ~U[2025-04-01 09:00:42Z]
      assert ended_session.end_datetime.second == 0
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
          organization_id: user.member.organization_id
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
          organization_id: user.member.organization_id
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
          organization_id: user.member.organization_id
        })

      {:ok, lv, html} = live(conn, ~p"/czasosledz")

      assert has_element?(
               lv,
               "#edit-session-form-#{session.id} input[name='sessions_form[title]']"
             )

      refute html =~ ~s(id="edit-session-form-#{session.id}_title" readonly)

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

    test "switches a finished session from the office to remote work", %{
      conn: conn,
      user: user,
      project: project
    } do
      yesterday = Date.add(Date.utc_today(), -1)

      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Office day",
          start_datetime: DateTime.new!(yesterday, ~T[09:00:00], "Etc/UTC"),
          end_datetime: DateTime.new!(yesterday, ~T[12:00:00], "Etc/UTC"),
          organization_id: user.member.organization_id
        })

      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      assert has_element?(lv, "#session-work-mode-#{session.id}[aria-label*='W biurze']")

      lv
      |> element("#session-work-mode-list-#{session.id} button", "Zdalnie")
      |> render_click()

      updated_session = Repo.get!(Session, session.id)

      assert updated_session.is_remote
      assert updated_session.title == session.title
      assert updated_session.project_id == session.project_id
      assert updated_session.start_datetime == session.start_datetime
      assert updated_session.end_datetime == session.end_datetime

      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      assert has_element?(lv, "#session-work-mode-#{session.id}[aria-label*='Zdalnie']")

      assert has_element?(
               lv,
               "#edit-session-form-#{session.id} input[name='sessions_form[start_end_times][0][is_remote]'][value='true'][checked]"
             )
    end

    test "saves each grouped session's own workplace", %{conn: conn, user: user, project: project} do
      yesterday = Date.add(Date.utc_today(), -1)

      [morning, afternoon] =
        for {from, to} <- [{~T[09:00:00], ~T[10:00:00]}, {~T[13:00:00], ~T[14:00:00]}] do
          session_fixture(%{
            user_id: user.id,
            project_id: project.id,
            title: "Code review",
            start_datetime: DateTime.new!(yesterday, from, "Etc/UTC"),
            end_datetime: DateTime.new!(yesterday, to, "Etc/UTC"),
            organization_id: user.member.organization_id
          })
        end

      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      form_id =
        Enum.find_value([morning, afternoon], fn session ->
          id = "edit-session-form-#{session.id}"

          if has_element?(lv, "##{id} [name='sessions_form[start_end_times][1][is_remote]']"),
            do: id
        end)

      # The workplace dropdown writes its choice into a hidden input.
      lv
      |> form("##{form_id}")
      |> render_submit(%{
        sessions_form: %{
          "start_end_times" => %{
            "0" => %{"is_remote" => "false"},
            "1" => %{"is_remote" => "true"}
          }
        }
      })

      refute Repo.get!(Session, morning.id).is_remote
      assert Repo.get!(Session, afternoon.id).is_remote
    end

    test "keeps the chosen workplace when another field changes before Save", %{
      conn: conn,
      user: user,
      project: project
    } do
      yesterday = Date.add(Date.utc_today(), -1)

      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Office day",
          start_datetime: DateTime.new!(yesterday, ~T[09:00:00], "Etc/UTC"),
          end_datetime: DateTime.new!(yesterday, ~T[12:00:00], "Etc/UTC"),
          organization_id: user.member.organization_id
        })

      {:ok, lv, _html} = live(conn, ~p"/czasosledz")
      form_selector = "#edit-session-form-#{session.id}"

      lv
      |> form(form_selector, %{
        sessions_form: %{"start_end_times" => %{"0" => %{"is_remote" => "true"}}}
      })
      |> render_change()

      lv
      |> form(form_selector, %{sessions_form: %{"title" => "Remote day"}})
      |> render_change()

      lv |> form(form_selector) |> render_submit()

      updated_session = Repo.get!(Session, session.id)
      assert updated_session.title == "Remote day"
      assert updated_session.is_remote
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
        organization_id: user.member.organization_id
      })

      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Second session",
          start_datetime: DateTime.new!(date, ~T[10:00:00], "Etc/UTC"),
          end_datetime: DateTime.new!(date, ~T[11:00:00], "Etc/UTC"),
          organization_id: user.member.organization_id
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

      updated_session = Repo.get!(Session, session.id)

      assert updated_session.title == "Edited second session"
      assert updated_session.start_datetime == session.start_datetime
      assert updated_session.end_datetime == session.end_datetime
    end

    test "moves one session of a task to a new session", %{
      conn: conn,
      user: user,
      project: project
    } do
      date = Date.utc_today()
      title = "Wspólne zadanie"

      moved =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: title,
          start_datetime: DateTime.new!(date, ~T[09:00:00], "Etc/UTC"),
          end_datetime: DateTime.new!(date, ~T[10:00:00], "Etc/UTC"),
          organization_id: user.member.organization_id
        })

      kept =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: title,
          start_datetime: DateTime.new!(date, ~T[11:00:00], "Etc/UTC"),
          end_datetime: DateTime.new!(date, ~T[12:00:00], "Etc/UTC"),
          organization_id: user.member.organization_id
        })

      single =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Pojedyncze zadanie",
          start_datetime: DateTime.new!(date, ~T[13:00:00], "Etc/UTC"),
          end_datetime: DateTime.new!(date, ~T[14:00:00], "Etc/UTC"),
          organization_id: user.member.organization_id
        })

      {:ok, lv, _html} = live(conn, filtered_sessions_path(project, date))

      assert has_element?(lv, "#move-session-#{moved.id}")
      assert has_element?(lv, "#move-session-#{kept.id}")
      refute has_element?(lv, "#move-session-#{single.id}")

      lv |> element("#move-session-#{moved.id}") |> render_click()

      assert has_element?(lv, "#move-session-modal")
      assert has_element?(lv, "#move-session-form input[value='#{title}']")

      lv
      |> form("#move-session-form", move_session_form: %{"title" => "Nowe zadanie"})
      |> render_submit()

      refute has_element?(lv, "#move-session-modal")

      assert Repo.get!(Session, moved.id).title == "Nowe zadanie"
      assert Repo.get!(Session, kept.id).title == title

      # Moving a session renames it and nothing else: its times and project stay.
      moved_after = Repo.get!(Session, moved.id)
      assert moved_after.start_datetime == moved.start_datetime
      assert moved_after.end_datetime == moved.end_datetime
      assert moved_after.project_id == moved.project_id

      html = render(lv)
      assert html =~ "Nowe zadanie"
      assert html =~ title
    end

    test "refuses to move a session under its current name", %{
      conn: conn,
      user: user,
      project: project
    } do
      date = Date.utc_today()
      title = "Wspólne zadanie"

      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: title,
          start_datetime: DateTime.new!(date, ~T[09:00:00], "Etc/UTC"),
          end_datetime: DateTime.new!(date, ~T[10:00:00], "Etc/UTC"),
          organization_id: user.member.organization_id
        })

      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        title: title,
        start_datetime: DateTime.new!(date, ~T[11:00:00], "Etc/UTC"),
        end_datetime: DateTime.new!(date, ~T[12:00:00], "Etc/UTC"),
        organization_id: user.member.organization_id
      })

      {:ok, lv, _html} = live(conn, filtered_sessions_path(project, date))

      lv |> element("#move-session-#{session.id}") |> render_click()

      lv
      |> form("#move-session-form", move_session_form: %{"title" => title})
      |> render_submit()

      assert has_element?(lv, "#move-session-modal")

      assert render(lv) =~
               Gettext.gettext(Firmowid.Gettext, "must be different from the current name")

      assert Repo.get!(Session, session.id).title == title
    end

    test "suggest previous project", %{conn: conn, user: user, project: project} do
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        title: "Test Session",
        start_datetime: DateTime.utc_now(),
        organization_id: user.member.organization_id
      })

      {:ok, lv, _html} = live(conn, ~p"/czasosledz")

      assert has_element?(
               lv,
               "#session_form input[name='session_form[project_id]'][value='#{project.id}']"
             )
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

  defp filtered_sessions_path(project, date) do
    ~p"/czasosledz?projekt=#{project.id}&miesiac=#{Date.to_iso8601(date)}"
  end
end
