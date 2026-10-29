defmodule FirmowidWeb.Admin.Views.SettlementTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Core

  test "a system admin sees the owner's phone in an organization's settlement, also after a plan change",
       %{
         conn: conn
       } do
    owner = admin_fixture()

    Core.update_member_profile!(owner.member, %{phone: "+48 600 700 800"},
      actor: owner,
      tenant: owner.member.organization_id
    )

    superuser = Ash.Seed.update!(admin_fixture(), %{system_role: :superuser})
    superuser = Core.load_member(superuser)

    {:ok, lv, html} =
      live(
        log_in_user(conn, superuser),
        ~p"/admin/rozliczenia/#{owner.member.organization_id}?miesiac=2026-10-01"
      )

    assert html =~ "+48 600 700 800"

    assert render_hook(lv, "save-current-plan", %{"plan" => %{"billing_plan" => "firma"}}) =~
             "+48 600 700 800"

    assert Core.get_organization!(owner.member.organization_id, authorize?: false).billing_plan ==
             :firma
  end
end
