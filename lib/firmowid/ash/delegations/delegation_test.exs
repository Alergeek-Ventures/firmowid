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

  test "rejects a negative expected cost", %{employee_scope: employee_scope} do
    assert {:error, _error} =
             Delegations.create_delegation(
               delegation_attrs(%{expected_cost: Money.new(:PLN, -1)}),
               scope: employee_scope
             )
  end

  test "only an administrator can approve a delegation", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)
    approval_attrs = approval_attrs()

    assert {:error, %Forbidden{}} =
             Delegations.approve_delegation(delegation.id, approval_attrs, scope: employee_scope)

    assert {:ok, approved_delegation} =
             Delegations.approve_delegation(delegation.id, approval_attrs, scope: admin_scope)

    assert approved_delegation.status == :in_progress
    assert approved_delegation.advance_amount == Money.new(:PLN, 50)
    assert approved_delegation.signed_command_blob_id
  end

  test "cannot complete an empty settlement", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

    assert {:error, _} = Delegations.complete_delegation(delegation.id, scope: employee_scope)
  end

  test "rejects transport details with a reversed trip", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

    assert {:error, _} =
             Delegations.create_expense(
               %{
                 delegation_id: delegation.id,
                 kind: :transport,
                 original_filename: "bilet.pdf",
                 details: %{
                   type: "transport",
                   trips: [
                     %{
                       departure_city: "Warszawa",
                       departure_datetime: ~U[2026-08-10 12:00:00Z],
                       arrival_city: "Kraków",
                       arrival_datetime: ~U[2026-08-10 10:00:00Z]
                     }
                   ]
                 }
               },
               scope: employee_scope
             )
  end

  defp delegation_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        title: "Spotkanie z klientem",
        billing_month: ~D[2026-09-01],
        destination: "Kraków",
        transport_types: [:railway, :bus],
        purpose: "Spotkanie z klientem",
        expected_cost: Money.new(:PLN, 100),
        start_date: ~D[2026-09-10],
        end_date: ~D[2026-09-11]
      },
      overrides
    )
  end

  defp approval_attrs do
    path = Briefly.create!(extname: ".pdf")
    File.write!(path, "%PDF-1.4 signed command")

    %{
      advance_amount: Money.new(:PLN, 50),
      signed_command_filename: "polecenie.pdf",
      upload_path: path,
      content_type: "application/pdf"
    }
  end
end
