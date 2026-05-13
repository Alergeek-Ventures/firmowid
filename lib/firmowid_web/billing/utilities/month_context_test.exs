defmodule FirmowidWeb.Billing.Utilities.MonthContextTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Billing
  alias Firmowid.Ash.Billing.SnapshotCalculator
  alias Firmowid.Ash.Core
  alias FirmowidWeb.Billing.Utilities.MonthContext

  describe "load/4" do
    test "builds a live preview for the current month" do
      admin = admin_fixture()
      organization = Core.get_organization!(admin.organization_id, authorize?: false)
      current_month = ~D[2026-04-01]

      context =
        MonthContext.load(organization, current_month, admin, current_month: current_month)

      assert context.selected_month == current_month
      assert context.selected_snapshot == nil
      assert context.status == %{kind: :live_preview}
      assert context.usage_source.month == current_month
      assert context.worksheet.selected_plan == organization.billing_plan
    end

    test "uses a persisted snapshot for historical months" do
      admin = admin_fixture()
      organization = Core.get_organization!(admin.organization_id, authorize?: false)
      current_month = ~D[2026-04-01]
      snapshot_month = ~D[2026-03-01]

      {:ok, snapshot} =
        Billing.create_billing_snapshot(
          %{
            month: snapshot_month,
            billing_plan: :firma,
            manual_external_invoices_count: 17,
            synced_bank_accounts_count: 5,
            active_non_owner_users_count: 3,
            frozen_at: ~U[2026-04-02 09:30:00Z]
          },
          scope: SnapshotCalculator.org_scope(organization.id)
        )

      context =
        MonthContext.load(organization, snapshot_month, admin,
          current_month: current_month,
          snapshots: [snapshot]
        )

      assert context.selected_month == snapshot_month
      assert context.selected_snapshot.id == snapshot.id
      assert context.status == %{kind: :snapshot, frozen_at: snapshot.frozen_at}
      assert context.usage_source.id == snapshot.id
      assert context.worksheet.selected_plan == :firma
      assert usage_row(context.worksheet, :manual_external_invoices).count == 17
    end
  end

  defp usage_row(worksheet, key) do
    Enum.find(worksheet.usage_rows, &(&1.key == key))
  end
end
