defmodule Firmowid.Ash.Timetracker.LeaveRequestTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker
  alias Firmowid.Ash.Timetracker.LeaveRequest

  setup do
    user = user_fixture()
    admin = admin_fixture(%{organization_id: user.organization_id})

    employee_scope = %Scope{actor: user, tenant: user.organization_id}
    admin_scope = %Scope{actor: admin, tenant: user.organization_id}

    %{
      user: user,
      admin: admin,
      employee_scope: employee_scope,
      admin_scope: admin_scope
    }
  end

  defp today, do: Date.utc_today()
  defp days_from_today(n), do: Date.add(today(), n)

  defp create_request!(scope, attrs) do
    attrs =
      Map.merge(
        %{
          starts_on: days_from_today(10),
          ends_on: days_from_today(12),
          reason: :rest
        },
        attrs
      )

    Timetracker.create_leave_request!(attrs, scope: scope)
  end

  describe "overlap prevention on create" do
    test "rejects create that overlaps an accepted request", %{
      employee_scope: employee_scope,
      admin_scope: admin_scope
    } do
      accepted =
        create_request!(employee_scope, %{
          starts_on: days_from_today(20),
          ends_on: days_from_today(25),
          reason: :rest
        })

      assert {:ok, _} = Timetracker.accept_leave_request(accepted.id, scope: admin_scope)

      assert {:error, _} =
               Timetracker.create_leave_request(
                 %{
                   starts_on: days_from_today(23),
                   ends_on: days_from_today(27),
                   reason: :other
                 },
                 scope: employee_scope
               )
    end

    test "rejects create that overlaps a pending request", %{employee_scope: employee_scope} do
      create_request!(employee_scope, %{
        starts_on: days_from_today(20),
        ends_on: days_from_today(25),
        reason: :rest
      })

      assert {:error, _} =
               Timetracker.create_leave_request(
                 %{
                   starts_on: days_from_today(23),
                   ends_on: days_from_today(27),
                   reason: :other
                 },
                 scope: employee_scope
               )
    end

    test "allows adjacent ranges that do not share days", %{
      employee_scope: employee_scope,
      admin_scope: admin_scope
    } do
      accepted =
        create_request!(employee_scope, %{
          starts_on: days_from_today(20),
          ends_on: days_from_today(22),
          reason: :rest
        })

      assert {:ok, _} = Timetracker.accept_leave_request(accepted.id, scope: admin_scope)

      assert {:ok, _} =
               Timetracker.create_leave_request(
                 %{
                   starts_on: days_from_today(23),
                   ends_on: days_from_today(24),
                   reason: :other
                 },
                 scope: employee_scope
               )
    end

    test "allows overlapping a declined request", %{
      employee_scope: employee_scope,
      admin_scope: admin_scope
    } do
      declined =
        create_request!(employee_scope, %{
          starts_on: days_from_today(20),
          ends_on: days_from_today(25),
          reason: :rest
        })

      assert {:ok, _} = Timetracker.decline_leave_request(declined.id, scope: admin_scope)

      assert {:ok, _} =
               Timetracker.create_leave_request(
                 %{
                   starts_on: days_from_today(23),
                   ends_on: days_from_today(27),
                   reason: :other
                 },
                 scope: employee_scope
               )
    end
  end

  describe "accepted_leave_days_for_year" do
    test "clamps requests that span year boundaries", %{
      user: user,
      admin_scope: admin_scope
    } do
      year = today().year
      year_start = Date.new!(year, 1, 1)
      prev_year_end = Date.add(year_start, -2)

      # Seed across year boundary - bypass create validations (starts_on >= today).
      Ash.Seed.seed!(LeaveRequest, %{
        id: Ash.UUIDv7.generate(),
        user_id: user.id,
        organization_id: user.organization_id,
        starts_on: prev_year_end,
        ends_on: Date.add(year_start, 2),
        category: :absence,
        reason: :rest,
        status: :accepted
      })

      loaded =
        Ash.load!(user, [accepted_leave_days_for_year: %{year: year}], scope: admin_scope)

      # Jan 1..Jan 3 inclusive = 3 days in the selected year
      assert loaded.accepted_leave_days_for_year == 3
    end
  end
end
