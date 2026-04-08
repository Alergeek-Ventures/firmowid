defmodule Firmowid.E2E.S02KsefConnectTest do
  @moduledoc """
  E2E Test: S02 - Connect KSeF account via token

  This test verifies:
  1. Login and navigate to organization settings
  2. Paste a KSeF token into the integration section
  3. Connect to KSeF and verify connected state
  4. Disconnect from KSeF and verify disconnected state

  ## Running this test

  # Run all E2E tests
  mix test.e2e

  # Run only this test
  mix test.e2e e2e/test/s02_ksef_connect_test.exs

  # Run with visible browser
  HEADLESS=false mix test.e2e e2e/test/s02_ksef_connect_test.exs
  """
  use Firmowid.E2E.PlaywrightCase

  @moduletag timeout: 60_000

  @base_url System.get_env("E2E_BASE_URL", "http://localhost:19335")
  @admin_email "kira@bytecraft.collective"
  @admin_password "kolejka123456"
  @ksef_token "20260406-EC-4D64AD5000-176BED60A2-7C|nip-6161525811|a06968acfd8d449a9923d760fc2dbb55306534e168fa47b1bac09a255f945600"

  describe "S02: Connect KSeF account via token" do
    test "connect, verify connected state, disconnect, verify disconnected state", %{page: page} do
      # Step 1: Login as admin
      login(page, @base_url, @admin_email, @admin_password)
      assert page_has_text?(page, "Fakturowanie")

      # Step 2: Navigate to organization settings
      navigate_to(page, "#{@base_url}/ustawienia/organizacja")
      accept_cookies(page)

      # Step 3: Verify the KSeF integration section is visible
      assert wait_for_text(page, "Integracja z KSeF", timeout: 5_000)

      # Step 4: Fill the KSeF token
      wait_for_element(page, "input[placeholder='Wprowadź token KSeF']", timeout: 5_000)
      Playwright.Page.fill(page, "input[placeholder='Wprowadź token KSeF']", @ksef_token)

      # Step 5: Click "Połącz z KSeF" button
      Playwright.Page.click(page, "text=Połącz z KSeF")

      # Step 6: Verify connected state
      assert wait_for_text(page, "Połączono z KSeF", timeout: 10_000)

      # Step 7: Cleanup — disconnect from KSeF
      Playwright.Page.click(page, "text=Rozłącz")

      # Wait for the confirmation modal
      assert wait_for_text(page, "Potwierdź rozłączenie", timeout: 5_000)

      # Click the "Rozłącz" button inside the confirmation modal
      modal = Playwright.Page.locator(page, "div:has-text('Potwierdź rozłączenie')")
      disconnect_btn = Playwright.Locator.locator(modal, "button:has-text('Rozłącz')")
      disconnect_btn |> Playwright.Locator.last() |> Playwright.Locator.click()

      # Step 8: Verify disconnected state — token input and connect CTA should reappear
      assert wait_for_element(page, "input[placeholder='Wprowadź token KSeF']", timeout: 10_000)
      assert wait_for_text(page, "Połącz z KSeF", timeout: 10_000)
    end
  end
end
