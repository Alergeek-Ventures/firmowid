defmodule FirmowidWeb.ConnCase do
  @moduledoc """
  Shared test setup for specs that require a Phoenix connection.

  It provides `Phoenix.ConnTest`, common connection helpers, and database sandbox setup.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use FirmowidWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias AshAuthentication.Plug.Helpers, as: AuthHelpers

  using do
    quote do
      use FirmowidWeb, :verified_routes

      import FirmowidWeb.ConnCase
      import Phoenix.ConnTest
      import Plug.Conn
      # The default endpoint for testing
      @endpoint FirmowidWeb.Core.Endpoint

      # Import conveniences for testing with connections
    end
  end

  setup tags do
    Firmowid.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = Firmowid.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> AuthHelpers.store_in_session(user)
  end

  def log_in_api_user(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)

    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
