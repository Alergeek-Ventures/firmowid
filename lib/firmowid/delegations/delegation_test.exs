defmodule Firmowid.Delegations.DelegationTest do
  @moduledoc false

  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Ash.Error.Forbidden
  alias Ecto.Adapters.SQL.Sandbox
  alias Firmowid.Blobs.Blob
  alias Firmowid.Delegations
  alias Firmowid.Delegations.DelegationExpense
  alias Firmowid.Delegations.DelegationExpense.Trip
  alias Firmowid.Scope

  setup do
    employee = user_fixture(%{name: "Kira Voss"})
    admin = admin_fixture(%{organization_id: employee.member.organization_id})

    %{
      employee_scope: %Scope{actor: employee, tenant: employee.member.organization_id},
      admin_scope: %Scope{actor: admin, tenant: employee.member.organization_id}
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

    assert first.reference == "KV-2026-09-1"
    assert second.reference == "KV-2026-09-2"
  end

  test "shares a calendar-month reference sequence between employees with the same initials", %{
    employee_scope: employee_scope
  } do
    employee = employee_scope.actor

    second_employee = user_in_org_fixture(employee.member.organization_id, %{name: "Kamil Voss"})

    second_scope = %Scope{actor: second_employee, tenant: employee.member.organization_id}

    first =
      Delegations.create_delegation!(delegation_attrs(%{billing_month: ~D[2026-09-01]}),
        scope: employee_scope
      )

    second =
      Delegations.create_delegation!(delegation_attrs(%{billing_month: ~D[2026-09-30]}),
        scope: second_scope
      )

    assert first.reference == "KV-2026-09-1"
    assert second.reference == "KV-2026-09-2"
  end

  test "uses the same reference namespace independently in each organization", %{
    employee_scope: employee_scope
  } do
    other_employee = user_fixture(%{name: "Kira Voss"})

    other_scope = %Scope{actor: other_employee, tenant: other_employee.member.organization_id}

    first = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)
    second = Delegations.create_delegation!(delegation_attrs(), scope: other_scope)

    assert first.reference == "KV-2026-09-1"
    assert second.reference == "KV-2026-09-1"
  end

  test "uses a stable fallback prefix for a blank employee name", %{
    employee_scope: employee_scope
  } do
    actor = employee_scope.actor
    employee = %{actor | member: %{actor.member | name: "   "}}
    scope = %Scope{actor: employee, tenant: employee.member.organization_id}

    delegation = Delegations.create_delegation!(delegation_attrs(), scope: scope)

    assert delegation.reference == "U#{String.upcase(String.slice(employee.id, 0, 8))}-2026-09-1"
  end

  test "assigns unique consecutive references to concurrent submissions", %{
    employee_scope: employee_scope
  } do
    parent = self()

    references =
      1..8
      |> Task.async_stream(
        fn _ ->
          :ok = Sandbox.allow(Repo, parent, self())
          Delegations.create_delegation!(delegation_attrs(), scope: employee_scope).reference
        end,
        max_concurrency: 8,
        ordered: false,
        timeout: 15_000
      )
      |> Enum.map(fn {:ok, reference} -> reference end)

    assert Enum.sort(references) == Enum.map(1..8, &"KV-2026-09-#{&1}")
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

  test "draft saving cannot update another delegation's expenses and rolls back the whole save",
       %{
         employee_scope: employee_scope,
         admin_scope: admin_scope
       } do
    first = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)
    first = Delegations.approve_delegation!(first.id, approval_attrs(), scope: admin_scope)
    second = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)
    second = Delegations.approve_delegation!(second.id, approval_attrs(), scope: admin_scope)
    own = seed_transport_expense(first, employee_scope.actor, %{})
    other = seed_transport_expense(second, employee_scope.actor, %{})

    assert {:error, _} =
             Delegations.save_delegation_draft(
               first.id,
               %{
                 date_change_reason: "Nie powinno się zapisać",
                 expenses: [
                   %{id: own.id, document_number: "CHANGED"},
                   %{id: other.id, document_number: "FORGED"}
                 ]
               },
               scope: employee_scope
             )

    assert Delegations.get_expense!(own.id, scope: employee_scope).document_number == "TICKET/1"
    assert Delegations.get_expense!(other.id, scope: employee_scope).document_number == "TICKET/1"
    assert Delegations.get_delegation!(first.id, scope: employee_scope).date_change_reason == nil

    stranger = user_in_org_fixture(employee_scope.tenant)

    assert {:error, _} =
             Delegations.save_delegation_draft(first.id, %{date_change_reason: "FORGED"},
               scope: %Scope{actor: stranger, tenant: employee_scope.tenant}
             )

    outsider = user_fixture()

    assert {:error, _} =
             Delegations.save_delegation_draft(first.id, %{date_change_reason: "FORGED"},
               scope: %Scope{actor: outsider, tenant: outsider.member.organization_id}
             )
  end

  test "cannot prepare an empty settlement", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

    assert {:error, _} = Delegations.prepare_settlement(delegation.id, scope: employee_scope)
  end

  test "cannot prepare a delegation with an incomplete uploaded expense", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

    _expense =
      Ash.Seed.seed!(DelegationExpense, %{
        delegation_id: delegation.id,
        organization_id: employee_scope.actor.member.organization_id,
        blob_id: seed_blob(employee_scope.actor).id,
        kind: :other,
        original_filename: "rachunek.pdf",
        document_number: "RACH/1",
        expense_amount: Money.new(:PLN, 0),
        details: %{type: "other", description: "Parking"}
      })

    assert {:error, _} = Delegations.prepare_settlement(delegation.id, scope: employee_scope)
  end

  test "requires a reason when final expense dates extend the delegation", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

    expense =
      seed_expense(delegation, employee_scope.actor,
        arrival_date: ~D[2026-09-10],
        departure_date: ~D[2026-09-11]
      )

    assert {:error, _} =
             Delegations.prepare_settlement(
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

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

    expense =
      seed_expense(delegation, employee_scope.actor,
        arrival_date: ~D[2026-09-10],
        departure_date: ~D[2026-09-11]
      )

    assert {:ok, _} = Delegations.prepare_settlement(delegation.id, scope: employee_scope)

    assert {:error, %Forbidden{}} =
             Delegations.complete_expense(expense, %{document_number: "NOWY/1"}, scope: employee_scope)
  end

  test "rejects negative and non-PLN foreign currency settlements", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

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

  test "detects local midnight evidence on update and completion instead of the UTC date", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    delegation =
      Delegations.approve_delegation!(delegation.id, approval_attrs(), scope: admin_scope)

    expense =
      seed_transport_expense(delegation, employee_scope.actor, %{
        departure_local_datetime: ~N[2026-09-11 23:30:00],
        arrival_local_datetime: ~N[2026-09-12 00:30:00],
        departure_datetime: ~U[2026-09-11 21:30:00Z],
        arrival_datetime: ~U[2026-09-11 22:30:00Z]
      })

    assert {:ok, _expense} =
             Delegations.update_expense(expense, %{document_number: "TICKET/2"}, scope: employee_scope)

    assert Delegations.get_delegation!(delegation.id, scope: employee_scope).detected_end_date ==
             ~D[2026-09-12]

    assert {:error, _} = Delegations.prepare_settlement(delegation.id, scope: employee_scope)

    assert {:ok, completed} =
             Delegations.prepare_settlement(
               delegation.id,
               %{date_change_reason: "Powrót po północy"},
               scope: employee_scope
             )

    assert completed.detected_end_date == ~D[2026-09-12]
  end

  test "completes local-only DST clocks and flights with earlier local arrival", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    for times <- [
          %{
            departure_local_datetime: ~N[2026-03-29 02:30:00],
            arrival_local_datetime: ~N[2026-03-29 03:30:00]
          },
          %{
            departure_local_datetime: ~N[2026-10-25 02:30:00],
            arrival_local_datetime: ~N[2026-10-25 02:15:00]
          },
          %{
            departure_datetime: ~U[2026-09-10 09:30:00Z],
            arrival_datetime: ~U[2026-09-10 12:30:00Z]
          },
          %{
            departure_local_datetime: ~N[2026-09-10 12:00:00],
            arrival_local_datetime: ~N[2026-09-10 11:00:00],
            departure_datetime: ~U[2026-09-10 10:00:00Z],
            arrival_datetime: ~U[2026-09-10 15:00:00Z]
          }
        ] do
      delegation =
        Delegations.create_delegation!(
          delegation_attrs(%{start_date: ~D[2026-03-01], end_date: ~D[2026-10-31]}),
          scope: employee_scope
        )

      delegation =
        Delegations.approve_delegation!(delegation.id, approval_attrs(), scope: admin_scope)

      expense = seed_transport_expense(delegation, employee_scope.actor, times)
      original_trip = hd(expense.details.value.trips)
      assert {:ok, _} = Delegations.prepare_settlement(delegation.id, scope: employee_scope)
      stored_expense = Delegations.get_expense!(expense.id, scope: employee_scope)
      assert hd(stored_expense.details.value.trips) == original_trip
    end
  end

  test "uses legacy UTC clock components without converting or populating local fields" do
    assert {:ok, trip} =
             Ash.Type.cast_input(Trip, %{
               departure_datetime: "2026-09-11T23:30:00Z",
               arrival_datetime: "2026-09-12T00:30:00Z"
             })

    assert trip.departure_local_datetime == nil
    assert trip.arrival_local_datetime == nil
    assert Trip.local_datetime(trip, :departure) == ~N[2026-09-11 23:30:00]
    assert Trip.local_datetime(trip, :arrival) == ~N[2026-09-12 00:30:00]
    assert Trip.evidence_dates(trip) == [~D[2026-09-11], ~D[2026-09-12]]
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

  test "prepares, reopens, and submits a settlement through the employee workflow", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

    _expense =
      seed_expense(delegation, employee_scope.actor,
        arrival_date: ~D[2026-09-10],
        departure_date: ~D[2026-09-11]
      )

    assert {:ok, prepared} =
             Delegations.prepare_settlement(delegation.id, scope: employee_scope)

    assert prepared.status == :awaiting_signature
    assert prepared.settlement_sequence == 1
    assert prepared.settlement_year == Date.utc_today().year
    assert %DateTime{} = prepared.settlement_prepared_at

    assert {:ok, reopened} = Delegations.edit_settlement(prepared.id, scope: employee_scope)
    assert reopened.status == :in_progress

    assert {:ok, prepared_again} =
             Delegations.prepare_settlement(reopened.id, scope: employee_scope)

    assert prepared_again.settlement_sequence == prepared.settlement_sequence
    assert prepared_again.status == :awaiting_signature

    signed_path = Briefly.create!(extname: ".pdf")
    File.write!(signed_path, "%PDF-1.4 signed settlement")

    assert {:ok, submitted} =
             Delegations.submit_for_review(
               prepared_again.id,
               %{
                 upload_path: signed_path,
                 content_type: "application/pdf",
                 original_filename: "podpisane-rozliczenie.pdf"
               },
               scope: employee_scope
             )

    assert submitted.status == :submitted
    assert submitted.signed_settlement_blob_id
    assert %DateTime{} = submitted.submitted_at

    assert {:error, _error} =
             Delegations.submit_for_review(
               submitted.id,
               %{
                 upload_path: signed_path,
                 content_type: "application/pdf",
                 original_filename: "podpisane-rozliczenie.pdf"
               },
               scope: employee_scope
             )
  end

  test "only the owner can prepare or submit a settlement and only with a PDF", %{
    employee_scope: employee_scope,
    admin_scope: admin_scope
  } do
    delegation = Delegations.create_delegation!(delegation_attrs(), scope: employee_scope)

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id, approval_attrs(), scope: admin_scope)

    _expense =
      seed_expense(delegation, employee_scope.actor,
        arrival_date: ~D[2026-09-10],
        departure_date: ~D[2026-09-11]
      )

    other_employee = user_in_org_fixture(employee_scope.tenant)
    other_scope = %Scope{actor: other_employee, tenant: employee_scope.tenant}

    assert {:error, %Forbidden{}} =
             Delegations.prepare_settlement(delegation.id, scope: other_scope)

    prepared = Delegations.prepare_settlement!(delegation.id, scope: employee_scope)
    invalid_path = Briefly.create!(extname: ".txt")
    File.write!(invalid_path, "not a pdf")

    assert {:error, _error} =
             Delegations.submit_for_review(
               prepared.id,
               %{
                 upload_path: invalid_path,
                 content_type: "text/plain",
                 original_filename: "rozliczenie.txt"
               },
               scope: employee_scope
             )

    assert {:error, %Forbidden{}} =
             Delegations.submit_for_review(
               prepared.id,
               %{
                 upload_path: invalid_path,
                 content_type: "application/pdf",
                 original_filename: "rozliczenie.pdf"
               },
               scope: other_scope
             )
  end

  defp seed_transport_expense(delegation, user, times) do
    Ash.Seed.seed!(DelegationExpense, %{
      delegation_id: delegation.id,
      organization_id: user.member.organization_id,
      blob_id: seed_blob(user).id,
      kind: :transport,
      original_filename: "bilet.pdf",
      document_number: "TICKET/1",
      expense_amount: Money.new(:PLN, 100),
      details: %{
        type: "transport",
        trips: [Map.merge(%{departure_city: "Warszawa", arrival_city: "Nowy Jork"}, times)]
      }
    })
  end

  defp seed_expense(delegation, user, details) do
    blob =
      Ash.Seed.seed!(Blob, %{
        blob_path: "/test/delegations/#{System.unique_integer([:positive])}.pdf",
        blob_checksum: "delegation-#{System.unique_integer([:positive])}",
        original_filename: "rachunek.pdf",
        organization_id: user.member.organization_id
      })

    Ash.Seed.seed!(DelegationExpense, %{
      delegation_id: delegation.id,
      organization_id: user.member.organization_id,
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
        organization_id: user.member.organization_id
      })

    Ash.Seed.seed!(DelegationExpense, %{
      delegation_id: delegation.id,
      organization_id: user.member.organization_id,
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
      organization_id: user.member.organization_id
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
