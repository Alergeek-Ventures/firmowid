defmodule FirmowidWeb.Organization.Controllers.SwitchTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Scope

  setup do
    # Sable owns her first organization and joins a second one as an admin; each
    # organization has one employee only it sees.
    sable = admin_fixture(%{name: "Sable Orin"})
    first_id = sable.member.organization_id
    user_in_org_fixture(first_id, %{name: "Ada Pierwsza"})

    other_admin = admin_fixture()
    second_id = other_admin.member.organization_id
    user_in_org_fixture(second_id, %{name: "Bob Drugi"})

    invite =
      Core.create_invite!(%{issued_by_id: other_admin.id, role: :admin},
        scope: scope_for(other_admin)
      )

    Core.consume_invite!(invite, %{name: "Sable Orin"}, tenant: second_id, actor: sable)

    %{sable: sable, other_admin: other_admin, first_id: first_id, second_id: second_id}
  end

  test "switching shows only the selected organization's data", %{
    conn: conn,
    sable: sable,
    first_id: first_id
  } do
    conn = log_in_user(conn, sable)

    # The organization joined last is the default one.
    {:ok, _lv, html} = live(conn, ~p"/zarzadzanie/pracownicy")
    assert html =~ "Bob Drugi"
    refute html =~ "Ada Pierwsza"

    conn = post(conn, ~p"/organizacja/przelacz", %{"organizacja" => first_id})
    assert redirected_to(conn) == ~p"/fakturowanie"

    {:ok, _lv, html} = conn |> recycle() |> live(~p"/zarzadzanie/pracownicy")
    assert html =~ "Ada Pierwsza"
    refute html =~ "Bob Drugi"
  end

  test "a foreign organization is rejected in the switch request and the session",
       %{conn: conn, sable: sable} do
    foreign_id = admin_fixture(%{name: "Obcy Admin"}).member.organization_id
    conn = log_in_user(conn, sable)

    conn = post(conn, ~p"/organizacja/przelacz", %{"organizacja" => foreign_id})
    assert redirected_to(conn) == ~p"/fakturowanie"
    assert get_session(conn, "organization_id") != foreign_id

    # A session naming a foreign organization falls back to the user's default one.
    conn = conn |> recycle() |> Plug.Test.init_test_session(%{"organization_id" => foreign_id})
    {:ok, _lv, html} = live(conn, ~p"/zarzadzanie/pracownicy")
    assert html =~ "Bob Drugi"
    refute html =~ "Obcy Admin"
  end

  test "a member archived in one organization keeps working in the other",
       %{conn: conn, sable: sable, other_admin: other_admin, second_id: second_id} do
    conn = log_in_user(conn, sable)
    conn = post(conn, ~p"/organizacja/przelacz", %{"organizacja" => second_id})

    member = Enum.find(Core.list_active_members(sable), &(&1.organization_id == second_id))
    Core.archive_member!(member, scope: scope_for(other_admin))

    {:ok, _lv, html} = conn |> recycle() |> live(~p"/zarzadzanie/pracownicy")
    assert html =~ "Ada Pierwsza"
    refute html =~ "Bob Drugi"
  end

  test "an existing account joins another organization with an invitation code", %{conn: conn} do
    user = admin_fixture()
    other_admin = admin_fixture()
    second_id = other_admin.member.organization_id
    invite = Core.create_invite!(%{issued_by_id: other_admin.id}, scope: scope_for(other_admin))

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/organizacja")

    lv
    |> form("#join_form", %{code: invite.invite_code, name: "Nowe Imię"})
    |> render_submit()

    conn = follow_trigger_action(form(lv, "#switch-organization-form"), conn)
    assert redirected_to(conn) == ~p"/czasosledz"
    assert get_session(conn, "organization_id") == second_id

    assert user |> Core.list_active_members() |> Enum.map(& &1.organization_id) |> Enum.sort() ==
             Enum.sort([user.member.organization_id, second_id])
  end

  test "a role change in another organization does not move the session", %{conn: conn} do
    admin_a = admin_fixture()
    first_id = admin_a.member.organization_id
    user = user_in_org_fixture(first_id)

    admin_b = admin_fixture()
    second_id = admin_b.member.organization_id
    invite = Core.create_invite!(%{issued_by_id: admin_b.id}, scope: scope_for(admin_b))
    Core.consume_invite!(invite, %{name: "Ewa"}, tenant: second_id, actor: user)

    conn = conn |> log_in_user(user) |> get(~p"/czasosledz")
    assert get_session(conn, "organization_id") == second_id

    # Updating the membership in the first organization makes it the default one.
    member = Enum.find(Core.list_active_members(user), &(&1.organization_id == first_id))
    Core.update_member_role!(member, %{role: :invoicing}, scope: scope_for(admin_a))

    conn = conn |> recycle() |> get(~p"/czasosledz")
    assert get_session(conn, "organization_id") == second_id
  end

  test "joining an organization the user is already active in explains why", %{
    conn: conn,
    sable: sable,
    other_admin: other_admin
  } do
    invite = Core.create_invite!(%{issued_by_id: other_admin.id}, scope: scope_for(other_admin))
    {:ok, lv, _html} = conn |> log_in_user(sable) |> live(~p"/organizacja")

    html =
      lv
      |> form("#join_form", %{code: invite.invite_code, name: "Sable Orin"})
      |> render_submit()

    assert html =~ "Należysz już do tej organizacji."
  end

  defp scope_for(admin), do: %Scope{actor: admin, tenant: admin.member.organization_id}
end
