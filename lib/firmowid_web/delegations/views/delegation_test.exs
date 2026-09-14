defmodule FirmowidWeb.Delegations.Views.DelegationTest do
  @moduledoc false

  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Delegations.DelegationExpense
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

  test "renders an in-progress delegation with union-backed expense details", %{conn: conn} do
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

    for {kind, details} <- [
          {
            :transport,
            %{
              type: "transport",
              transport_type: :railway,
              trips: [
                %{
                  departure_city: "Wrocław",
                  departure_datetime: ~U[2026-08-10 08:00:00Z],
                  arrival_city: "Kraków",
                  arrival_datetime: ~U[2026-08-10 10:00:00Z]
                }
              ]
            }
          },
          {:accommodation, %{type: "accommodation", locality: "Kraków"}},
          {:other, %{type: "other", description: "Parking"}}
        ] do
      Ash.Seed.seed!(
        DelegationExpense,
        %{
          delegation_id: delegation.id,
          organization_id: user.organization_id,
          kind: kind,
          original_filename: "rachunek.pdf",
          document_number: "FV/1",
          expense_amount: Money.new(:PLN, 100),
          details: details
        },
        tenant: user.organization_id
      )
    end

    {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    assert html =~ "transport-transport-type-"
    assert html =~ "accommodation-locality-"
    assert html =~ "other-description-"
    assert html =~ "trip-departure-city-"
  end
end
