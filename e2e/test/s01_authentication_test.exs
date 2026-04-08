defmodule Firmowid.E2E.S01AuthenticationTest do
  @moduledoc """
  E2E Test: S01 - Authentication

  This test verifies:
  1. Login with valid credentials
  2. Redirect to dashboard after login
  3. Navbar contains expected navigation items
  4. Sign out via user dropdown
  5. Redirect to landing page after sign out
  6. Protected route redirects to login when unauthenticated

  ## Running this test

  # Run all E2E tests
  mix test.e2e

  # Run only this test
  mix test.e2e e2e/test/s01_authentication_test.exs

  # Run with visible browser
  HEADLESS=false mix test.e2e e2e/test/s01_authentication_test.exs
  """
  use Firmowid.E2E.PlaywrightCase

  @moduletag timeout: 60_000

  @base_url System.get_env("E2E_BASE_URL", "http://localhost:19335")
  @admin_email "kira@bytecraft.collective"
  @admin_password "kolejka123456"

  describe "S01: Authentication" do
    test "login, verify navbar, sign out, and protected route redirect", %{page: page} do
      # Step 1: Navigate to login page
      navigate_to(page, "#{@base_url}/zaloguj")

      # Accept cookie banner if present
      accept_cookies(page)

      # Step 2: Log in with admin credentials
      login(page, @base_url, @admin_email, @admin_password)

      # Step 3: Verify redirect to /czasosledz after login
      assert current_path(page) == "/czasosledz"

      # Step 4: Verify navbar shows expected navigation items
      assert page_has_text?(page, "Fakturowanie")
      assert page_has_text?(page, "Analiza")
      assert page_has_text?(page, "Czasośledź")
      assert page_has_text?(page, "Zarządzanie")

      # Step 5: Sign out via user dropdown
      Playwright.Page.click(page, "#dropdown_button")
      wait_for_element(page, "#dropdown_content", timeout: 5_000)
      Playwright.Page.click(page, "#dropdown_content a[href='/sign-out']")
      wait_for_element(page, "form[action='/zaloguj']", timeout: 10_000)

      # Step 6: Verify redirect to landing page after sign out
      assert current_path(page) == "/"

      # Step 7: Verify navigating to a protected route redirects to login
      navigate_to(page, "#{@base_url}/czasosledz")
      Process.sleep(1_000)

      assert current_path(page) == "/zaloguj"
    end
  end
end
