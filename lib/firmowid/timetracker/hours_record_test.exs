defmodule Firmowid.Timetracker.HoursRecordTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Ash.Error.Forbidden
  alias Firmowid.Blobs.Blob
  alias Firmowid.Timetracker.HoursRecord

  setup do
    user = user_fixture()

    scope = %Firmowid.Scope{
      actor: user,
      tenant: user.member.organization_id
    }

    %{user: user, scope: scope}
  end

  defp seed_blob!(organization_id) do
    Ash.Seed.seed!(Blob, %{
      blob_path: "/test/path/hours_record_#{System.unique_integer([:positive])}.pdf",
      blob_checksum: "hr-checksum-#{System.unique_integer([:positive])}",
      original_filename: "hours_record.pdf",
      organization_id: organization_id
    })
  end

  describe "by_month/4" do
    test "returns record for a given user and month", %{user: user, scope: scope} do
      blob = seed_blob!(user.member.organization_id)

      # Insert directly — the create action requires blob upload infrastructure
      Repo.insert!(
        %HoursRecord{
          id: Ash.UUIDv7.generate(),
          member_id: user.member.id,
          blob_id: blob.id,
          month: 3,
          year: 2025,
          number_of_hours: 160,
          organization_id: user.member.organization_id
        },
        skip_organization_id: true
      )

      {:ok, record} = HoursRecord.by_month(user.member.id, 3, 2025, scope: scope)
      assert record.month == 3
      assert record.year == 2025
    end

    test "returns nil when no record exists", %{user: user, scope: scope} do
      {:ok, result} =
        HoursRecord.by_month(user.member.id, 6, 2025,
          scope: scope,
          not_found_error?: false
        )

      assert is_nil(result)
    end
  end

  describe "create/2" do
    test "stores no file when the actor may not create the record", %{user: user, scope: scope} do
      organization_id = user.member.organization_id
      other_user = user_in_org_fixture(organization_id)
      upload_path = Briefly.create!(extname: ".pdf")
      File.write!(upload_path, "%PDF-1.4 timesheet #{System.unique_integer()}")

      assert {:error, %Forbidden{}} =
               HoursRecord.create(
                 %{
                   member_id: other_user.member.id,
                   month: 3,
                   year: 2025,
                   number_of_hours: 160,
                   upload_path: upload_path,
                   upload_filename: "ewidencja.pdf"
                 },
                 scope: scope
               )

      assert Repo.aggregate(Blob, :count) == 0
    end
  end

  describe "withdraw_change_request/2" do
    test "the author takes back a pending request", %{user: user, scope: scope} do
      record = insert_requested_record!(user)

      assert {:ok, record} = HoursRecord.withdraw_change_request(record, scope: scope)
      assert is_nil(record.change_requested_at)
      assert is_nil(record.change_request_kind)
      assert is_nil(record.change_request_reason)
      assert record.submission_status == :submitted
    end

    # Admins pass every Timetracker action through the domain bypass.
    test "another employee cannot take it back", %{user: user} do
      record = insert_requested_record!(user)
      employee = user_in_org_fixture(user.member.organization_id, %{role: :employee})
      employee_scope = %Firmowid.Scope{actor: employee, tenant: user.member.organization_id}

      assert {:error, %Forbidden{}} =
               HoursRecord.withdraw_change_request(record, scope: employee_scope)
    end

    test "a request the administrators decided on stays", %{user: user, scope: scope} do
      record = insert_requested_record!(user, change_request_decision: :rejected)

      assert {:error, _error} = HoursRecord.withdraw_change_request(record, scope: scope)

      assert %{change_request_kind: :cancellation} =
               Repo.get!(HoursRecord, record.id, skip_organization_id: true)
    end
  end

  defp insert_requested_record!(user, attrs \\ []) do
    blob = seed_blob!(user.member.organization_id)

    Repo.insert!(
      struct!(
        %HoursRecord{
          id: Ash.UUIDv7.generate(),
          member_id: user.member.id,
          blob_id: blob.id,
          month: 4,
          year: 2025,
          number_of_hours: 160,
          submission_status: :submitted,
          change_requested_at: DateTime.utc_now(),
          change_request_kind: :cancellation,
          change_request_reason: "Wrong hours",
          organization_id: user.member.organization_id
        },
        attrs
      ),
      skip_organization_id: true
    )
  end

  describe "submitted check" do
    test "by_month returns the record when submitted", %{user: user, scope: scope} do
      blob = seed_blob!(user.member.organization_id)

      Repo.insert!(
        %HoursRecord{
          id: Ash.UUIDv7.generate(),
          member_id: user.member.id,
          blob_id: blob.id,
          month: 2,
          year: 2025,
          number_of_hours: 160,
          organization_id: user.member.organization_id
        },
        skip_organization_id: true
      )

      {:ok, record} = HoursRecord.by_month(user.member.id, 2, 2025, scope: scope)
      assert record.month == 2
      assert record.year == 2025
    end
  end
end
