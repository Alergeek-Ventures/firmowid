defmodule FirmowidWeb.Auth.Controllers.SessionApiTest do
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures

  @user_attrs %{
    password: "really_long_password"
  }

  setup %{conn: conn} do
    user = user_fixture(@user_attrs)
    {:ok, conn: put_req_header(conn, "accept", "application/json"), user: user}
  end

  describe "login" do
    test "returns token when credentials are valid", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/api/login", %{
          "email" => user.email,
          "password" => @user_attrs.password
        })

      assert %{"token" => token} = json_response(conn, 200)
      assert is_binary(token)
    end

    test "returns error when email is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/api/login", %{
          "email" => "invalid@example.com",
          "password" => @user_attrs.password
        })

      assert json_response(conn, 401)["errors"] != %{}
    end

    test "returns error when password is invalid", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/api/login", %{
          "email" => user.email,
          "password" => "invalid_password"
        })

      assert json_response(conn, 401)["errors"] != %{}
    end
  end
end
