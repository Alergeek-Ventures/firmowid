defmodule Firmowid.AnalyticsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Analytics
  alias Firmowid.Test.Support.PosthogClient

  test "captures registration immediately with the stable user ID and only the allowed method" do
    PosthogClient.enable()

    assert :ok =
             Analytics.capture_account_created(
               %{id: "user-id", email: "private@example.com"},
               :password
             )

    assert_receive {:posthog_capture, "account_created", "user-id", %{"method" => "password"} = properties}

    assert map_size(properties) == 1

    assert :ok = Analytics.capture_account_created(%{id: "user-id"}, :google)
    assert_receive {:posthog_capture, "account_created", "user-id", %{"method" => "google"}}
  end

  test "ignores disabled analytics, missing IDs, and unsupported registration methods" do
    PosthogClient.enable()
    assert :ok = Analytics.capture_account_created(%{id: nil}, :password)
    assert :ok = Analytics.capture_account_created(%{}, :password)
    assert :ok = Analytics.capture_account_created(%{id: "user-id"}, :other)
    refute_receive {:posthog_capture, _, _, _}

    PosthogClient.disable()
    assert :ok = Analytics.capture_account_created(%{id: "user-id"}, :password)
    refute_receive {:posthog_capture, _, _, _}
  end
end
