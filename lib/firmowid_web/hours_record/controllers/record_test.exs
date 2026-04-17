defmodule FirmowidWeb.HoursRecord.Controllers.RecordTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord
  alias Firmowid.Repo

  test "employee cannot download another employee's submitted hours record", %{conn: conn} do
    admin = admin_fixture()
    employee_a = user_in_org_fixture(admin.organization_id, %{role: :employee})
    employee_b = user_in_org_fixture(admin.organization_id, %{role: :employee})

    blob =
      Ash.Seed.seed!(Blob, %{
        blob_path: "/test/path/hr_record.pdf",
        blob_checksum: "hr-record-checksum-#{System.unique_integer([:positive])}",
        original_filename: "hr_record.pdf",
        organization_id: admin.organization_id
      })

    record =
      Repo.insert!(
        %AshHoursRecord{
          id: Ash.UUIDv7.generate(),
          user_id: employee_b.id,
          blob_id: blob.id,
          month: 4,
          year: 2026,
          number_of_hours: 8,
          organization_id: admin.organization_id
        },
        skip_organization_id: true
      )

    conn =
      conn
      |> log_in_user(employee_a)
      |> get(~p"/czasosledz/ewidencja/#{record.id}")

    assert redirected_to(conn) == ~p"/czasosledz"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Nie masz dostępu do tej ewidencji godzin."
  end
end
