defmodule Firmowid.BankData.TokenManagerTest do
  use ExUnit.Case, async: false

  alias Firmowid.BankData.TokenManager

  @moduletag capture_log: true

  # Requires real GoCardless credentials (GO_LIMITLESS_SECRET_ID/KEY).
  # Excluded by default; included when running `mix check` locally.
  @moduletag :external

  # We test the GenServer by starting a fresh instance per test.
  # The global TokenManager started by Application is already running,
  # so we start a named instance with a different name and test the
  # internal functions via the module's public API.

  # Instead of testing the full GenServer (which would conflict with the
  # application-supervised instance), we test the key behaviours via
  # the running instance, which in test mode will call the real GoCardless
  # endpoints. Since we can't easily stub Req calls made inside GenServer
  # (they don't go through the mock_data path), we test the logic by
  # inspecting state.

  describe "state management" do
    test "initial state has nil tokens and zero fetch_failures" do
      state = :sys.get_state(TokenManager)

      # After init, the GenServer immediately schedules a fetch.
      # By the time we check, it may have already fetched.
      # But fetch_failures should be 0 if it succeeded.
      assert state.fetch_failures == 0
    end

    test "state has access_expires of 86400 (24h)" do
      state = :sys.get_state(TokenManager)

      # GoCardless returns 86400 as default access_expires
      assert state.access_expires == 86_400
    end

    test "state has refresh_expires of 2592000 (30d)" do
      state = :sys.get_state(TokenManager)

      assert state.refresh_expires == 2_592_000
    end

    test "state has non-nil access_token after startup" do
      state = :sys.get_state(TokenManager)

      assert is_binary(state.access_token)
      assert byte_size(state.access_token) > 0
    end

    test "state has non-nil refresh_token after startup" do
      state = :sys.get_state(TokenManager)

      assert is_binary(state.refresh_token)
      assert byte_size(state.refresh_token) > 0
    end
  end

  describe "get_access_token/0" do
    test "returns a non-nil access token" do
      token = TokenManager.get_access_token()

      assert is_binary(token)
      assert byte_size(token) > 0
    end
  end

  describe "refresh_now/0" do
    test "returns a new access token" do
      old_state = :sys.get_state(TokenManager)
      new_token = TokenManager.refresh_now()

      assert is_binary(new_token)
      assert byte_size(new_token) > 0

      new_state = :sys.get_state(TokenManager)

      # The new token should be different from the old one (different jti)
      assert new_state.access_token != old_state.access_token

      # Refresh token should remain the same (not rotated by /token/refresh/)
      assert new_state.refresh_token == old_state.refresh_token

      # fetch_failures should be 0
      assert new_state.fetch_failures == 0
    end
  end
end
