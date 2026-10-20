defmodule Firmowid.Ash.Core.User.AuthenticationTest do
  @moduledoc "Regression coverage for archived members across authentication entry points."

  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures

  alias AshAuthentication.Info
  alias AshAuthentication.Strategy
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Core.UserIdentity

  @authentication_context %{private: %{ash_authentication?: true}}

  setup do
    admin = admin_fixture()
    user = user_in_org_fixture(admin.organization_id)
    user = Ash.Seed.update!(user, %{confirmed_at: DateTime.utc_now()})
    {:ok, password_strategy} = Info.strategy(User, :password)

    %{admin: admin, user: user, password_strategy: password_strategy}
  end

  test "an archived member signs in to an account without an organization", %{
    admin: admin,
    user: user,
    password_strategy: strategy
  } do
    {:ok, _member} = Core.archive_member(user.member, actor: admin, tenant: user.organization_id)

    params = %{email: to_string(user.email), password: valid_user_password()}
    assert {:ok, signed_in} = Strategy.action(strategy, :sign_in, params, [])
    assert signed_in.id == user.id
    assert signed_in.organization_id == nil
    assert is_binary(signed_in.__metadata__.token)
  end

  test "an admin still lists the archived member", %{admin: admin, user: user} do
    {:ok, _member} = Core.archive_member(user.member, actor: admin, tenant: user.organization_id)

    assert [archived] =
             Core.list_users!(%{status: :archived}, actor: admin, tenant: admin.organization_id)

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

  defp google_user_info(user) do
    %{
      "sub" => "google-#{user.id}",
      "email" => to_string(user.email),
      "email_verified" => true,
      "name" => "Google User"
    }
  end
end
