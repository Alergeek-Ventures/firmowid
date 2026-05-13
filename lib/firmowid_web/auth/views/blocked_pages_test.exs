defmodule FirmowidWeb.Auth.Views.BlockedPagesTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Core

  test "organization owner can view the expired subscription page", %{conn: conn} do
    admin = admin_fixture()
    expire_subscription!(admin.organization_id)

    assert {:ok, _view, html} =
             conn
             |> log_in_user(admin)
             |> live(~p"/abonament-wygasl")

    assert html =~ "Abonament wygasł"
    assert html =~ "Skontaktuj się w sprawie abonamentu"
  end

  test "non-owner member is redirected from expired subscription page to disabled account", %{
    conn: conn
  } do
    admin = admin_fixture()
    member = user_in_org_fixture(admin.organization_id)
    expire_subscription!(admin.organization_id)

    assert {:error, {:redirect, %{to: to}}} =
             conn
             |> log_in_user(member)
             |> live(~p"/abonament-wygasl")

    assert to == ~p"/konto-wylaczone"
  end

  defp expire_subscription!(organization_id) do
    organization = Core.get_organization!(organization_id, authorize?: false)

    Core.update_organization_billing_plan!(organization, %{billing_plan: :no_plan}, authorize?: false)
  end
end
