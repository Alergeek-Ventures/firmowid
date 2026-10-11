defmodule Firmowid.Ash.Core.User.AuthenticationTest do
  @moduledoc "Regression coverage for archived accounts across authentication entry points."

  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias AshAuthentication.Errors.AuthenticationFailed
  alias AshAuthentication.Info
  alias AshAuthentication.Jwt
  alias AshAuthentication.Strategy
  alias AshAuthentication.Strategy.Password
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.Token
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Core.UserIdentity

  @authentication_context %{private: %{ash_authentication?: true}}

  setup do
    user = user_fixture()
    user = Ash.Seed.update!(user, %{confirmed_at: DateTime.utc_now()})
    {:ok, password_strategy} = Info.strategy(User, :password)

    %{user: user, password_strategy: password_strategy}
  end

  test "password authentication accepts active users but never issues tokens for archived users",
       %{
         user: user,
         password_strategy: strategy
       } do
    params = %{email: to_string(user.email), password: valid_user_password()}
    assert {:ok, signed_in} = Strategy.action(strategy, :sign_in, params, [])
    assert signed_in.id == user.id
    assert is_binary(signed_in.__metadata__.token)

    archive(user)
    tokens = stored_tokens()

    assert {:error, %AuthenticationFailed{}} = Strategy.action(strategy, :sign_in, params, [])
    assert stored_tokens() == tokens
  end

  test "session subject lookup and trusted default reads exclude archived users", %{user: user} do
    subject = AshAuthentication.user_to_subject(user)

    assert {:ok, %{id: id}} =
             User.get_by_subject(%{subject: subject}, context: @authentication_context)

    assert id == user.id

    assert {:ok, %{id: ^id}} = AshAuthentication.subject_to_user(subject, User)
    assert {:ok, %{id: ^id}} = User.get(user.id, context: @authentication_context)

    archive(user)

    assert {:error, _} =
             User.get_by_subject(%{subject: subject}, context: @authentication_context)

    assert {:error, _} = AshAuthentication.subject_to_user(subject, User)
    assert {:error, _} = User.get(user.id, context: @authentication_context)
  end

  test "ordinary administrative reads and archived lists remain available", %{user: user} do
    admin = admin_fixture(%{organization_id: user.organization_id})
    archived = archive(user)

    assert {:ok, %{id: id, archived_at: archived_at}} = User.get(user.id, actor: admin)
    assert id == archived.id
    assert archived_at == archived.archived_at

    assert Enum.any?(
             Core.list_users!(%{status: :archived}, actor: admin, tenant: admin.organization_id),
             &(&1.id == user.id)
           )
  end

  test "remembered tokens cannot mint a fresh session after archival", %{user: user} do
    assert {:ok, token, _claims} = Jwt.token_for_user(user, %{"purpose" => "remember_me"})

    assert {:ok, signed_in} =
             User.sign_in_with_remember_me(%{token: token}, context: @authentication_context)

    assert signed_in.id == user.id
    assert is_binary(signed_in.__metadata__.token)

    archive(user)
    tokens = stored_tokens()

    assert {:error, error} =
             User.sign_in_with_remember_me(%{token: token}, context: @authentication_context)

    assert authentication_failed?(error)
    assert stored_tokens() == tokens
  end

  test "Google skipped upserts reject archived accounts before avatar, token, or identity effects",
       %{
         user: user
       } do
    user_info = google_user_info(user)
    oauth_tokens = %{"access_token" => "test-google-token"}

    assert {:ok, signed_in} =
             User.register_with_google(user_info, oauth_tokens, context: @authentication_context)

    assert signed_in.id == user.id
    assert is_binary(signed_in.__metadata__.token)

    # Leave only the email conflict so this exercises the post-upsert result guard.
    Enum.each(UserIdentity.read!(actor: user), &UserIdentity.destroy!(&1, actor: user))

    archived = archive(user)
    identities = UserIdentity.read!(actor: archived)
    tokens = stored_tokens()

    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    on_exit(fn -> :gen_tcp.close(listener) end)
    {:ok, {_address, port}} = :inet.sockname(listener)
    user_info = Map.put(user_info, "picture", "http://127.0.0.1:#{port}/avatar.jpg")

    assert {:error, error} =
             User.register_with_google(user_info, oauth_tokens, context: @authentication_context)

    assert authentication_failed?(error)
    assert {:error, :timeout} = :gen_tcp.accept(listener, 0)
    assert stored_tokens() == tokens
    assert UserIdentity.read!(actor: archived) == identities
    assert User.get!(user.id, actor: %{system_role: :superuser}).avatar_blob_id == nil
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

  test "a linked archived Google identity cannot create or relink an account using a changed email",
       %{
         user: user
       } do
    user_info = google_user_info(user)
    oauth_tokens = %{"access_token" => "test-google-token"}

    assert {:ok, _linked} =
             User.register_with_google(user_info, oauth_tokens, context: @authentication_context)

    archived = archive(user)
    identities = UserIdentity.read!(actor: archived)
    tokens = stored_tokens()
    changed_email = unique_user_email()
    user_info = Map.put(user_info, "email", changed_email)

    assert {:error, error} =
             User.register_with_google(user_info, oauth_tokens, context: @authentication_context)

    assert authentication_failed?(error)
    assert UserIdentity.read!(actor: archived) == identities
    assert stored_tokens() == tokens

    assert {:ok, nil} =
             User.get_by_email(%{email: changed_email},
               context: @authentication_context,
               not_found_error?: false
             )
  end

  test "reset tokens cannot update an archived account, even with a supplied record", %{
    user: user,
    password_strategy: strategy
  } do
    assert {:ok, reset_token} = Password.reset_token_for(strategy, user)

    params = %{
      reset_token: reset_token,
      password: "a different password!!"
    }

    assert {:ok, updated} =
             User.password_reset_with_password(user, params, context: @authentication_context)

    assert updated.hashed_password != user.hashed_password

    assert {:ok, reset_token} = Password.reset_token_for(strategy, updated)
    archived = archive(updated)
    tokens = stored_tokens()
    params = Map.put(params, :reset_token, reset_token)

    assert {:error, error} =
             User.password_reset_with_password(archived, params, context: @authentication_context)

    assert authentication_failed?(error)
    assert stored_tokens() == tokens

    assert User.get!(archived.id, actor: %{system_role: :superuser}).hashed_password ==
             archived.hashed_password
  end

  test "password reset requests for archived accounts are silent and produce no tokens", %{
    user: user,
    password_strategy: strategy
  } do
    archive(user)
    tokens = stored_tokens()

    assert :ok = Strategy.action(strategy, :reset_request, %{email: to_string(user.email)}, [])
    assert stored_tokens() == tokens
  end

  defp archive(user), do: Ash.Seed.update!(user, %{archived_at: Date.utc_today()})

  defp stored_tokens do
    [context: @authentication_context]
    |> Token.read!()
    |> Enum.map(& &1.jti)
    |> Enum.sort()
  end

  defp google_user_info(user) do
    %{
      "sub" => "google-#{user.id}",
      "email" => to_string(user.email),
      "email_verified" => true,
      "name" => "Google User"
    }
  end

  defp authentication_failed?(%AuthenticationFailed{}), do: true

  defp authentication_failed?(%{errors: errors}), do: Enum.any?(errors, &authentication_failed?/1)

  defp authentication_failed?(_error), do: false
end
