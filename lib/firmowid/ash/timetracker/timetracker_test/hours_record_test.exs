defmodule Firmowid.Ash.Timetracker.HoursRecordTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Timetracker.Checks.OwnsResource
  alias Firmowid.Ash.Timetracker.HoursRecord, as: AshHoursRecord

  setup do
    user = user_fixture()

    scope = %Firmowid.Ash.Scope{
      current_user: user,
      current_tenant: user.organization_id
    }

    %{user: user, scope: scope}
  end

  describe "by_month/4" do
    test "returns record for a given user and month", %{user: user, scope: scope} do
      # Insert directly — the create action requires blob upload infrastructure
      Repo.insert!(
        %AshHoursRecord{
          id: Ash.UUIDv7.generate(),
          user_id: user.id,
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

  describe "ownership policy" do
    test "OwnsResource check rejects another user's id", %{user: user} do
      other_user = user_fixture(%{organization_id: user.organization_id})

      # Test the check module directly since the :create action has an inline
      # change that does file I/O (Blobs.create_blob) which runs during
      # for_create, before policies can be evaluated.
      changeset =
        AshHoursRecord
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:user_id, other_user.id)

      context = %{subject: changeset}
      refute OwnsResource.match?(user, context, [])
    end

    test "OwnsResource check accepts own user_id", %{user: user} do
      changeset =
        AshHoursRecord
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:user_id, user.id)

      context = %{subject: changeset}
      assert OwnsResource.match?(user, context, [])
    end

    test "OwnsResource check rejects nil actor" do
      changeset =
        AshHoursRecord
        |> Ash.Changeset.new()
        |> Ash.Changeset.change_attribute(:user_id, Ash.UUIDv7.generate())

      context = %{subject: changeset}
      refute OwnsResource.match?(nil, context, [])
    end
  end

  describe "submitted check" do
    test "by_month returns the record when submitted", %{user: user, scope: scope} do
      Repo.insert!(
        %AshHoursRecord{
          id: Ash.UUIDv7.generate(),
          user_id: user.id,
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
