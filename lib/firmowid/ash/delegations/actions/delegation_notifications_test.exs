defmodule Firmowid.Ash.Delegations.Actions.DelegationNotificationsTest do
  use Firmowid.DataCase, async: true

  import Ash.Signals.Test
  import Firmowid.AccountsFixtures
  import Swoosh.TestAssertions

  alias Firmowid.Ash.Delegations.Delegation
  alias Firmowid.Ash.Delegations.Signals
  alias Firmowid.Test.Support.AuthEmailHelpers

  test "delivers a delegation notification to organization admins" do
    employee = user_fixture()
    admin = admin_fixture(%{organization_id: employee.member.organization_id})
    AuthEmailHelpers.drain_sent_emails()

    delegation =
      Ash.Seed.seed!(Delegation, %{
        id: Ash.UUIDv7.generate(),
        organization_id: employee.member.organization_id,
        member_id: employee.member.id,
        reference: "TEST-2026-08-1",
        title: "Spotkanie z klientem",
        billing_month: ~D[2026-08-01],
        destination: "Kraków",
        transport_types: [:railway],
        purpose: "Spotkanie z klientem",
        expected_cost: Money.new(:PLN, 100),
        start_date: ~D[2026-08-10],
        end_date: ~D[2026-08-11],
        status: :pending
      })

    assert :ok =
             react_to_signal(
               Signals,
               :delegation_submitted,
               %{delegation_id: delegation.id, organization_id: employee.member.organization_id},
               only: Delegation,
               inline?: true,
               tenant: employee.member.organization_id
             )

    assert_email_sent(subject: "Nowe zgłoszenie delegacji", to: [to_string(admin.email)])
  end

  test "delivers an approval confirmation to the employee" do
    employee = user_fixture()
    AuthEmailHelpers.drain_sent_emails()

    delegation =
      Ash.Seed.seed!(Delegation, %{
        id: Ash.UUIDv7.generate(),
        organization_id: employee.member.organization_id,
        member_id: employee.member.id,
        reference: "TEST-2026-08-1",
        title: "Spotkanie z klientem",
        billing_month: ~D[2026-08-01],
        destination: "Kraków",
        transport_types: [:railway],
        purpose: "Spotkanie z klientem",
        expected_cost: Money.new(:PLN, 100),
        start_date: ~D[2026-08-10],
        end_date: ~D[2026-08-11],
        status: :in_progress
      })

    assert :ok =
             react_to_signal(
               Signals,
               :delegation_approved,
               %{delegation_id: delegation.id, organization_id: employee.member.organization_id},
               only: Delegation,
               inline?: true,
               tenant: employee.member.organization_id
             )

    assert_email_sent(subject: "Delegacja została zatwierdzona", to: [to_string(employee.email)])
  end
end
