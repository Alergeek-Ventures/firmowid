defmodule FirmowidMcp.Utilities.RefreshTokenTransactionTest do
  @moduledoc "Checks refresh transactions and revocation across independent database connections."

  # Races need independent connections; sandboxed async tests can exhaust the pool.
  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures

  alias AshAuthentication.Oauth2Server.Register
  alias Ecto.Adapters.SQL.Sandbox
  alias Firmowid.Core
  alias Firmowid.Core.OauthRefreshToken
  alias Firmowid.Oauth2Server
  alias Firmowid.Repo

  @auth_context %{private: %{ash_authentication?: true}}

  for operation <- [:password_change, :archive, :reuse, :revoke] do
    test "concurrent #{operation} revokes the successor of an HTTP refresh" do
      operation = unquote(operation)
      parent = self()
      {user, client, raw, owner} = committed_fixture()
      client_id = client.cimd_url
      pause_rotation()

      rotation =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Process.put(:pause_oauth_rotation, true)
            refresh(raw, client_id)
          end)
        end)

      assert_receive {:rotation_paused, rotation_pid}, 10_000

      revoker =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:revoker_backend, backend_pid})
            revoke(operation, owner, user, raw, client_id)
          end)
        end)

      assert_receive {:revoker_backend, backend_pid}, 10_000
      await_lock(revoker, backend_pid, 2_000)
      send(rotation_pid, :continue_rotation)
      rotated = Task.await(rotation, 10_000)

      assert %{"refresh_token" => descendant, "access_token" => access_token} =
               json_response(rotated, 200)

      assert_revocation(operation, Task.await(revoker, 10_000))

      assert_revoked_access(operation, access_token)

      rejected = independently(fn -> refresh(descendant, client_id) end)
      assert %{"error" => "invalid_grant"} = json_response(rejected, 400)
    end
  end

  test "reuse by another client commits chain revocation before sending invalid_grant" do
    {_user, client, raw, _owner} = fixture()
    client_id = client.cimd_url
    other_client = register_client()

    assert %{"refresh_token" => descendant} = json_response(refresh(raw, client_id), 200)

    reused = refresh(raw, other_client.id)
    assert %{"error" => "invalid_grant"} = json_response(reused, 400)
    assert %{"error" => "invalid_grant"} = json_response(refresh(descendant, client_id), 400)
  end

  test "responses and before_send callbacks run after rotation and revocation commit" do
    {_user, client, raw, _owner} = fixture()
    client_id = client.cimd_url

    rotated = refresh(raw, client_id)

    assert %{"refresh_token" => descendant, "token_type" => "Bearer"} =
             json_response(rotated, 200)

    assert get_resp_header(rotated, "cache-control") == ["no-store"]

    reused = refresh(raw, client_id)
    assert %{"error" => "invalid_grant"} = json_response(reused, 400)
    assert %{"error" => "invalid_grant"} = json_response(refresh(descendant, client_id), 400)

    {_user, client, raw, _owner} = fixture()
    revoked = revoke(:revoke, nil, nil, raw, client.cimd_url)
    assert response(revoked, 200) == ""
    assert get_resp_header(revoked, "cache-control") == ["no-store"]
    assert %{"error" => "invalid_grant"} = json_response(refresh(raw, client.cimd_url), 400)
  end

  test "failed successor issuance rolls rotation back before sending the native server error" do
    {user, client, raw, _owner} = committed_fixture()
    pause_rotation()

    rotation =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Process.put(:pause_oauth_rotation, true)
          refresh(raw, client.cimd_url)
        end)
      end)

    assert_receive {:rotation_paused, rotation_pid}, 10_000

    independently(fn ->
      organization = Core.get_organization!(user.member.organization_id, authorize?: false)

      Core.update_organization_billing_plan!(organization, %{billing_plan: :no_plan}, authorize?: false)
    end)

    send(rotation_pid, :continue_rotation)
    conn = Task.await(rotation, 10_000)

    assert json_response(conn, 500) == %{
             "error" => "server_error",
             "error_description" => "request could not be processed"
           }

    assert get_resp_header(conn, "cache-control") == ["no-store"]

    assert {:ok, %{rotated_to_id: nil}} =
             independently(fn ->
               Core.get_oauth_refresh_token_by_hash(hash(raw), context: @auth_context)
             end)
  end

  @doc "Pauses after predecessor rotation, before successor issuance."
  @spec pause_rotation([atom()], map(), map(), pid()) :: :ok
  def pause_rotation(_event, _measurements, %{query: query}, parent) do
    if Process.get(:pause_oauth_rotation) == true and String.contains?(query, "UPDATE") and
         String.contains?(query, "oauth_refresh_tokens") and
         String.contains?(query, "rotated_to_id") do
      Process.delete(:pause_oauth_rotation)
      send(parent, {:rotation_paused, self()})

      receive do
        :continue_rotation -> :ok
      after
        10_000 -> raise "refresh rotation barrier timed out"
      end
    end

    :ok
  end

  defp pause_rotation do
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(handler, [:firmowid, :repo, :query], &__MODULE__.pause_rotation/4, self())

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp committed_fixture do
    {user, client, _raw, owner} = fixture = independently(&fixture/0)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        assert {:ok, :ok} =
                 Repo.transaction(fn ->
                   :ok = Core.destroy_user_in_transaction(user)
                   Core.destroy_user_in_transaction(owner)
                 end)

        Ash.destroy!(client, context: @auth_context)
      end)
    end)

    fixture
  end

  defp fixture do
    owner = admin_fixture()
    user = user_in_org_fixture(owner.member.organization_id)
    client = register_client()
    client = Ash.Seed.update!(client, %{cimd_url: "https://example.com/#{client.id}.json"})
    raw = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    id = Ash.UUIDv7.generate()

    OauthRefreshToken.issue!(
      %{
        id: id,
        chain_id: id,
        token_hash: hash(raw),
        client_id: client.id,
        user_id: user.id,
        scope: "mcp",
        resource_uri: Oauth2Server.resource_url(),
        expires_at: DateTime.shift(DateTime.utc_now(), minute: 5)
      },
      context: @auth_context,
      tenant: user.member.organization_id
    )

    {user, client, raw, owner}
  end

  defp register_client do
    {:ok, client, _response} =
      Register.register(Oauth2Server, %{
        "client_name" => "Refresh transaction",
        "redirect_uris" => ["https://example.com/callback"],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    client
  end

  defp assert_revoked_access(:password_change, access_token) do
    rejected =
      independently(fn ->
        build_conn()
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> post("/mcp", %{})
      end)

    assert %{"error" => "unauthorized"} = json_response(rejected, 401)
  end

  defp assert_revoked_access(_operation, _access_token), do: :ok

  defp hash(raw), do: :sha256 |> :crypto.hash(raw) |> Base.encode16(case: :lower)

  defp refresh(raw, client_id) do
    # Encoded paths must take the same transaction as literal protocol paths.
    post(after_commit_conn(), "/oauth/%74oken", %{
      grant_type: "refresh_token",
      refresh_token: raw,
      client_id: client_id
    })
  end

  defp revoke(:reuse, _owner, _user, raw, client_id), do: refresh(raw, client_id)

  defp revoke(:revoke, _owner, _user, raw, client_id) do
    post(after_commit_conn(), "/oauth/%72evoke", %{token: raw, client_id: client_id})
  end

  defp revoke(:archive, owner, user, _raw, _client_id) do
    Core.archive_member(user.member, actor: owner, tenant: user.member.organization_id)
  end

  defp revoke(:password_change, _owner, user, _raw, _client_id) do
    Core.change_password(
      user,
      %{
        current_password: valid_user_password(),
        password: String.reverse(valid_user_password()),
        password_confirmation: String.reverse(valid_user_password())
      },
      actor: user
    )
  end

  defp assert_revocation(:reuse, conn), do: assert(%{"error" => "invalid_grant"} = json_response(conn, 400))

  defp assert_revocation(:revoke, conn), do: assert(response(conn, 200) == "")
  defp assert_revocation(_operation, result), do: assert({:ok, _record} = result)

  defp after_commit_conn do
    register_before_send(build_conn(), fn conn ->
      refute Repo.in_transaction?(), "the response was sent inside the token transaction"
      conn
    end)
  end

  defp independently(fun), do: Task.await(Task.async(fn -> Sandbox.unboxed_run(Repo, fun) end), 10_000)

  defp await_lock(_task, _backend_pid, 0), do: flunk("revoker did not reach its row lock")

  defp await_lock(task, backend_pid, attempts) do
    if result = Task.yield(task, 0),
      do: flunk("revoker escaped the user lock: #{inspect(result)}")

    %{rows: [[blocked]]} =
      Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [backend_pid])

    if blocked, do: :ok, else: await_lock(task, backend_pid, attempts - 1)
  end
end
