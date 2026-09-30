defmodule Firmowid.Ash.Core.Changes.CaptureGoogleRegistrationTest do
  @moduledoc false
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures, only: [unique_user_email: 0]

  alias AshAuthentication.Strategy
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User
  alias Firmowid.Test.Support.PosthogClient

  test "Google registration captures a new account but not a repeat sign-in" do
    PosthogClient.enable()
    email = unique_user_email()

    user_info = %{
      "email" => email,
      "email_verified" => true,
      "name" => "Test",
      "sub" => Ecto.UUID.generate()
    }

    tokens = %{"access_token" => "test-token"}

    strategy = AshAuthentication.Info.strategy!(User, :google)

    {:ok, user} =
      Strategy.action(strategy, :register, %{user_info: user_info, oauth_tokens: tokens}, domain: Core)

    assert_receive {:posthog_capture, "account_created", distinct_id, %{"method" => "google"}}

    assert distinct_id == to_string(user.id)

    {:ok, returning_user} =
      Strategy.action(strategy, :register, %{user_info: user_info, oauth_tokens: tokens}, domain: Core)

    assert returning_user.id == user.id
    refute_receive {:posthog_capture, "account_created", _, _}
  end
end
