defmodule FirmowidWeb.Delegations.Views.DelegationFormTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Scope

  test "renders, validates, and submits a delegation", %{conn: conn} do
    employee = user_fixture()
    scope = %Scope{actor: employee, tenant: employee.organization_id}
    {:ok, view, html} = conn |> log_in_user(employee) |> live(~p"/delegacje/dodaj")

    assert html =~ "Planowanie delegacji"
    assert html =~ "Gdy zostanie zaakceptowany otrzymasz maila z potwierdzeniem."

    invalid_html =
      render_change(view, "validate", %{
        "delegation" => delegation_params(%{"end_date" => "2026-09-09"})
      })

    assert invalid_html =~ "musi być na lub po dacie wyjazdu"

    view
    |> form("#delegation-form", delegation: delegation_params())
    |> render_submit()

    assert_redirect(view, ~p"/ustawienia/profil")

    [delegation] = Delegations.list_delegations_for_user!(employee.id, scope: scope)
    assert delegation.purpose == "Spotkanie z klientem"
    assert delegation.destination == "Kraków"
    assert delegation.transport_types == [:railway, :bus]
    assert delegation.advance_payment_amount == Money.new(:PLN, "123.45")
    assert delegation.start_date == ~D[2026-09-10]
    assert delegation.end_date == ~D[2026-09-11]
  end

  test "keeps the form live when the billing month is malformed", %{conn: conn} do
    employee = user_fixture()
    {:ok, view, _html} = conn |> log_in_user(employee) |> live(~p"/delegacje/dodaj")

    assert render_hook(view, "change-month", %{"month" => "not-a-date"}) =~
             "Wybierz poprawny miesiąc rozliczeniowy."

    assert render(view) =~ "Planowanie delegacji"
  end

  test "adds and removes transport type selects", %{conn: conn} do
    employee = user_fixture()
    {:ok, view, html} = conn |> log_in_user(employee) |> live(~p"/delegacje/dodaj")

    assert html =~ "Miejsce podróży"
    assert html =~ "Środek lokomocji"
    assert html =~ "Wybierz z listy"
    assert html =~ ~r/<option[^>]*value=""[^>]*disabled[^>]*hidden[^>]*>\s*Wybierz z listy/
    assert html =~ "+ Dodaj kolejny"

    html = render_click(view, "add_transport_type")
    assert html =~ "delegation_transport_types_1"
    assert html =~ "Usuń środek lokomocji"

    refute render_click(view, "remove_transport_type", %{"index" => "0"}) =~
             "delegation_transport_types_1"
  end

  defp delegation_params(overrides \\ %{}) do
    Map.merge(
      %{
        "billing_month" => "2026-09-01",
        "destination" => "Kraków",
        "transport_types" => ["railway", "bus"],
        "purpose" => "Spotkanie z klientem",
        "advance_payment_amount" => "123.45",
        "start_date" => "2026-09-10",
        "end_date" => "2026-09-11"
      },
      overrides
    )
  end
end
