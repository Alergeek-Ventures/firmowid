defmodule FirmowidWeb.Delegations.Views.DelegationTest do
  @moduledoc false

  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Scope

  test "renders an approved delegation settlement page", %{conn: conn} do
    user = user_fixture()
    admin = admin_fixture(%{organization_id: user.organization_id})
    scope = %Scope{actor: user, tenant: user.organization_id}

    delegation =
      Delegations.create_delegation!(
        %{
          title: "Wyjazd służbowy",
          billing_month: ~D[2026-08-01],
          destination: "Kraków",
          transport_types: [:railway],
          purpose: "Spotkanie z klientem",
          advance_payment_amount: Money.new(:PLN, 100),
          start_date: ~D[2026-08-10],
          end_date: ~D[2026-08-11]
        },
        scope: scope
      )

    {:ok, delegation} =
      Delegations.approve_delegation(delegation.id,
        scope: %Scope{actor: admin, tenant: user.organization_id}
      )

    {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    assert html =~ "Rozliczenie delegacji"
    assert html =~ "Przejazdy"
    assert html =~ "Nocleg"
  end
end
