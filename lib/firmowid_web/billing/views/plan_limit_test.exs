defmodule FirmowidWeb.Billing.Views.PlanLimitTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Core
  alias Firmowid.Repo

  test "from the decision day an admin is held on the choice until they submit one; an employee works on",
       %{conn: conn} do
    admin = admin_fixture()
    org_id = admin.member.organization_id
    kept_employee = employee(org_id, ~U[2026-01-02 10:00:00Z])
    dropped_employee = employee(org_id, ~U[2026-01-03 10:00:00Z])
    kept_account = synced_account(org_id, "Older Bank", ~U[2026-01-01 10:00:00Z])
    dropped_account = synced_account(org_id, "Newer Bank", ~U[2026-01-02 10:00:00Z])

    org_id
    |> Core.get_organization!(authorize?: false)
    |> Ash.Seed.update!(%{plan_limit_decision_on: Date.add(Date.utc_today(), -1)})

    assert {:ok, _view, _html} = conn |> log_in_user(kept_employee) |> live(~p"/czasosledz")

    conn = log_in_user(conn, admin)
    assert {:error, {:redirect, %{to: "/limit-planu"}}} = live(conn, ~p"/fakturowanie")

    {:ok, view, _html} = live(conn, ~p"/limit-planu")
    assert has_element?(view, "#plan-limit-bank_institutions label", "Older Bank")
    assert has_element?(view, "#plan-limit-bank_institutions label", "Newer Bank")
    refute has_element?(view, "#plan-limit-upgrade button")

    # The oldest that fit the plan are ticked to start with.
    view |> form("#plan-limit-form") |> render_submit()
    assert_redirect(view, "/fakturowanie")

    assert Repo.reload!(dropped_employee.member).archived_at
    refute Repo.reload!(kept_employee.member).archived_at
    assert Repo.reload!(dropped_account).suspended_by_plan_at
    refute Repo.reload!(kept_account).suspended_by_plan_at

    assert {:ok, _view, _html} = live(conn, ~p"/fakturowanie")
  end

  defp employee(org_id, joined_at) do
    user = user_in_org_fixture(org_id)
    %{user | member: Ash.Seed.update!(user.member, %{inserted_at: joined_at})}
  end

  defp synced_account(org_id, bank, connected_at) do
    bank_account_fixture_for_organization!(org_id, %{
      gocardless_id: Ash.UUID.generate(),
      institution_id: bank,
      institution_name: bank,
      inserted_at: connected_at
    })
  end
end
