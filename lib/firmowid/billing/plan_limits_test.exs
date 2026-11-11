defmodule Firmowid.Billing.PlanLimitsTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures
  import Swoosh.TestAssertions

  alias Ash.Error.Forbidden
  alias Firmowid.Billing.PlanLimits
  alias Firmowid.Core
  alias Firmowid.Finances
  alias Firmowid.Scope
  alias Firmowid.SystemActor
  alias Firmowid.Test.Support.AuthEmailHelpers
  alias Firmowid.Timetracker.Project

  # The Free plan includes 2 users, 1 bank and 3 projects.

  describe "check/2" do
    test "gives a free month the first time, decides today later and ends once usage fits" do
      admin = admin_fixture()
      org_id = admin.member.organization_id
      employee(org_id, ~U[2026-01-02 10:00:00Z])
      newest = employee(org_id, ~U[2026-01-03 10:00:00Z])
      AuthEmailHelpers.drain_sent_emails()

      assert {:ok, deciding} = PlanLimits.check(organization(org_id), ~D[2026-11-11])
      assert deciding.plan_limit_decision_on == ~D[2026-12-01]
      assert deciding.plan_limit_free_month_used_at
      assert_email_sent(to: [to_string(admin.email)])

      {:ok, _member} = Core.archive_member(newest.member, scope: Scope.new!(admin, org_id))

      assert {:ok, within} = PlanLimits.check(deciding, ~D[2026-11-12])
      assert within.plan_limit_decision_on == nil
      assert within.plan_limit_free_month_used_at == deciding.plan_limit_free_month_used_at

      employee(org_id, ~U[2026-01-04 10:00:00Z])
      AuthEmailHelpers.drain_sent_emails()

      assert {:ok, again} = PlanLimits.check(within, ~D[2026-11-20])
      assert again.plan_limit_decision_on == ~D[2026-11-20]
      assert_email_sent(to: [to_string(admin.email)])
    end

    test "switches off the newest excess a week after the decision day and keeps the owner" do
      %{admin: admin, org_id: org_id} = above_free = above_free_plan()
      deciding = decide_on(org_id, ~D[2026-11-01])

      assert {:ok, waiting} = PlanLimits.check(deciding, ~D[2026-11-07])
      assert waiting.plan_limit_decision_on == ~D[2026-11-01]
      refute reload(above_free.newer_employee.member).archived_at

      assert {:ok, decided} = PlanLimits.check(waiting, ~D[2026-11-08])
      assert decided.plan_limit_decision_on == nil

      refute reload(admin.member).archived_at
      refute reload(above_free.older_employee.member).archived_at

      assert %{archived_at: %Date{}, suspended_by_plan_at: %DateTime{}} =
               reload(above_free.newer_employee.member)

      assert Enum.all?(above_free.older_bank, &is_nil(reload(&1).suspended_by_plan_at))
      assert reload(above_free.newer_bank).suspended_by_plan_at
      refute reload(above_free.manual_account).suspended_by_plan_at

      assert Enum.all?(above_free.older_projects, &is_nil(reload(&1).archived_at))

      assert %{archived_at: %Date{}, suspended_by_plan_at: %DateTime{}} =
               reload(above_free.newest_project)

      assert_email_sent(to: [to_string(admin.email)])
    end

    test "skips an organization without a plan" do
      admin = admin_fixture()
      org_id = admin.member.organization_id
      employee(org_id, ~U[2026-01-02 10:00:00Z])
      employee(org_id, ~U[2026-01-03 10:00:00Z])
      blocked = Ash.Seed.update!(organization(org_id), %{billing_plan: :no_plan})
      AuthEmailHelpers.drain_sent_emails()

      assert {:ok, %{plan_limit_decision_on: nil}} = PlanLimits.check(blocked, ~D[2026-11-11])
      refute_email_sent()
    end
  end

  describe "keep/3" do
    test "refuses a selection above the plan, then keeps the owner and switches a bank off with all its accounts" do
      %{admin: admin, org_id: org_id} = above_free = above_free_plan()
      deciding = decide_on(org_id, PlanLimits.today())
      scope = Scope.new!(admin, org_id)
      [older_bank_account | _rest] = above_free.older_bank
      projects = Enum.map(above_free.older_projects, & &1.id)

      too_many = %{
        users: [above_free.older_employee.member.id, above_free.newer_employee.member.id],
        bank_institutions: [above_free.newer_bank.institution_id],
        active_projects: projects
      }

      assert {:error, :over_limit} = PlanLimits.keep(deciding, too_many, scope)
      refute reload(above_free.newer_employee.member).archived_at
      refute reload(older_bank_account).suspended_by_plan_at

      # The owner is not among the kept ids and stays anyway.
      kept = %{too_many | users: [above_free.newer_employee.member.id]}

      assert {:ok, %{plan_limit_decision_on: nil}} = PlanLimits.keep(deciding, kept, scope)

      refute reload(admin.member).archived_at
      refute reload(above_free.newer_employee.member).archived_at
      assert reload(above_free.older_employee.member).suspended_by_plan_at

      assert Enum.all?(above_free.older_bank, &reload(&1).suspended_by_plan_at)
      refute reload(above_free.newer_bank).suspended_by_plan_at
      refute reload(above_free.manual_account).suspended_by_plan_at
    end

    test "an account without a known bank is not a bank and blocks nothing" do
      admin = admin_fixture()
      org_id = admin.member.organization_id
      synced_account(org_id, "ONLY_BANK", ~U[2026-01-01 10:00:00Z])
      without_bank = synced_account(org_id, nil, ~U[2026-01-02 10:00:00Z])
      scope = Scope.new!(admin, org_id)

      assert %{bank_institutions: 1} = PlanLimits.usage(organization(org_id))

      assert [%{id: "ONLY_BANK"}] =
               PlanLimits.switched_on(organization(org_id), scope).bank_institutions

      assert {:ok, _organization} = PlanLimits.keep(organization(org_id), %{}, scope)
      refute reload(without_bank).suspended_by_plan_at
    end
  end

  describe "plan_changed/2" do
    test "a higher plan brings back what the plan switched off, not what was archived by hand" do
      %{admin: admin, org_id: org_id} = above_free = above_free_plan()
      scope = Scope.new!(admin, org_id)
      [by_hand_project | _rest] = above_free.older_projects
      {:ok, _member} = Core.archive_member(above_free.older_employee.member, scope: scope)
      {:ok, _project} = Project.archive(by_hand_project, scope: scope)

      deciding = decide_on(org_id, ~D[2026-11-01])
      {:ok, on_free} = PlanLimits.check(deciding, ~D[2026-11-08])
      assert reload(above_free.newer_bank).suspended_by_plan_at

      # Without the hand-archived project the remaining three fit the plan.
      {:ok, by_plan_project} =
        Project.archive(above_free.newest_project, %{by_plan?: true}, scope: scope)

      by_plan_member = plan_archived_employee(org_id)

      assert {:ok, %{plan_limit_decision_on: nil}} =
               Core.update_organization_billing_plan(on_free, %{billing_plan: :firma}, authorize?: false)

      refute reload(above_free.newer_bank).suspended_by_plan_at
      assert %{archived_at: nil, suspended_by_plan_at: nil} = reload(by_plan_project)
      assert %{archived_at: nil, suspended_by_plan_at: nil} = reload(by_plan_member)

      assert reload(above_free.older_employee.member).archived_at
      assert reload(by_hand_project).archived_at
    end

    test "a lower plan brings nothing back and starts no decision" do
      %{org_id: org_id} = above_free = above_free_plan()
      on_firma = Ash.Seed.update!(organization(org_id), %{billing_plan: :firma})

      paused =
        Ash.Seed.update!(above_free.newer_bank, %{suspended_by_plan_at: DateTime.utc_now()})

      AuthEmailHelpers.drain_sent_emails()

      assert {:ok, %{billing_plan: :free, plan_limit_decision_on: nil}} =
               Core.update_organization_billing_plan(on_firma, %{billing_plan: :free}, authorize?: false)

      assert reload(paused).suspended_by_plan_at
      refute_email_sent()
    end
  end

  describe "tenancy" do
    test "the plan limits of one organization cannot touch another organization's data" do
      own_admin = admin_fixture()
      %{actor: actor} = PlanLimits.scope(own_admin.member.organization_id)

      other_admin = admin_fixture()
      other_org_id = other_admin.member.organization_id
      other_employee = user_in_org_fixture(other_org_id)

      other_project =
        Ash.Seed.seed!(Project, %{name: "Other project", organization_id: other_org_id})

      other_account = synced_account(other_org_id, "OTHER_BANK", ~U[2026-01-01 10:00:00Z])
      # As if the tenant were forged: only the policies stand in the way.
      opts = [actor: actor, tenant: other_org_id]

      assert {:error, %Forbidden{}} =
               Core.archive_member(other_employee.member, %{by_plan?: true}, opts)

      assert {:error, %Forbidden{}} = Project.archive(other_project, %{by_plan?: true}, opts)
      assert {:error, %Forbidden{}} = Finances.suspend_bank_account_by_plan(other_account, opts)

      assert {:error, %Forbidden{}} =
               Core.leave_organization(other_employee, other_org_id, actor: actor)

      # Not even for an account that also works in its own organization.
      shared = user_in_org_fixture(other_org_id)

      Core.set_organization!(shared, %{organization_id: actor.org_id, role: :employee},
        actor: %SystemActor{
          org_id: actor.org_id,
          role: :organization_owner_setup,
          user_id: shared.id
        },
        tenant: actor.org_id
      )

      assert {:error, %Forbidden{}} = Core.leave_organization(shared, other_org_id, actor: actor)

      refute reload(other_employee.member).archived_at
      refute reload(other_project).archived_at
      refute reload(other_account).suspended_by_plan_at
    end
  end

  # An owner with two employees, an older bank with two accounts, a newer bank
  # with one, a manually added account and four projects.
  defp above_free_plan do
    admin = admin_fixture()
    org_id = admin.member.organization_id

    above_free = %{
      admin: admin,
      org_id: org_id,
      older_employee: employee(org_id, ~U[2026-01-02 10:00:00Z]),
      newer_employee: employee(org_id, ~U[2026-01-03 10:00:00Z]),
      older_bank: [
        synced_account(org_id, "OLDER_BANK", ~U[2026-01-01 10:00:00Z]),
        synced_account(org_id, "OLDER_BANK", ~U[2026-01-05 10:00:00Z])
      ],
      newer_bank: synced_account(org_id, "NEWER_BANK", ~U[2026-01-03 10:00:00Z]),
      manual_account: bank_account_fixture_for_organization!(org_id),
      older_projects: for(day <- 1..3, do: project(org_id, day)),
      newest_project: project(org_id, 4)
    }

    AuthEmailHelpers.drain_sent_emails()
    above_free
  end

  defp organization(org_id), do: Core.get_organization!(org_id, authorize?: false)

  defp decide_on(org_id, day) do
    Ash.Seed.update!(organization(org_id), %{
      plan_limit_decision_on: day,
      plan_limit_free_month_used_at: DateTime.utc_now()
    })
  end

  defp employee(org_id, joined_at) do
    user = user_in_org_fixture(org_id)
    %{user | member: Ash.Seed.update!(user.member, %{inserted_at: joined_at})}
  end

  defp plan_archived_employee(org_id) do
    Ash.Seed.update!(user_in_org_fixture(org_id).member, %{
      archived_at: Date.utc_today(),
      suspended_by_plan_at: DateTime.utc_now()
    })
  end

  defp synced_account(org_id, institution_id, connected_at) do
    bank_account_fixture_for_organization!(org_id, %{
      gocardless_id: Ash.UUID.generate(),
      institution_id: institution_id,
      institution_name: institution_id,
      inserted_at: connected_at
    })
  end

  defp project(org_id, day) do
    Ash.Seed.seed!(Project, %{
      name: "Project #{day}",
      organization_id: org_id,
      inserted_at: DateTime.new!(Date.new!(2026, 1, day), ~T[10:00:00])
    })
  end

  # Read past the policies: the tests look at what is stored.
  defp reload(record), do: Repo.reload!(record)
end
