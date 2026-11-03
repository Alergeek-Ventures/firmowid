defmodule FirmowidMcp.Timetracker.AddSessionsTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures

  alias Firmowid.Scope
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Session
  alias FirmowidMcp.Router

  setup do
    user = user_fixture()
    organization_id = user.member.organization_id
    project = project_fixture(%{organization_id: organization_id})
    user_project_fixture(user.id, project.id, organization_id)

    running =
      session_fixture(%{
        user_id: user.id,
        project_id: project.id,
        organization_id: organization_id,
        title: "Running",
        start_datetime: ~U[2026-03-10 12:00:00Z]
      })

    %{user: user, project: project, running: running}
  end

  test "adds past sessions one at a time and in bulk while a session runs", %{
    user: user,
    project: project,
    running: running
  } do
    assert {:ok, [morning]} =
             call_add_sessions(user, [
               entry(project, "Morning", "2026-03-10T09:00:00+01:00", "2026-03-10T11:30:45+01:00")
             ])

    assert %{
             "title" => "Morning",
             "start_datetime" => "2026-03-10T08:00:00Z",
             "end_datetime" => "2026-03-10T10:30:00Z"
           } =
             morning

    assert {:ok, [_, _]} =
             call_add_sessions(user, [
               entry(project, "Review", "2026-03-09T08:00:00Z", "2026-03-09T10:00:00Z"),
               entry(project, "Planning", "2026-03-09T10:00:00Z", "2026-03-09T11:00:00Z")
             ])

    assert ["Running", "Morning", "Planning", "Review"] == Enum.map(sessions(user), & &1.title)
    assert_unchanged(user, running)
  end

  test "adds nothing and names the item when one session is rejected", %{
    user: user,
    project: project,
    running: running
  } do
    valid = entry(project, "Morning", "2026-03-10T08:00:00Z", "2026-03-10T09:00:00Z")

    assert {:error, message} =
             call_add_sessions(user, [
               valid,
               entry(project, "Too late", "2026-03-10T11:00:00Z", "2026-03-10T13:00:00Z")
             ])

    assert message =~ "sessions.1.start_datetime: overlaps existing sessions"
    assert message =~ running.id

    assert {:error, "sessions.1.start_datetime: must be before end datetime"} =
             call_add_sessions(user, [
               valid,
               entry(project, "Reversed", "2026-03-09T10:00:00Z", "2026-03-09T09:00:00Z")
             ])

    assert {:error, message} =
             call_add_sessions(user, [
               entry(project, "Next month", "2026-03-31T23:00:00Z", "2026-04-01T01:00:00Z")
             ])

    assert message =~ "sessions.0.end_datetime"

    assert {:error, _missing_end} =
             call_add_sessions(user, [Map.delete(valid, "end_datetime")])

    assert [%{id: id}] = sessions(user)
    assert id == running.id
    assert_unchanged(user, running)
  end

  test "rejects a month with a submitted hours record, for administrators too", %{
    user: user,
    project: project
  } do
    admin = admin_fixture(%{organization_id: user.member.organization_id})
    user_project_fixture(admin.id, project.id, user.member.organization_id)

    for caller <- [user, admin] do
      seed_submitted_hours_record!(caller, ~D[2026-02-01])

      assert {:error, "sessions.1.start_datetime: falls in a month with a submitted hours record"} =
               call_add_sessions(caller, [
                 entry(project, "March", "2026-03-02T08:00:00Z", "2026-03-02T09:00:00Z"),
                 entry(project, "February", "2026-02-02T08:00:00Z", "2026-02-02T09:00:00Z")
               ])

      refute Enum.any?(sessions(caller), &(&1.title in ["March", "February"]))
    end
  end

  test "never writes to projects or members outside the caller's access", %{
    user: user,
    project: project,
    running: running
  } do
    other = user_fixture()
    other_project = project_fixture(%{organization_id: other.member.organization_id})
    user_project_fixture(other.id, other_project.id, other.member.organization_id)
    unassigned = project_fixture(%{organization_id: user.member.organization_id})

    for foreign_project <- [other_project, unassigned] do
      assert {:error, message} =
               call_add_sessions(user, [
                 entry(foreign_project, "Foreign", "2026-03-09T08:00:00Z", "2026-03-09T09:00:00Z")
               ])

      assert message =~ "sessions.0.project_id"
    end

    assert {:ok, [%{"id" => own_id}]} =
             call_add_sessions(user, [
               project
               |> entry("Impersonated", "2026-03-09T08:00:00Z", "2026-03-09T09:00:00Z")
               |> Map.put("member_id", other.member.id)
             ])

    assert [running.id, own_id] == Enum.map(sessions(user), & &1.id)
    assert [] = sessions(other)
  end

  defp seed_submitted_hours_record!(user, month) do
    blob =
      Ash.Seed.seed!(Firmowid.Blobs.Blob, %{
        organization_id: user.member.organization_id,
        blob_path: "hours-#{user.id}.pdf",
        blob_checksum: "hours-#{user.id}",
        original_filename: "hours.pdf"
      })

    Ash.Seed.seed!(Firmowid.Timetracker.HoursRecord, %{
      organization_id: user.member.organization_id,
      member_id: user.member.id,
      blob_id: blob.id,
      month: month.month,
      year: month.year,
      number_of_hours: 10,
      submission_status: :submitted
    })
  end

  defp entry(project, title, start_datetime, end_datetime) do
    %{
      "title" => title,
      "project_id" => project.id,
      "start_datetime" => start_datetime,
      "end_datetime" => end_datetime
    }
  end

  defp call_add_sessions(user, sessions) do
    conn =
      :post
      |> Plug.Test.conn("/", %{
        "jsonrpc" => "2.0",
        "id" => "add-sessions",
        "method" => "tools/call",
        "params" => %{
          "name" => "add_sessions",
          "arguments" => %{"input" => %{"sessions" => sessions}}
        }
      })
      |> put_req_header("mcp-protocol-version", "2025-03-26")
      |> Ash.PlugHelpers.set_actor(user)
      |> Ash.PlugHelpers.set_tenant(user.member.organization_id)
      |> Router.call(Router.init(tools: [:add_sessions], mcp_resources: []))

    assert conn.status == 200, conn.resp_body

    case Jason.decode!(conn.resp_body)["result"] do
      %{"isError" => true, "content" => [%{"text" => text}]} -> {:error, text}
      %{"content" => [%{"text" => text}]} -> {:ok, Jason.decode!(text)}
    end
  end

  defp sessions(user) do
    Timetracker.list_sessions!(%{member_id: user.member.id},
      scope: %Scope{actor: user, tenant: user.member.organization_id},
      query: Ash.Query.sort(Session, start_datetime: :desc)
    )
  end

  defp assert_unchanged(user, running) do
    current =
      Session.get_current!(scope: %Scope{actor: user, tenant: user.member.organization_id})

    assert Map.take(current, [
             :id,
             :title,
             :start_datetime,
             :end_datetime,
             :project_id,
             :is_remote,
             :updated_at
           ]) ==
             Map.take(running, [
               :id,
               :title,
               :start_datetime,
               :end_datetime,
               :project_id,
               :is_remote,
               :updated_at
             ])
  end
end
