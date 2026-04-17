defmodule Firmowid.Ash.Timetracker.HoursRecordTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord

  setup do
    user = user_fixture()

    scope = %Firmowid.Ash.Scope{
      actor: user,
      tenant: user.organization_id
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
      blob = seed_blob!(user.organization_id)

      # Insert directly — the create action requires blob upload infrastructure
      Repo.insert!(
        %AshHoursRecord{
          id: Ash.UUIDv7.generate(),
          user_id: user.id,
          blob_id: blob.id,
          month: 3,
          year: 2025,
          number_of_hours: 160,
          organization_id: user.organization_id
        },
        skip_organization_id: true
      )

      {:ok, record} = AshHoursRecord.by_month(user.id, 3, 2025, scope: scope)
      assert record.month == 3
      assert record.year == 2025
    end

    test "returns nil when no record exists", %{user: user, scope: scope} do
      {:ok, result} =
        AshHoursRecord.by_month(user.id, 6, 2025,
          scope: scope,
          not_found_error?: false
        )

      assert is_nil(result)
    end
  end

  describe "submitted check" do
    test "by_month returns the record when submitted", %{user: user, scope: scope} do
      blob = seed_blob!(user.organization_id)

      Repo.insert!(
        %AshHoursRecord{
          id: Ash.UUIDv7.generate(),
          user_id: user.id,
          blob_id: blob.id,
          month: 2,
          year: 2025,
          number_of_hours: 160,
          organization_id: user.organization_id
        },
        skip_organization_id: true
      )

      {:ok, record} = AshHoursRecord.by_month(user.id, 2, 2025, scope: scope)
      assert record.month == 2
      assert record.year == 2025
    end
  end
end
