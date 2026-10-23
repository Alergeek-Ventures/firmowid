defmodule Firmowid.Ash.Core.User.AuthenticationTest do
  @moduledoc "Regression coverage for membership and password revocation across authentication entry points."

  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy
  alias Ecto.Adapters.SQL.Sandbox
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Core.UserIdentity

  @authentication_context %{private: %{ash_authentication?: true}}

  setup do
    admin = admin_fixture()
    user = user_in_org_fixture(admin.member.organization_id)
    user = Ash.Seed.update!(user, %{confirmed_at: DateTime.utc_now()})
    {:ok, password_strategy} = Info.strategy(User, :password)

    %{admin: admin, user: user, password_strategy: password_strategy}
  end

  test "an archived member signs in to an account without an organization", %{
    admin: admin,
    user: user,
    password_strategy: strategy
  } do
    {:ok, _member} =
      Core.archive_member(user.member, actor: admin, tenant: user.member.organization_id)

    params = %{email: to_string(user.email), password: valid_user_password()}
    assert {:ok, signed_in} = Strategy.action(strategy, :sign_in, params, [])
    assert signed_in.id == user.id
    assert Core.load_member(signed_in).member == nil
    assert is_binary(signed_in.__metadata__.token)
  end

  test "an admin still lists the archived member", %{admin: admin, user: user} do
    {:ok, _member} =
      Core.archive_member(user.member, actor: admin, tenant: user.member.organization_id)

    assert [archived] =
             Core.list_users!(%{status: :archived},
               actor: admin,
               tenant: admin.member.organization_id
             )

    assert archived.id == user.id
  end

  test "a linked active Google account retains its local identity when the provider email changes",
       %{
         user: user
       } do
    user_info = google_user_info(user)
    oauth_tokens = %{"access_token" => "test-google-token"}

    assert {:ok, linked} =
             User.register_with_google(user_info, oauth_tokens, context: @authentication_context)

    changed_email = unique_user_email()
    user_info = Map.put(user_info, "email", changed_email)

    assert {:ok, signed_in} =
             User.register_with_google(user_info, oauth_tokens, context: @authentication_context)

    assert signed_in.id == linked.id
    assert signed_in.email == user.email
    assert is_binary(signed_in.__metadata__.token)
    assert [%{user_id: user_id}] = UserIdentity.read!(actor: user)
    assert user_id == user.id

    assert {:ok, nil} =
             User.get_by_email(%{email: changed_email},
               context: @authentication_context,
               not_found_error?: false
             )
  end

  for method <- [:password, :remember_me, :remember_me_before_lock] do
    test "password changes revoke sessions issued by an overlapping #{method} sign-in" do
      method = unquote(method)
      parent = self()

      # Commit this fixture on an independently checked-out connection: two real
      # transactions are required to observe issuance racing password revocation.
      user =
        Task.await(
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              Core.register_with_password!(valid_user_attributes(), authorize?: false)
            end)
          end)
        )

      on_exit(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          User.destroy!(user, authorize?: false)
        end)
      end)

      {action, params} = sign_in_params(method, user)

      sign_in =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            method
            |> paused_sign_in(action, params, parent)
            |> Ash.read_one()
          end)
        end)

      assert_receive {:credentials_read, sign_in_pid}, 10_000

      password_change =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Repo.transaction(fn ->
              %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
              send(parent, {:password_backend, backend_pid})

              user
              |> Ash.Changeset.for_update(
                :change_password,
                %{
                  current_password: valid_user_password(),
                  password: String.reverse(valid_user_password()),
                  password_confirmation: String.reverse(valid_user_password())
                },
                actor: user
              )
              |> Ash.update!(actor: user)
            end)
          end)
        end)

      assert_receive {:password_backend, backend_pid}, 10_000
      change_state = await_password_change(password_change, backend_pid, 2_000)
      send(sign_in_pid, :continue)
      sign_in_result = Task.await(sign_in, 10_000)

      case change_state do
        :blocked -> assert {:ok, _user} = Task.await(password_change, 10_000)
        {:completed, result} -> assert {:ok, _user} = result
      end

      assert_revoked_sign_in(method, sign_in_result)
    end
  end

  defp paused_sign_in(:remember_me_before_lock, action, params, parent) do
    User
    |> Ash.Query.for_read(action, params, context: @authentication_context)
    |> Ash.Query.before_action(fn query ->
      pause_sign_in(parent)
      query
    end)
  end

  defp paused_sign_in(_method, action, params, parent) do
    User
    |> Ash.Query.after_action(fn _query, users ->
      pause_sign_in(parent)
      {:ok, users}
    end)
    |> Ash.Query.for_read(action, params, context: @authentication_context)
  end

  defp pause_sign_in(parent) do
    send(parent, {:credentials_read, self()})

    receive do
      :continue -> :ok
    after
      10_000 -> raise "sign-in barrier timed out"
    end
  end

  defp assert_revoked_sign_in(:remember_me_before_lock, result), do: assert({:error, _} = result)

  defp assert_revoked_sign_in(_method, result) do
    assert {:ok, signed_in} = result

    assert :error ==
             Sandbox.unboxed_run(Repo, fn ->
               AshAuthentication.Plug.Helpers.authenticate_resource_from_session(
                 User,
                 %{"user_token" => signed_in.__metadata__.token},
                 :firmowid,
                 []
               )
             end)
  end

  defp sign_in_params(:password, user) do
    {:sign_in_with_password, %{email: user.email, password: valid_user_password()}}
  end

  defp sign_in_params(method, user) when method in [:remember_me, :remember_me_before_lock] do
    {:ok, token, _claims} =
      Task.await(
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            AshAuthentication.Jwt.token_for_user(user, %{"purpose" => "remember_me"}, purpose: :remember_me)
          end)
        end)
      )

    {:sign_in_with_remember_me, %{token: token}}
  end

  defp await_password_change(_task, _backend_pid, 0), do: flunk("password change did not reach its row lock")

  defp await_password_change(task, backend_pid, attempts) do
    case Task.yield(task, 0) do
      {:ok, result} ->
        {:completed, result}

      nil ->
        %{rows: [[blocked]]} =
          Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [backend_pid])

        if blocked, do: :blocked, else: await_password_change(task, backend_pid, attempts - 1)
    end
  end

  defp google_user_info(user) do
    %{
      "sub" => "google-#{user.id}",
      "email" => to_string(user.email),
      "email_verified" => true,
      "name" => "Google User"
    }
  end
end
