defmodule Firmowid.Ash.Billing.LimitsTest do
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Ash.Billing
  alias Firmowid.Ash.Billing.Limits

  # TODO: replace authorize?: false + actor: %{} with system actor once available
  defp opts(org_id), do: [tenant: org_id, authorize?: false, actor: %{}]

  setup do
    user = user_fixture()
    %{organization_id: user.organization_id}
  end

  describe "get_limits" do
    test "returns limits for an organization", %{organization_id: org_id} do
      limits = Billing.get_limits!(opts(org_id))
      assert limits.cost_invoices_used == 0
      assert limits.cost_invoices_limit == 100
    end
  end

  describe "increment_counter" do
    test "increments the usage counter", %{organization_id: org_id} do
      limits = Billing.get_limits!(opts(org_id))
      {:ok, updated} = Billing.increment_counter(limits, %{type: :cost_invoices}, opts(org_id))
      assert updated.cost_invoices_used == 1
    end

    test "increments bank_connections", %{organization_id: org_id} do
      limits = Billing.get_limits!(opts(org_id))
      {:ok, limits} = Billing.increment_counter(limits, %{type: :bank_connections}, opts(org_id))
      {:ok, limits} = Billing.increment_counter(limits, %{type: :bank_connections}, opts(org_id))
      assert limits.bank_connections_used == 2
    end
  end

  describe "decrement_counter" do
    test "decrements the usage counter", %{organization_id: org_id} do
      limits = Billing.get_limits!(opts(org_id))
      {:ok, limits} = Billing.increment_counter(limits, %{type: :sales_invoices}, opts(org_id))
      {:ok, limits} = Billing.increment_counter(limits, %{type: :sales_invoices}, opts(org_id))
      {:ok, limits} = Billing.decrement_counter(limits, %{type: :sales_invoices}, opts(org_id))
      assert limits.sales_invoices_used == 1
    end

    test "does not go below zero", %{organization_id: org_id} do
      limits = Billing.get_limits!(opts(org_id))
      {:ok, limits} = Billing.decrement_counter(limits, %{type: :cost_invoices}, opts(org_id))
      assert limits.cost_invoices_used == 0
    end
  end

  describe "over limit check" do
    test "within limits", %{organization_id: org_id} do
      limits = Billing.get_limits!(opts(org_id))
      assert limits.cost_invoices_used < limits.cost_invoices_limit
    end

    test "at limit", %{organization_id: org_id} do
      set_counter!(org_id, :cost_invoices_used, 100)
      limits = Billing.get_limits!(opts(org_id))
      assert limits.cost_invoices_used >= limits.cost_invoices_limit
    end
  end

  describe "reset_counters (via ResetWorker)" do
    test "resets invoice counters to zero but not bank_connections", %{organization_id: org_id} do
      limits = Billing.get_limits!(opts(org_id))
      {:ok, _} = Billing.increment_counter(limits, %{type: :cost_invoices}, opts(org_id))
      {:ok, _} = Billing.increment_counter(limits, %{type: :sales_invoices}, opts(org_id))
      {:ok, _} = Billing.increment_counter(limits, %{type: :bank_connections}, opts(org_id))

      assert :ok = perform_job(Firmowid.Ash.Billing.ResetWorker, %{})

      limits = Billing.get_limits!(opts(org_id))
      assert limits.cost_invoices_used == 0
      assert limits.sales_invoices_used == 0
      # bank_connections should NOT be reset
      assert limits.bank_connections_used == 1
    end
  end

  # Test-only helper: sets a counter to a specific value via raw Ecto.
  defp set_counter!(org_id, field, value) do
    import Ecto.Query, only: [where: 3]

    Limits
    |> where([l], l.organization_id == ^org_id)
    |> Firmowid.Repo.one!(skip_organization_id: true)
    |> Ecto.Changeset.change(%{field => value})
    |> Firmowid.Repo.update!(skip_organization_id: true)
  end
end
