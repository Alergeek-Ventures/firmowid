defmodule Firmowid.Timetracker.SessionTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias Ash.Error.Invalid
  alias Ecto.Adapters.SQL.Sandbox
  alias Firmowid.Scope
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Session
  alias Firmowid.Timetracker.Workers.StopSessionWorker

  setup do
    user = user_fixture()
    project = project_fixture(%{organization_id: user.member.organization_id})
    user_project_fixture(user.id, project.id, user.member.organization_id)

    scope = %Scope{
      actor: user,
      tenant: user.member.organization_id
    }

    %{user: user, project: project, scope: scope}
  end

  describe "create/2" do
    test "creates a session with valid params", %{user: user, project: project, scope: scope} do
      {:ok, session} =
        Session.create(
          %{
            title: "Working on feature",
            project_id: project.id,
            member_id: user.member.id,
            start_datetime: ~U[2025-04-01 09:00:00Z]
          },
          scope: scope
        )

      assert session.title == "Working on feature"
      assert session.project_id == project.id
      assert session.member_id == user.member.id
      assert is_nil(session.end_datetime)
    end

    test "creates a session with end_datetime", %{user: user, project: project, scope: scope} do
      {:ok, session} =
        Session.create(
          %{
            title: "Completed task",
            project_id: project.id,
            member_id: user.member.id,
            start_datetime: ~U[2025-04-01 09:00:00Z],
            end_datetime: ~U[2025-04-01 10:00:00Z]
          },
          scope: scope
        )

      assert session.end_datetime == ~U[2025-04-01 10:00:00Z]
    end

    test "normalizes explicit boundaries to minutes", %{
      user: user,
      project: project,
      scope: scope
    } do
      {:ok, session} =
        Session.create(
          %{
            title: "Completed task",
            project_id: project.id,
            member_id: user.member.id,
            start_datetime: ~U[2025-04-01 09:00:42Z],
            end_datetime: ~U[2025-04-01 10:00:17Z]
          },
          scope: scope
        )

      assert session.start_datetime == ~U[2025-04-01 09:00:00Z]
      assert session.end_datetime == ~U[2025-04-01 10:00:00Z]
    end

    test "rejects session with end before start", %{user: user, project: project, scope: scope} do
      assert {:error, _} =
               Session.create(
                 %{
                   title: "Bad times",
                   project_id: project.id,
                   member_id: user.member.id,
                   start_datetime: ~U[2025-04-01 10:00:00Z],
                   end_datetime: ~U[2025-04-01 09:00:00Z]
                 },
                 scope: scope
               )
    end
  end

  describe "stop/2" do
    test "stops a running session by setting end_datetime", %{
      project: project,
      scope: scope
    } do
      {:ok, session} =
        Session.start(
          %{
            title: "Running",
            project_id: project.id
          },
          scope: scope
        )

      assert is_nil(session.end_datetime)

      {:ok, stopped} = Session.stop(session, scope: scope)

      assert stopped.start_datetime.second == 0
      assert stopped.end_datetime.second == 0
    end
  end

  describe "stop_current/1" do
    test "stops the actor's running session without a client-supplied id", %{
      user: user,
      project: project,
      scope: scope
    } do
      {:ok, session} =
        Session.create(
          %{
            title: "Running",
            project_id: project.id,
            member_id: user.member.id,
            start_datetime: DateTime.utc_now()
          },
          scope: scope
        )

      {:ok, stopped} = Session.stop_current(scope: scope)

      assert stopped.id == session.id
      assert stopped.end_datetime
      assert is_nil(Session.get_current!(scope: scope))
    end

    test "returns nil when the actor has no running session", %{scope: scope} do
      assert {:ok, nil} = Session.stop_current(scope: scope)
    end
  end

  describe "MCP session reads" do
    test "load the linked project for previous and current sessions", %{
      user: user,
      project: project,
      scope: scope
    } do
      completed_session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          organization_id: user.member.organization_id,
          start_datetime: ~U[2025-04-01 09:00:00Z],
          end_datetime: ~U[2025-04-01 10:00:00Z]
        })

      current_session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          organization_id: user.member.organization_id
        })

      assert [listed_current, listed_completed] = Session.list_user_sessions!(scope: scope)
      assert listed_current.id == current_session.id
      assert listed_completed.id == completed_session.id
      assert listed_current.project.name == project.name
      assert listed_completed.project.name == project.name

      assert %{id: current_id, project: %{id: project_id, name: project_name}} =
               Session.get_current!(scope: scope)

      assert current_id == current_session.id
      assert project_id == project.id
      assert project_name == project.name
    end
  end

  describe "update/3" do
    test "updates session title", %{user: user, project: project, scope: scope} do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Old Title",
          organization_id: user.member.organization_id
        })

      {:ok, updated} = Session.update(session, %{title: "New Title"}, scope: scope)

      assert updated.title == "New Title"
    end

    test "normalizes legacy second-precision boundaries when editing", %{
      user: user,
      project: project,
      scope: scope
    } do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          organization_id: user.member.organization_id
        })

      Repo.query!(
        """
        UPDATE sessions
        SET start_datetime = '2025-04-01 09:00:42Z', end_datetime = '2025-04-01 10:00:17Z'
        WHERE id::text = $1
        """,
        [session.id]
      )

      session = Repo.get!(Session, session.id)

      {:ok, updated} = Session.update(session, %{title: "Edited legacy session"}, scope: scope)

      assert updated.start_datetime == ~U[2025-04-01 09:00:00Z]
      assert updated.end_datetime == ~U[2025-04-01 10:00:00Z]
    end

    test "keeps adjacent sessions editable with minute-only boundaries", %{
      user: user,
      project: project,
      scope: scope
    } do
      first_session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "First",
          start_datetime: ~U[2025-04-01 09:00:42Z],
          end_datetime: ~U[2025-04-01 10:00:17Z],
          organization_id: user.member.organization_id
        })

      second_session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          title: "Second",
          start_datetime: ~U[2025-04-01 10:00:00Z],
          end_datetime: ~U[2025-04-01 11:00:00Z],
          organization_id: user.member.organization_id
        })

      {:ok, updated} =
        Session.update(
          second_session,
          %{
            title: "Edited second",
            start_datetime: ~U[2025-04-01 10:00:00Z],
            end_datetime: ~U[2025-04-01 11:00:00Z]
          },
          scope: scope
        )

      assert first_session.end_datetime == updated.start_datetime
      assert updated.title == "Edited second"
    end
  end

  describe "edit_current_user_session/2" do
    test "updates the acting user's running session", %{
      user: user,
      project: project,
      scope: scope
    } do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          organization_id: user.member.organization_id
        })

      assert {:ok, updated} =
               Session.edit_current_user_session(%{id: session.id, title: "Updated"},
                 scope: scope
               )

      assert updated.title == "Updated"
      assert {:ok, current_session} = Session.current_session(session.id, scope: scope)
      assert current_session.id == session.id
    end

    test "does not let an admin edit another user's session", %{user: user, project: project} do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          organization_id: user.member.organization_id
        })

      admin = admin_fixture(%{organization_id: user.member.organization_id})
      admin_scope = %Scope{actor: admin, tenant: user.member.organization_id}

      assert {:error, _} =
               Session.edit_current_user_session(%{id: session.id, title: "Unauthorized"},
                 scope: admin_scope
               )

      assert Timetracker.get_session_by_id!(session.id,
               scope: %Scope{actor: user, tenant: user.member.organization_id}
             ).title == "Test Session"
    end
  end

  test "exposes self-scoped session and leave tools" do
    tool_names = Timetracker |> AshAi.Info.tools() |> Enum.map(& &1.name)

    assert :start_session in tool_names
    assert :edit_session in tool_names
    assert :list_leave_requests in tool_names
    assert :create_leave_request in tool_names
  end

  describe "destroy/2" do
    test "deletes a session", %{user: user, project: project, scope: scope} do
      session =
        session_fixture(%{
          user_id: user.id,
          project_id: project.id,
          organization_id: user.member.organization_id
        })

      assert :ok = Session.destroy(session, scope: scope)
      assert is_nil(Repo.get(Session, session.id))
    end
  end

  describe "overlap prevention" do
    @tag capture_log: true
    test "does not double hourly salary through independently committed overlapping sessions" do
      parent = self()

      {owner, user, scope, project, salary} =
        fn ->
          Sandbox.unboxed_run(Repo, fn ->
            owner = admin_fixture()
            user = user_fixture(%{organization_id: owner.member.organization_id})
            scope = Scope.new!(user, user.member.organization_id)

            project =
              Ash.Seed.seed!(Firmowid.Timetracker.Project, %{
                name: "Concurrent hours",
                organization_id: scope.tenant
              })

            Ash.Seed.seed!(Firmowid.Timetracker.ProjectUser, %{
              project_id: project.id,
              member_id: user.member.id,
              organization_id: scope.tenant
            })

            salary =
              Ash.Seed.seed!(Firmowid.Payroll.UserSalary, %{
                organization_id: scope.tenant,
                member_id: user.member.id,
                hourly_rate: Decimal.new(100),
                starts_at: ~U[2025-01-01 00:00:00Z]
              })

            {owner, user, scope, project, salary}
          end)
        end
        |> Task.async()
        |> Task.await(10_000)

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          assert {:ok, :ok} =
                   Repo.transaction(fn ->
                     :ok = Firmowid.Core.destroy_user_in_transaction(owner, actor: owner)
                     Firmowid.Core.User.destroy!(user, authorize?: false)
                   end)
        end)
      end)

      attrs = %{
        title: "Concurrent hourly work",
        project_id: project.id,
        member_id: user.member.id,
        start_datetime: ~U[2025-04-01 09:00:00Z],
        end_datetime: ~U[2025-04-01 10:00:00Z]
      }

      first =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Repo.transaction(fn ->
              session = Session.create!(attrs, scope: scope)
              %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
              send(parent, {:session_inserted, self(), backend_pid})

              receive do
                :commit -> session
              after
                10_000 -> raise "session commit barrier timed out"
              end
            end)
          end)
        end)

      assert_receive {:session_inserted, first_pid, first_backend}, 10_000

      second =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:session_backend, backend_pid})
            Session.create(attrs, scope: scope)
          end)
        end)

      assert_receive {:session_backend, backend_pid}, 10_000
      refute backend_pid == first_backend
      second_state = await_session_insert(second, backend_pid, 2_000)
      send(first_pid, :commit)
      assert {:ok, _session} = Task.await(first, 10_000)

      second_result =
        case second_state do
          :blocked -> Task.await(second, 10_000)
          {:completed, result} -> result
        end

      persisted = Ash.load!(salary, [monthly_amount: [month: ~D[2025-04-01]]], scope: scope)
      assert persisted.monthly_amount == Money.new!(:PLN, 100)
      assert {:error, _} = second_result
    end

    test "prevents overlapping sessions for the same user", %{
      user: user,
      project: project,
      scope: scope
    } do
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 00:00:00Z],
        end_datetime: ~U[2025-04-01 01:00:00Z],
        organization_id: user.member.organization_id
      })

      result =
        Session.create(
          %{
            title: "Overlap",
            project_id: project.id,
            member_id: user.member.id,
            start_datetime: ~U[2025-04-01 00:30:00Z],
            end_datetime: ~U[2025-04-01 01:30:00Z]
          },
          scope: scope
        )

      assert {:error, _} = result
    end

    test "prevents overlapping ongoing sessions", %{user: user, project: project, scope: scope} do
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        start_datetime: ~U[2025-04-01 00:00:00Z],
        organization_id: user.member.organization_id
      })

      result =
        Session.create(
          %{
            title: "Overlap",
            project_id: project.id,
            member_id: user.member.id,
            start_datetime: ~U[2025-04-01 00:30:00Z]
          },
          scope: scope
        )

      assert {:error, _} = result
    end
  end

  defp await_session_insert(_task, _backend_pid, 0), do: flunk("session insert did not complete or reach its lock")

  defp await_session_insert(task, backend_pid, attempts) do
    case Task.yield(task, 0) do
      {:ok, result} ->
        {:completed, result}

      nil ->
        %{rows: [[blocked]]} =
          Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [backend_pid])

        if blocked, do: :blocked, else: await_session_insert(task, backend_pid, attempts - 1)
    end
  end

  describe "auto-stop worker" do
    test "cancels pending auto-stop when session is stopped", %{project: project, scope: scope} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, session} =
          Session.start(%{title: "Running", project_id: project.id}, scope: scope)

        assert_enqueued(worker: StopSessionWorker)

        {:ok, _stopped} = Session.stop(session, scope: scope)

        refute_enqueued(worker: StopSessionWorker)
      end)
    end

    test "caps a still-running session at start + 12 hours", %{
      user: user,
      project: project,
      scope: scope
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        start_datetime = ~U[2026-03-10 08:00:00Z]

        {:ok, session} =
          Session.create(
            %{
              title: "Running",
              project_id: project.id,
              member_id: user.member.id,
              start_datetime: start_datetime
            },
            scope: scope
          )

        assert is_nil(session.end_datetime)

        assert :ok =
                 perform_job(StopSessionWorker, %{
                   "session_id" => session.id,
                   "organization_id" => session.organization_id
                 })

        updated = Ash.reload!(session, scope: scope)

        assert updated.end_datetime == DateTime.shift(start_datetime, hour: 12)
      end)
    end

    test "clamps the cap to the end of the start month", %{
      user: user,
      project: project,
      scope: scope
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, session} =
          Session.create(
            %{
              title: "Running",
              project_id: project.id,
              member_id: user.member.id,
              start_datetime: ~U[2026-08-31 20:00:00Z]
            },
            scope: scope
          )

        assert :ok =
                 perform_job(StopSessionWorker, %{
                   "session_id" => session.id,
                   "organization_id" => session.organization_id
                 })

        updated = Ash.reload!(session, scope: scope)

        assert updated.end_datetime == ~U[2026-08-31 23:59:00Z]
      end)
    end

    test "no-ops when session is already stopped", %{project: project, scope: scope} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, session} =
          Session.start(%{title: "Running", project_id: project.id}, scope: scope)

        {:ok, stopped} = Session.stop(session, scope: scope)

        assert :ok =
                 perform_job(StopSessionWorker, %{
                   "session_id" => stopped.id,
                   "organization_id" => stopped.organization_id
                 })

        reloaded = Ash.reload!(stopped, scope: scope)
        assert reloaded.end_datetime == stopped.end_datetime
      end)
    end
  end

  describe "same-month boundary" do
    test "rejects a created session whose end falls in the next month", %{
      user: user,
      project: project,
      scope: scope
    } do
      assert {:error, %Invalid{errors: [reason]}} =
               Session.create(
                 %{
                   title: "Month straddle",
                   project_id: project.id,
                   member_id: user.member.id,
                   start_datetime: ~U[2026-08-31 23:00:00Z],
                   end_datetime: ~U[2026-09-01 01:00:00Z]
                 },
                 scope: scope
               )

      assert reason.field == :end_datetime
    end

    test "rejects a session longer than 24 hours", %{user: user, project: project, scope: scope} do
      assert {:error, %Invalid{errors: [reason]}} =
               Session.create(
                 %{
                   title: "Too long",
                   project_id: project.id,
                   member_id: user.member.id,
                   start_datetime: ~U[2026-09-10 09:00:00Z],
                   end_datetime: ~U[2026-09-11 09:01:00Z]
                 },
                 scope: scope
               )

      assert reason.field == :end_datetime
    end
  end
end
