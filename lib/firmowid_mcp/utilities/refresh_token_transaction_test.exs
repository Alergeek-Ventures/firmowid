defmodule FirmowidMcp.Utilities.RefreshTokenTransactionTest do
  @moduledoc "Checks HTTP refresh rotation and chain revocation on independent database connections."

  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures

  alias AshAuthentication.Oauth2Server.Jwt
  alias AshAuthentication.Oauth2Server.Register
  alias Ecto.Adapters.SQL.Sandbox
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.OauthRefreshToken
  alias Firmowid.Oauth2Server
  alias Firmowid.Repo

  @auth_context %{private: %{ash_authentication?: true}}

  for revocation <- [:reuse, :revoke, :ancestor_reuse_other_client],
      identity <- [:registered, :cimd],
      encoded? <- [false, true] do
    test "HTTP rotation cannot escape concurrent #{revocation} for a #{identity} client (encoded: #{encoded?})" do
      revocation = unquote(revocation)
      identity = unquote(identity)
      encoded? = unquote(encoded?)
      parent = self()
      {user, client, raw, presented_id} = independently(fn -> fixture(identity) end)

      {rotation_raw, revocation_client} =
        independently(fn -> prepare_revocation(revocation, raw, presented_id) end)

      revocation_client_id = if revocation_client, do: revocation_client.id, else: presented_id

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          assert {:ok, :ok} = Repo.transaction(fn -> Core.destroy_user_in_transaction(user) end)
          Ash.destroy!(client, context: @auth_context)

          if revocation_client, do: Ash.destroy!(revocation_client, context: @auth_context)
        end)
      end)

      handler = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach(
          handler,
          [:firmowid, :repo, :query],
          &__MODULE__.pause_rotation/4,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler) end)

      rotation =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Process.put(:pause_oauth_rotation, :waiting)
            refresh(rotation_raw, presented_id, encoded?)
          end)
        end)

      assert_receive {:rotation_paused, rotation_pid}, 10_000

      revoker =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
            send(parent, {:revoker_backend, backend_pid})

            revoke(revocation, raw, revocation_client_id, encoded?)
          end)
        end)

      assert_receive {:revoker_backend, backend_pid}, 10_000
      state = await_revoker(revoker, backend_pid, 2_000)
      send(rotation_pid, :continue_rotation)
      rotated = Task.await(rotation, 10_000)

      assert %{"refresh_token" => descendant, "access_token" => access_token} =
               json_response(rotated, 200)

      assert {:ok, %{"client_id" => ^presented_id, "tenant" => tenant}} =
               Jwt.verify(Oauth2Server, access_token)

      assert tenant == user.member.organization_id

      response =
        case state do
          :blocked -> Task.await(revoker, 10_000)
          {:completed, response} -> response
        end

      assert_revocation(revocation, response)

      rejected = independently(fn -> refresh(descendant, presented_id) end)
      assert %{"error" => "invalid_grant"} = json_response(rejected, 400)
      assert state == :blocked
    end
  end

  for operation <- [:reuse, :revoke] do
    test "a blocked account keeps the native #{operation} response" do
      operation = unquote(operation)
      {user, _client, raw, client_id} = fixture(:registered)
      prepare_blocked_token(operation, raw, client_id)
      block(user)

      assert_revocation(operation, revoke(operation, raw, client_id, false))
    end

    test "deletion between token lookup and user lock keeps the native #{operation} response" do
      operation = unquote(operation)
      parent = self()
      {user, client, raw, client_id} = independently(fn -> fixture(:registered) end)

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          if user = Core.get_user!(user.id, authorize?: false, not_found_error?: false) do
            assert {:ok, :ok} = Repo.transaction(fn -> Core.destroy_user_in_transaction(user) end)
          end

          Ash.destroy!(client, context: @auth_context)
        end)
      end)

      handler = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach(
          handler,
          [:firmowid, :repo, :query],
          &__MODULE__.pause_token_lookup/4,
          parent
        )

      on_exit(fn -> :telemetry.detach(handler) end)

      request =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            # TokenOrganization also reads the grant before the wrapper on /token.
            Process.put(:pause_oauth_lookup, token_lookup_count(operation))
            revoke(operation, raw, client_id, false)
          end)
        end)

      assert_receive {:token_lookup_paused, request_pid}, 10_000

      assert {:ok, :ok} =
               independently(fn ->
                 Repo.transaction(fn -> Core.destroy_user_in_transaction(user) end)
               end)

      send(request_pid, :continue_lookup)
      assert_revocation(operation, Task.await(request, 10_000))
    end
  end

  test "a blocked account's live refresh token keeps the native invalid_grant" do
    {user, _client, raw, client_id} = fixture(:registered)
    block(user)

    assert %{"error" => "invalid_grant"} =
             json_response(refresh_after_commit(build_conn(), raw, client_id), 400)
  end

  test "blocking the account between rotation and issuance keeps the native server error" do
    parent = self()
    {user, client, raw, client_id} = independently(fn -> fixture(:registered) end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        assert {:ok, :ok} = Repo.transaction(fn -> Core.destroy_user_in_transaction(user) end)
        Ash.destroy!(client, context: @auth_context)
      end)
    end)

    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(handler, [:firmowid, :repo, :query], &__MODULE__.pause_rotation/4, parent)

    on_exit(fn -> :telemetry.detach(handler) end)

    rotation =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          Process.put(:pause_oauth_rotation, :issuing)
          refresh_after_commit(build_conn(), raw, client_id)
        end)
      end)

    assert_receive {:rotation_paused, rotation_pid}, 10_000
    independently(fn -> block(user) end)
    send(rotation_pid, :continue_rotation)
    conn = Task.await(rotation, 10_000)

    assert json_response(conn, 500) == %{
             "error" => "server_error",
             "error_description" => "request could not be processed"
           }

    assert get_resp_header(conn, "cache-control") == ["no-store"]

    hash = :sha256 |> :crypto.hash(raw) |> Base.encode16(case: :lower)

    assert {:ok, %{rotated_to_id: nil}} =
             independently(fn ->
               Core.get_oauth_refresh_token_by_hash(hash, context: @auth_context)
             end)
  end

  test "native responses are sent only after their transaction" do
    {_user, _client, raw, client_id} = fixture(:registered)

    rotated = refresh_after_commit(build_conn(), raw, client_id)

    assert %{"refresh_token" => descendant, "token_type" => "Bearer"} =
             json_response(rotated, 200)

    assert get_resp_header(rotated, "cache-control") == ["no-store"]

    reused = refresh_after_commit(build_conn(), raw, client_id)
    assert %{"error" => "invalid_grant"} = json_response(reused, 400)
    assert %{"error" => "invalid_grant"} = json_response(refresh(descendant, client_id), 400)

    {_user, _client, raw, client_id} = fixture(:registered)

    revoked =
      build_conn()
      |> sent_after_commit()
      |> post("/oauth/revoke", %{token: raw, client_id: client_id})

    assert response(revoked, 200) == ""
    assert get_resp_header(revoked, "cache-control") == ["no-store"]
    assert %{"error" => "invalid_grant"} = json_response(refresh(raw, client_id), 400)
  end

  test "unknown tokens and another client cannot exchange or revoke an unused grant" do
    {_user, _client, raw, client_id} = fixture(:registered)
    {_other_user, _other_client, _other_raw, other_id} = fixture(:registered)

    assert %{"error" => "invalid_grant"} = json_response(refresh(raw, other_id), 400)

    assert %{"error" => "invalid_grant"} =
             json_response(revoke(:revoke, raw, other_id, false), 400)

    assert %{"error" => "invalid_grant"} = json_response(refresh("unknown-token", client_id), 400)
    assert_revocation(:revoke, revoke(:revoke, "unknown-token", client_id, false))
    assert %{"refresh_token" => _} = json_response(refresh(raw, client_id), 200)
  end

  test "known tokens preserve native client, resource and scope validation" do
    {user, _client, raw, client_id} = fixture(:cimd)
    params = %{grant_type: "refresh_token", refresh_token: raw, client_id: client_id}

    for {invalid, error} <- [
          {%{client_id: "https://example.com/unknown.json"}, "invalid_client"},
          {%{client_id: ""}, "invalid_request"},
          {%{scope: "ungranted"}, "invalid_scope"},
          {%{resource: "https://example.com/ungranted"}, "invalid_target"}
        ] do
      conn = post(build_conn(), "/oauth/token", Map.merge(params, invalid))
      assert %{"error" => ^error} = json_response(conn, 400)
    end

    basic =
      build_conn()
      |> put_req_header("authorization", "Basic " <> Base.encode64(client_id <> ":"))
      |> post("/oauth/revoke", %{token: raw, client_id: client_id})

    assert %{"error" => "invalid_client"} = json_response(basic, 401)
    assert [challenge] = get_resp_header(basic, "www-authenticate")
    assert String.starts_with?(challenge, "Basic realm=")

    conn = post(build_conn(), "/oauth/token", Map.put(params, :user_id, Ash.UUIDv7.generate()))
    assert %{"access_token" => access_token} = json_response(conn, 200)

    assert {:ok, %{"sub" => subject, "client_id" => ^client_id}} =
             Jwt.verify(Oauth2Server, access_token)

    assert subject == user.id
  end

  @doc "Pauses the selected grant lookup so deletion can commit before the user lock."
  @spec pause_token_lookup([atom()], map(), map(), pid()) :: :ok
  def pause_token_lookup(_event, _measurements, metadata, parent) do
    count = Process.get(:pause_oauth_lookup)

    if count && String.starts_with?(metadata.query, "SELECT") &&
         String.contains?(metadata.query, "\"oauth_refresh_tokens\"") do
      if count == 1 do
        Process.delete(:pause_oauth_lookup)
        send(parent, {:token_lookup_paused, self()})

        receive do
          :continue_lookup -> :ok
        after
          10_000 -> raise "token lookup barrier timed out"
        end
      else
        Process.put(:pause_oauth_lookup, count - 1)
      end
    end

    :ok
  end

  test "discovery remains native and its mount does not expose token mutations" do
    assert %{"token_endpoint" => _} =
             json_response(get(build_conn(), "/.well-known/oauth-authorization-server"), 200)

    {_user, _client, raw, client_id} = fixture(:registered)

    conn =
      post(build_conn(), "/.well-known/token", %{
        grant_type: "refresh_token",
        refresh_token: raw,
        client_id: client_id
      })

    assert conn.status == 404
    assert %{"refresh_token" => _} = json_response(refresh(raw, client_id), 200)
  end

  @doc "Pauses rotation after its predecessor update, before or after the issuance lock."
  @spec pause_rotation([atom()], map(), map(), pid()) :: :ok
  def pause_rotation(_event, _measurements, %{query: query}, parent) do
    rotation? =
      String.contains?(query, "UPDATE") and String.contains?(query, "oauth_refresh_tokens") and
        String.contains?(query, "rotated_to_id")

    case Process.get(:pause_oauth_rotation) do
      :issuing when rotation? ->
        await_rotation(parent)

      :waiting when rotation? ->
        Process.put(:pause_oauth_rotation, :rotated)

      :rotated ->
        if String.contains?(query, "FOR UPDATE") and String.contains?(query, "users"),
          do: await_rotation(parent)

      _other ->
        :ok
    end

    :ok
  end

  defp await_rotation(parent) do
    Process.delete(:pause_oauth_rotation)
    send(parent, {:rotation_paused, self()})

    receive do
      :continue_rotation -> :ok
    after
      10_000 -> raise "refresh rotation barrier timed out"
    end
  end

  defp fixture(identity) do
    user = admin_fixture()
    client = register_client()

    client =
      case identity do
        :registered -> client
        :cimd -> Ash.Seed.update!(client, %{cimd_url: "https://example.com/#{client.id}.json"})
      end

    raw = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    id = Ash.UUIDv7.generate()

    OauthRefreshToken.issue!(
      %{
        id: id,
        chain_id: id,
        token_hash: :sha256 |> :crypto.hash(raw) |> Base.encode16(case: :lower),
        client_id: client.id,
        user_id: user.id,
        scope: "mcp",
        resource_uri: Oauth2Server.resource_url(),
        expires_at: DateTime.shift(DateTime.utc_now(), minute: 5)
      },
      context: @auth_context,
      tenant: user.member.organization_id
    )

    {user, client, raw, client.cimd_url || client.id}
  end

  defp register_client do
    {:ok, client, _response} =
      Register.register(Oauth2Server, %{
        "client_name" => "Concurrent refresh regression",
        "redirect_uris" => ["https://example.com/callback"],
        "grant_types" => ["authorization_code", "refresh_token"],
        "response_types" => ["code"],
        "token_endpoint_auth_method" => "none"
      })

    client
  end

  defp prepare_revocation(:ancestor_reuse_other_client, raw, client_id) do
    %{"refresh_token" => descendant} = json_response(refresh(raw, client_id), 200)
    {descendant, register_client()}
  end

  defp prepare_revocation(_revocation, raw, _client_id), do: {raw, nil}

  defp block(user) do
    organization = Core.get_organization!(user.member.organization_id, authorize?: false)

    Core.update_organization_billing_plan!(organization, %{billing_plan: :no_plan}, authorize?: false)
  end

  defp prepare_blocked_token(:reuse, raw, client_id) do
    assert_revocation(:revoke, revoke(:revoke, raw, client_id, false))
  end

  defp prepare_blocked_token(:revoke, _raw, _client_id), do: :ok

  defp token_lookup_count(:reuse), do: 2
  defp token_lookup_count(:revoke), do: 1

  defp refresh(raw, client_id, encoded? \\ false) do
    path = if encoded?, do: "/oauth/%74oken", else: "/oauth/token"

    post(build_conn(), path, %{
      grant_type: "refresh_token",
      refresh_token: raw,
      client_id: client_id
    })
  end

  defp refresh_after_commit(conn, raw, client_id) do
    conn
    |> sent_after_commit()
    |> post("/oauth/token", %{
      grant_type: "refresh_token",
      refresh_token: raw,
      client_id: client_id
    })
  end

  # Runs right before the adapter sends the response.
  defp sent_after_commit(conn) do
    register_before_send(conn, fn conn ->
      refute Repo.in_transaction?(), "the response was sent inside the token transaction"
      conn
    end)
  end

  defp revoke(:reuse, raw, client_id, encoded?), do: refresh(raw, client_id, encoded?)

  defp revoke(:ancestor_reuse_other_client, raw, client_id, encoded?) do
    refresh(raw, client_id, encoded?)
  end

  defp revoke(:revoke, raw, client_id, encoded?) do
    path = if encoded?, do: "/oauth/%72evoke", else: "/oauth/revoke"
    post(build_conn(), path, %{token: raw, client_id: client_id})
  end

  defp assert_revocation(revocation, response) when revocation in [:reuse, :ancestor_reuse_other_client] do
    assert %{"error" => "invalid_grant"} = json_response(response, 400)
  end

  defp assert_revocation(:revoke, response), do: assert(response.status == 200)

  defp independently(fun) do
    Task.await(Task.async(fn -> Sandbox.unboxed_run(Repo, fun) end), 10_000)
  end

  defp await_revoker(_task, _backend_pid, 0), do: flunk("revoker did not reach its row lock")

  defp await_revoker(task, backend_pid, attempts) do
    case Task.yield(task, 0) do
      {:ok, response} ->
        {:completed, response}

      nil ->
        %{rows: [[blocked]]} =
          Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [backend_pid])

        if blocked, do: :blocked, else: await_revoker(task, backend_pid, attempts - 1)
    end
  end
end
