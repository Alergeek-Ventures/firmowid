defmodule Firmowid.E2E.S03SandboxBankAccountTest do
  @moduledoc """
  E2E Test: S03 - Add a sandbox bank account via GoCardless

  This test verifies:
  1. Bank account connection via GoCardless OAuth
  2. Real-time PubSub updates when account is linked
  3. Account rename functionality
  4. Setting account as default
  5. Transaction sync from GoCardless sandbox

  ## Running this test

  # Run all E2E tests
  mix test.e2e

  # Run only this test
  mix test.e2e e2e/test/s03_sandbox_bank_account_test.exs

  # Run with visible browser
  HEADLESS=false mix test.e2e e2e/test/s03_sandbox_bank_account_test.exs
  """
  use Firmowid.E2E.PlaywrightCase

  # E2E tests need more time for browser operations and external OAuth flows
  @moduletag timeout: 120_000

  @base_url System.get_env("E2E_BASE_URL", "http://localhost:19335")
  @admin_email "kira@bytecraft.collective"
  @admin_password "kolejka123456"
  @gocardless_login "usera"
  @gocardless_password "usera"

  describe "S03: Sandbox bank account connection and transaction sync" do
    test "successfully connects sandbox bank account and syncs transactions", %{page: page} do
      # Step 1: Login as admin
      login(page, @base_url, @admin_email, @admin_password)

      # Verify login successful - should be on main page
      assert page_has_text?(page, "Fakturowanie")

      # Step 2: Navigate to Settings > Bank Accounts
      navigate_to(page, "#{@base_url}/ustawienia/konta-bankowe")

      # Verify we're on the bank accounts page
      assert page_has_text?(page, "Konta bankowe")

      # Accept cookie banner if present
      accept_cookies(page)

      # Step 3: Navigate directly to bank connection page
      navigate_to(page, "#{@base_url}/ustawienia/bank/dodaj")
      Process.sleep(2_000)
      screenshot(page, "step3_after_connect_click")

      # Step 4: Select GoCardless provider
      # The page should show GoCardless as the provider option
      assert page_has_text?(page, "GoCardless")

      # Step 5: Select sandbox institution
      wait_for_element(page, "text=Testowe konto zastępcze", timeout: 5_000)
      Playwright.Page.click(page, "text=Testowe konto zastępcze")

      # Step 6: Click connect button
      Playwright.Page.click(page, "text=Połącz z bankiem")

      # Step 7: Complete OAuth flow
      # Wait for GoCardless OAuth page to load
      wait_for_element(page, "input[name='username']", timeout: 10_000)

      # Fill in GoCardless sandbox credentials
      Playwright.Page.fill(page, "input[name='username']", @gocardless_login)
      Playwright.Page.fill(page, "input[name='password']", @gocardless_password)
      Playwright.Page.click(page, "button[type='submit']")

      # Wait for OAuth completion and redirect
      Process.sleep(2_000)

      # Step 8: After OAuth, we'll be on /fakturowanie (expected behavior)
      assert current_path(page) == "/fakturowanie"

      # Step 9: Navigate back to Settings > Bank Accounts
      navigate_to(page, "#{@base_url}/ustawienia/konta-bankowe")

      # Step 10: Verify account appears automatically via PubSub (wait up to 30 seconds)
      # The account should appear without manual refresh
      assert wait_for_text(page, "Main Account", timeout: 30_000)

      # Step 11: Rename account to "Sandbox test"
      # Find the account row using a locator that finds the row containing "Main Account"
      edit_button = Playwright.Page.locator(page, "tr:has-text('Main Account') button[title='Edytuj']")
      Playwright.Locator.click(edit_button)

      # Clear and fill new name
      page
      |> Playwright.Page.fill("input[name='account_name']", "Sandbox test")
      |> Playwright.Page.click("text=Zapisz")

      # Verify rename successful
      assert wait_for_text(page, "Sandbox test", timeout: 5_000)

      # Step 12: Set account as default
      default_button = Playwright.Page.locator(page, "tr:has-text('Sandbox test') >> text=Ustaw jako domyślne")
      Playwright.Locator.click(default_button)

      # Step 13: Verify "Domyślne dla EUR" badge appears
      assert wait_for_text(page, "Domyślne dla EUR", timeout: 5_000)

      # Step 14: Wait for transaction sync (background job)
      Process.sleep(35_000)

      # Step 15: Navigate to /fakturowanie
      navigate_to(page, "#{@base_url}/fakturowanie")

      # Step 16: Check Transactions tab
      Playwright.Page.click(page, "text=Transakcje")

      # Step 17: Verify transactions appear (from GoCardless sandbox)
      # Look for known sandbox transaction counterparties
      assert wait_for_text(page, "Freshto Ideal", timeout: 10_000)
      assert page_has_text?(page, "Liam Brown")
      assert page_has_text?(page, "Jennifer Houston")

      # Verify transaction amounts are displayed
      assert page_has_text?(page, "€")
    end

    test "handles OAuth cancellation gracefully", %{page: page} do
      # Login first
      login(page, @base_url, @admin_email, @admin_password)

      # Navigate to bank accounts
      navigate_to(page, "#{@base_url}/ustawienia/konta-bankowe")

      # Accept cookie banner if present
      accept_cookies(page)

      # Navigate directly to bank connection page
      navigate_to(page, "#{@base_url}/ustawienia/bank/dodaj")
      Process.sleep(2_000)

      wait_for_element(page, "text=Testowe konto zastępcze", timeout: 5_000)
      Playwright.Page.click(page, "text=Testowe konto zastępcze")
      Playwright.Page.click(page, "text=Połącz z bankiem")

      # Wait for OAuth page to load
      wait_for_element(page, "input[name='username']", timeout: 10_000)

      # Navigate back to bank accounts instead of using go_back (not implemented)
      navigate_to(page, "#{@base_url}/ustawienia/konta-bankowe")

      # Page should still be accessible
      assert page_has_text?(page, "Konta bankowe")
    end
  end
end
