defmodule Firmowid.E2E.PlaywrightCase do
  @moduledoc """
  Base case for Playwright E2E tests.

  Automatically tags tests as :e2e and sets up:
  - Browser context and page
  - Common imports (Firmowid.E2E.Helpers)
  - Default timeout of 120 seconds

  ## Usage

      defmodule Firmowid.E2E.MyTest do
        use Firmowid.E2E.PlaywrightCase
        
        test "my scenario", %{page: page} do
          # Test code here - Helpers functions available automatically
          navigate_to(page, "http://localhost:19335")
        end
      end
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Firmowid.E2E.Helpers

      alias Firmowid.E2E.Helpers
      # Automatically tag all tests as :e2e
      @moduletag :e2e

      # Import helper functions directly

      # Aliases for convenience
    end
  end

  setup do
    # Launch browser (headless by default, can be overridden with HEADLESS=false)
    headless = System.get_env("HEADLESS", "true") == "true"
    slow_mo = String.to_integer(System.get_env("SLOW_MO", "0"))

    # BrowserType.launch returns {session, browser} tuple
    # executable_path is configured in test_helper.exs
    {_session, browser} = Playwright.BrowserType.launch(:chromium, %{headless: headless, slowMo: slow_mo})

    # Create a new browser context
    context = Playwright.Browser.new_context(browser)

    # Create a new page
    page = Playwright.BrowserContext.new_page(context)

    # Set default viewport
    Playwright.Page.set_viewport_size(page, %{width: 1280, height: 720})

    on_exit(fn ->
      Playwright.BrowserContext.close(context)
      Playwright.Browser.close(browser)
    end)

    {:ok, %{page: page, context: context, browser: browser}}
  end
end
