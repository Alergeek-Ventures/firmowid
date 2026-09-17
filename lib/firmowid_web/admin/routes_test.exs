defmodule FirmowidWeb.Admin.RoutesTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias AshAuthentication.TokenResource

  @admin_paths ["/admin/dashboard/home", "/admin/oban/jobs"]

  setup do
    start_supervised!({Oban.Met, conf: Oban.config()})

    sonar_conf = %{Oban.config() | testing: :disabled}

    start_supervised!({Oban.Sonar, conf: sonar_conf, name: Oban.Registry.via(sonar_conf.name, Oban.Sonar)})

    :ok
  end

  test "anonymous users cannot mount admin dashboards", %{conn: conn} do
    for path <- @admin_paths do
      assert {:error, {:redirect, %{to: "/zaloguj"}}} = live(conn, path)
    end
  end

  test "ordinary organization admins cannot mount admin dashboards", %{conn: conn} do
    user = admin_fixture()
    conn = log_in_user(conn, user)

    for path <- @admin_paths do
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, path)
    end
  end

  test "superuser can mount admin dashboards after the initial request", %{conn: conn} do
    for path <- @admin_paths do
      superuser = superuser_fixture()
      conn = conn |> log_in_user(superuser) |> get(path)
      assert response(conn, 200)
      assert {:ok, _view, _html} = live(conn)
    end
  end

  test "role revoked between initial request and live mount is rejected", %{conn: conn} do
    for path <- @admin_paths do
      superuser = superuser_fixture()
      conn = conn |> log_in_user(superuser) |> get(path)
      assert response(conn, 200)

      Ash.Seed.update!(superuser, %{system_role: :user})

      assert {:error, {:redirect, %{to: "/"}}} = live(conn)
    end
  end

  test "token revoked between initial request and live mount is rejected", %{conn: conn} do
    for path <- @admin_paths do
      superuser = superuser_fixture()
      conn = conn |> log_in_user(superuser) |> get(path)
      assert response(conn, 200)

      token = Plug.Conn.get_session(conn, "user_token")

      assert :ok =
               TokenResource.revoke(Firmowid.Ash.Core.Token, token,
                 authorize?: false,
                 store_all_tokens?: true
               )

      assert {:error, {:redirect, %{to: "/zaloguj"}}} = live(conn)
    end
  end

  test "development guide is not routed outside development", %{conn: conn} do
    assert response(get(conn, "/development"), 404)
  end

  defp superuser_fixture do
    Ash.Seed.update!(admin_fixture(), %{system_role: :superuser})
  end
end
