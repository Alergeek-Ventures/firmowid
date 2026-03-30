defmodule Firmowid.Ash.Billing.LimitsTest do
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Billing.Limits

  # TODO: replace authorize?: false + actor: %{} with system actor once available
  defp opts, do: [authorize?: false, actor: %{}]

  setup do
    user = user_fixture()
    %{organization_id: user.organization_id}
  end

  describe "check" do
    test "returns :ok when within limits", %{organization_id: org_id} do
      assert {:ok, :ok} = Limits.check(org_id, :cost_invoices, opts())
    end

    test "returns warning when at limit", %{organization_id: org_id} do
      set_counter!(org_id, :cost_invoices_used, 100)

      assert {:ok, {:warning, :over_limit, %{used: 100, limit: 100}}} =
               Limits.check(org_id, :cost_invoices, opts())
    end

    test "returns warning when over limit", %{organization_id: org_id} do
      set_counter!(org_id, :sales_invoices_used, 150)

      assert {:ok, {:warning, :over_limit, %{used: 150, limit: 100}}} =
               Limits.check(org_id, :sales_invoices, opts())
    end
  end

  describe "increment" do
    test "increments the usage counter", %{organization_id: org_id} do
      assert {:ok, _} = Limits.increment(org_id, :cost_invoices, opts())

      limits = Limits.by_organization!(org_id, opts())
      assert limits.cost_invoices_used == 1
    end

    test "increments bank_connections", %{organization_id: org_id} do
      assert {:ok, _} = Limits.increment(org_id, :bank_connections, opts())
      assert {:ok, _} = Limits.increment(org_id, :bank_connections, opts())

      limits = Limits.by_organization!(org_id, opts())
      assert limits.bank_connections_used == 2
    end
  end

  describe "decrement" do
    test "decrements the usage counter", %{organization_id: org_id} do
      # First increment, then decrement
      {:ok, _} = Limits.increment(org_id, :sales_invoices, opts())
      {:ok, _} = Limits.increment(org_id, :sales_invoices, opts())
      {:ok, _} = Limits.decrement(org_id, :sales_invoices, opts())

      limits = Limits.by_organization!(org_id, opts())
      assert limits.sales_invoices_used == 1
    end

    test "does not go below zero", %{organization_id: org_id} do
      {:ok, _} = Limits.decrement(org_id, :cost_invoices, opts())

      limits = Limits.by_organization!(org_id, opts())
      assert limits.cost_invoices_used == 0
    end
  end

  describe "usage_summary" do
    test "returns full summary", %{organization_id: org_id} do
      {:ok, _} = Limits.increment(org_id, :cost_invoices, opts())

      {:ok, summary} = Limits.usage_summary(org_id, opts())

      assert summary.cost_invoices == %{used: 1, limit: 100, over_limit: false}
      assert summary.sales_invoices == %{used: 0, limit: 100, over_limit: false}
      assert summary.bank_connections == %{used: 0, limit: 5, over_limit: false}
    end
  end

  describe "reset_monthly_counters" do
    test "resets invoice counters to zero", %{organization_id: org_id} do
      {:ok, _} = Limits.increment(org_id, :cost_invoices, opts())
      {:ok, _} = Limits.increment(org_id, :sales_invoices, opts())
      {:ok, _} = Limits.increment(org_id, :bank_connections, opts())

      {:ok, %{reset_count: count}} = Limits.reset_monthly_counters(opts())
      assert count >= 1

      limits = Limits.by_organization!(org_id, opts())
      assert limits.cost_invoices_used == 0
      assert limits.sales_invoices_used == 0
      # bank_connections should NOT be reset
      assert limits.bank_connections_used == 1
    end
  end

  # Test-only helper: sets a counter to a specific value for test setup.
  # Uses a direct Ecto changeset on the Ash resource (which is also an Ecto
  # schema via AshPostgres) to set arbitrary values without going through
  # Ash actions. This is acceptable in tests for setup purposes only.
  defp set_counter!(org_id, field, value) do
    import Ecto.Query, only: [where: 3]

    Limits
    |> where([l], l.organization_id == ^org_id)
    |> Firmowid.Repo.one!(skip_organization_id: true)
    |> Ecto.Changeset.change(%{field => value})
    |> Firmowid.Repo.update!(skip_organization_id: true)
  end
end
