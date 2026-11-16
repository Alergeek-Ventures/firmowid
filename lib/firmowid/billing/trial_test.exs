defmodule Firmowid.Billing.TrialTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias Firmowid.Billing.Month
  alias Firmowid.Billing.Subscription
  alias Firmowid.BillingFixtures
  alias Firmowid.Core
  alias Firmowid.Core.Organization
  alias Firmowid.Repo
  alias Firmowid.Scope

  setup do
    admin = admin_fixture()
    org_id = admin.member.organization_id
    scope = %Scope{actor: %{admin | system_role: :superuser}, tenant: org_id}

    %{org_id: org_id, scope: scope}
  end

  test "a trial gives the plan until the end of its last month and uses up the free month", %{
    org_id: org_id,
    scope: scope
  } do
    assert {:ok, organization} =
             Core.grant_organization_trial(organization(org_id), :firma, 3, scope: scope)

    assert organization.billing_plan == :firma

    assert organization.trial_ends_on ==
             Month.current() |> Date.shift(month: 2) |> Date.end_of_month()

    assert %{plan_granted?: true, free_month_available?: false} =
             Ash.load!(organization, [:plan_granted?, :free_month_available?], scope: scope)
  end

  test "the daily trigger returns an ended trial to Free and leaves a running one", %{
    org_id: org_id,
    scope: scope
  } do
    {:ok, _organization} =
      Core.grant_organization_trial(organization(org_id), :firma, 2, scope: scope)

    ended =
      Ash.Seed.update!(organization(org_id), %{trial_ends_on: Date.add(Date.utc_today(), -2)})

    running = admin_fixture().member.organization_id

    {:ok, _organization} =
      Core.grant_organization_trial(organization(running), :przedsiebiorca, 1, scope: %{scope | tenant: running})

    AshOban.schedule_and_run_triggers({Organization, :end_trial})

    assert %{billing_plan: :free, trial_ends_on: nil, trial_granted_at: %DateTime{}} =
             organization(ended.id)

    assert %{billing_plan: :przedsiebiorca, trial_ends_on: %Date{}} = organization(running)
  end

  test "a plan set by hand replaces the trial", %{org_id: org_id, scope: scope} do
    {:ok, organization} =
      Core.grant_organization_trial(organization(org_id), :przedsiebiorca, 2, scope: scope)

    assert {:ok, %{billing_plan: :firma, trial_ends_on: nil}} =
             Core.update_organization_billing_plan(organization, %{billing_plan: :firma}, scope: scope)
  end

  test "granting a trial ends a subscription still awaiting its card for the same plan", %{
    org_id: org_id,
    scope: scope
  } do
    awaiting =
      Ash.Seed.seed!(Subscription, %{
        organization_id: org_id,
        plan: :firma,
        billing_period: :monthly,
        tokenization_id: "TOK-AWAITING"
      })

    assert {:ok, %{billing_plan: :firma}} =
             Core.grant_organization_trial(organization(org_id), :firma, 2, scope: scope)

    assert %{status: :ended, end_reason: :plan_changed} = Repo.reload!(awaiting)
  end

  test "a company paying with a card gets no trial", %{org_id: org_id, scope: scope} do
    BillingFixtures.active_subscription!(org_id)

    assert {:error, %Ash.Error.Invalid{} = error} =
             Core.grant_organization_trial(organization(org_id), :firma, 3, scope: scope)

    assert Exception.message(error) =~ "cannot get a trial"
    assert %{billing_plan: :przedsiebiorca, trial_ends_on: nil} = organization(org_id)
  end

  defp organization(org_id), do: Core.get_organization!(org_id, authorize?: false)
end
