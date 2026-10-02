defmodule Firmowid.Ash.Delegations.DelegationTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Ash.Error.Forbidden
  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Scope

  setup do
    employee = user_fixture()
    admin = admin_fixture(%{organization_id: employee.organization_id})

    %{
      employee_scope: %Scope{actor: employee, tenant: employee.organization_id},
      admin_scope: %Scope{actor: admin, tenant: employee.organization_id}
    }
  end

  test "rejects a negative advance payment amount", %{employee_scope: employee_scope} do
    assert {:error, _error} =
             Delegations.create_delegation(
               delegation_attrs(%{advance_payment_amount: Money.new(:PLN, -1)}),
               scope: employee_scope
             )
  end

  test "only an administrator can approve a delegation", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    assert {:error, %Forbidden{}} =
             Delegations.approve_delegation(delegation.id, scope: employee_scope)

    assert {:ok, approved_delegation} =
             Delegations.approve_delegation(delegation.id, scope: admin_scope)

    assert approved_delegation.status == :in_progress
  end

  defp delegation_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        title: "Spotkanie z klientem",
        billing_month: ~D[2026-09-01],
        destination: "Kraków",
        transport_types: [:railway, :bus],
        purpose: "Spotkanie z klientem",
        advance_payment_amount: Money.new(:PLN, 100),
        start_date: ~D[2026-09-10],
        end_date: ~D[2026-09-11]
      },
      overrides
    )
  end
end
