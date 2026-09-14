defmodule Firmowid.Ash.Delegations.DelegationTest do
  @moduledoc false

  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Ash.Error.Forbidden
  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Delegations.DelegationExpense
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

  test "assigns sequential references for a user and billing month", %{
    employee_scope: employee_scope
  } do
    first = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)
    second = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    assert first.reference =~ ~r/^U[0-9A-F-]+-2026-09-1$/
    assert second.reference =~ ~r/^U[0-9A-F-]+-2026-09-2$/
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

  test "cannot complete a delegation with an incomplete uploaded expense", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)
    {:ok, delegation} = Delegations.approve_delegation(delegation.id, scope: admin_scope)

    _expense =
      Ash.Seed.seed!(DelegationExpense, %{
        delegation_id: delegation.id,
        organization_id: employee_scope.actor.organization_id,
        blob_id: seed_blob(employee_scope.actor).id,
        kind: :other,
        original_filename: "rachunek.pdf",
        document_number: "RACH/1",
        expense_amount: Money.new(:PLN, 0),
        details: %{type: "other", description: "Parking"}
      })

    assert {:error, _} = Delegations.complete_delegation(delegation.id, scope: employee_scope)
  end

  test "requires a reason when final expense dates extend the delegation", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)
    {:ok, delegation} = Delegations.approve_delegation(delegation.id, scope: admin_scope)

    expense =
      seed_expense(delegation, employee_scope.actor,
        arrival_date: ~D[2026-09-10],
        departure_date: ~D[2026-09-11]
      )

    assert {:error, _} =
             Delegations.complete_delegation(
               delegation.id,
               %{
                 expenses: [
                   %{
                     id: expense.id,
                     details: %{
                       type: "accommodation",
                       locality: "Kraków",
                       arrival_date: ~D[2026-09-10],
                       departure_date: ~D[2026-09-12]
                     }
                   }
                 ]
               },
               scope: employee_scope
             )
  end

  test "cannot complete an expense after its delegation is complete", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)
    {:ok, delegation} = Delegations.approve_delegation(delegation.id, scope: admin_scope)

    expense =
      seed_expense(delegation, employee_scope.actor,
        arrival_date: ~D[2026-09-10],
        departure_date: ~D[2026-09-11]
      )

    assert {:ok, _} = Delegations.complete_delegation(delegation.id, scope: employee_scope)

    assert {:error, %Forbidden{}} =
             Delegations.complete_expense(expense, %{document_number: "NOWY/1"}, scope: employee_scope)
  end

  test "rejects negative and non-PLN foreign currency settlements", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)
    {:ok, delegation} = Delegations.approve_delegation(delegation.id, scope: admin_scope)
    expense = seed_foreign_expense(delegation, employee_scope.actor)

    for settlement_amount <- [Money.new(:PLN, -1), Money.new(:EUR, 100)] do
      assert {:error, _} =
               Delegations.complete_expense(
                 expense,
                 %{settlement_method: :statement, settlement_amount: settlement_amount},
                 scope: employee_scope
               )
    end
  end

  test "rejects transport details with a reversed trip", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

    assert {:error, _} =
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
             }
             |> Map.merge(upload_attrs())
             |> Delegations.create_expense(scope: employee_scope)
  end

  test "detects a delegation end date from a return ticket", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

    assert {:ok, _expense} =
             %{
               delegation_id: delegation.id,
               kind: :transport,
               original_filename: "bilet-powrotny.pdf",
               document_number: "POW/1",
               details: %{
                 type: "transport",
                 trips: [
                   %{
                     departure_city: "Kraków",
                     departure_datetime: ~U[2026-09-11 16:00:00Z],
                     arrival_city: "Warszawa",
                     arrival_datetime: ~U[2026-09-12 19:00:00Z]
                   }
                 ]
               }
             }
             |> Map.merge(upload_attrs())
             |> Delegations.create_expense(scope: employee_scope)

    detected_delegation =
      Delegations.get_delegation!(delegation.id, scope: employee_scope)

    assert detected_delegation.detected_start_date == nil
    assert detected_delegation.detected_end_date == ~D[2026-09-12]
  end

  test "clears detected dates after correcting and deleting evidence", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

    expense =
      seed_expense(delegation, employee_scope.actor,
        arrival_date: ~D[2026-09-10],
        departure_date: ~D[2026-09-12]
      )

    {:ok, expense} =
      Delegations.update_expense(expense, %{document_number: "REZ/2"}, scope: employee_scope)

    assert Delegations.get_delegation!(delegation.id, scope: employee_scope).detected_end_date ==
             ~D[2026-09-12]

    assert {:ok, corrected_expense} =
             Delegations.update_expense(
               expense,
               %{
                 details: %{
                   type: "accommodation",
                   locality: "Kraków",
                   arrival_date: ~D[2026-09-10],
                   departure_date: ~D[2026-09-11]
                 }
               },
               scope: employee_scope
             )

    assert Delegations.get_delegation!(delegation.id, scope: employee_scope).detected_end_date ==
             nil

    out_of_range_expense =
      seed_expense(delegation, employee_scope.actor,
        arrival_date: ~D[2026-09-10],
        departure_date: ~D[2026-09-12]
      )

    {:ok, out_of_range_expense} =
      Delegations.update_expense(out_of_range_expense, %{document_number: "REZ/3"}, scope: employee_scope)

    assert Delegations.get_delegation!(delegation.id, scope: employee_scope).detected_end_date ==
             ~D[2026-09-12]

    assert :ok = Delegations.destroy_expense(out_of_range_expense, scope: employee_scope)

    assert Delegations.get_delegation!(delegation.id, scope: employee_scope).detected_end_date ==
             nil

    assert corrected_expense.id == expense.id
  end

  test "requires an uploaded expense document", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

    assert {:error, _error} =
             Delegations.create_expense(
               %{
                 delegation_id: delegation.id,
                 kind: :other,
                 original_filename: "rachunek.pdf",
                 details: %{type: "other", description: "Parking"}
               },
               scope: employee_scope
             )
  end

  defp seed_expense(delegation, user, details) do
    blob =
      Ash.Seed.seed!(Blob, %{
        blob_path: "/test/delegations/#{System.unique_integer([:positive])}.pdf",
        blob_checksum: "delegation-#{System.unique_integer([:positive])}",
        original_filename: "rachunek.pdf",
        organization_id: user.organization_id
      })

    Ash.Seed.seed!(DelegationExpense, %{
      delegation_id: delegation.id,
      organization_id: user.organization_id,
      blob_id: blob.id,
      kind: :accommodation,
      original_filename: "rachunek.pdf",
      document_number: "REZ/1",
      expense_amount: Money.new(:PLN, 100),
      details: Map.merge(%{type: "accommodation", locality: "Kraków"}, Map.new(details))
    })
  end

  defp seed_foreign_expense(delegation, user) do
    statement_blob =
      Ash.Seed.seed!(Blob, %{
        blob_path: "/test/delegations/statement-#{System.unique_integer([:positive])}.pdf",
        blob_checksum: "statement-#{System.unique_integer([:positive])}",
        original_filename: "wyciag.pdf",
        organization_id: user.organization_id
      })

    Ash.Seed.seed!(DelegationExpense, %{
      delegation_id: delegation.id,
      organization_id: user.organization_id,
      blob_id: statement_blob.id,
      statement_blob_id: statement_blob.id,
      kind: :other,
      original_filename: "rachunek.pdf",
      document_number: "RACH/1",
      expense_amount: Money.new(:EUR, 100),
      details: %{type: "other", description: "Parking"}
    })
  end

  defp seed_blob(user) do
    Ash.Seed.seed!(Blob, %{
      blob_path: "/test/delegations/#{System.unique_integer([:positive])}.pdf",
      blob_checksum: "delegation-#{System.unique_integer([:positive])}",
      original_filename: "rachunek.pdf",
      organization_id: user.organization_id
    })
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

  defp upload_attrs do
    path = Briefly.create!(extname: ".pdf")
    File.write!(path, "delegation expense")

    %{upload_path: path, content_type: "application/pdf"}
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
