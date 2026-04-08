defmodule FirmowidWeb.HoursRecord.Views.IndexTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.TimetrackerFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord

  setup %{conn: conn} do
    admin = admin_fixture()
    employee = user_in_org_fixture(admin.organization_id, %{role: :employee})

    # Required by hours-record flow guard in LiveView.
    employee =
      Core.update_profile!(employee, %{name: "Sable Orin", employment_date: ~D[2023-01-10]},
        authorize?: false,
        actor: %{},
        tenant: employee.organization_id
      )

    project = project_fixture(%{organization_id: admin.organization_id, name: "Hours Project"})
    user_project_fixture(employee.id, project.id, admin.organization_id)

    %{
      conn: log_in_user(conn, employee),
      employee: employee,
      project: project
    }
  end

  test "employee sees month breakdown and can submit signed hours record", %{
    conn: conn,
    employee: employee,
    project: project
  } do
    session_fixture(%{
      organization_id: employee.organization_id,
      project_id: project.id,
      user_id: employee.id,
      title: "S22 Session",
      start_datetime: ~U[2026-04-03 09:00:00Z],
      end_datetime: ~U[2026-04-03 11:15:00Z]
    })

    april = ~D[2026-04-01]
    {:ok, lv, html} = live(conn, ~p"/czasosledz/ewidencja?month=#{Date.to_iso8601(april)}")

    assert html =~ "Hours Project"
    assert html =~ "Ewidencja godzin"
    assert html =~ "BRAK"

    lv
    |> element("button[phx-click='toggle-project'][phx-value-id='#{project.id}']")
    |> render_click()

    assert render(lv) =~ "S22 Session"

    pdf_path = ~p"/czasosledz/ewidencja/#{Date.to_iso8601(april)}/pdf"
    assert render(lv) =~ pdf_path

    lv
    |> element("a[phx-click='download']")
    |> render_click()

    lv
    |> element("button[phx-click='sign']")
    |> render_click()

    upload_fixture = Path.expand("../../../../test/fixtures/receipt.png", __DIR__)

    lv
    |> file_input("#upload-form", :hours_record, [%{name: "signed-hours.png", content: File.read!(upload_fixture)}])
    |> render_upload("signed-hours.png")

    lv
    |> form("#upload-form", %{})
    |> render_submit()

    assert render(lv) =~ "WYSŁANO"

    scope = %Scope{actor: employee, tenant: employee.organization_id}
    {:ok, submitted_record} = AshHoursRecord.by_month(employee.id, 4, 2026, scope: scope)
    assert submitted_record.number_of_hours == 3
  end
end
