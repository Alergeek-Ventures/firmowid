defmodule FirmowidWeb.Infrastructure.Hooks.TimezoneTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures
  import Phoenix.LiveViewTest

  test "a browser reporting a time zone the database does not know still sees its sessions", %{
    conn: conn
  } do
    user = user_fixture()
    organization_id = user.member.organization_id
    project = project_fixture(%{name: "Acme", organization_id: organization_id})
    user_project_fixture(user.id, project.id, organization_id)

    session_fixture(%{
      user_id: user.id,
      project_id: project.id,
      title: "Monthly report",
      start_datetime: DateTime.utc_now(),
      organization_id: organization_id
    })

    # ICU reports this when it cannot determine the system time zone.
    {:ok, _lv, html} =
      conn
      |> log_in_user(user)
      |> put_connect_params(%{"timezone" => "Etc/Unknown"})
      |> live(~p"/czasosledz")

    assert html =~ "Monthly report"
  end
end
