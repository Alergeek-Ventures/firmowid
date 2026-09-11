defmodule Firmowid.Ash.Delegations.Workers.DelegationEmailWorkerTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Swoosh.TestAssertions

  alias Firmowid.Ash.Delegations.Delegation
  alias Firmowid.Ash.Delegations.Workers.DelegationEmailWorker
  alias Firmowid.Test.Support.AuthEmailHelpers

  test "delivers a delegation notification to organization admins" do
    employee = user_fixture()
    admin = admin_fixture(%{organization_id: employee.organization_id})
    AuthEmailHelpers.drain_sent_emails()

    delegation =
      Ash.Seed.seed!(Delegation, %{
        id: Ash.UUIDv7.generate(),
        organization_id: employee.organization_id,
        user_id: employee.id,
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
             DelegationEmailWorker.perform(%Oban.Job{
               args: %{
                 "delegation_id" => delegation.id,
                 "organization_id" => employee.organization_id
               }
             })

    assert_email_sent(subject: "Nowe zgłoszenie delegacji", to: [to_string(admin.email)])
  end

  test "delivers an approval confirmation to the employee" do
    employee = user_fixture()
    AuthEmailHelpers.drain_sent_emails()

    delegation =
      Ash.Seed.seed!(Delegation, %{
        id: Ash.UUIDv7.generate(),
        organization_id: employee.organization_id,
        user_id: employee.id,
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
             DelegationEmailWorker.perform(%Oban.Job{
               args: %{
                 "delegation_id" => delegation.id,
                 "organization_id" => employee.organization_id,
                 "notification" => "approved"
               }
             })

    assert_email_sent(subject: "Delegacja została zatwierdzona", to: [to_string(employee.email)])
  end
end
