# E2E Test Configuration

# Configure Playwright to use the installed Chromium 1217 browser
# (Playwright Elixir expects revision 1148 but we've installed 1217 via npx)
headless = System.get_env("HEADLESS", "true") == "true"

executable_path =
  if headless do
    "/var/home/kosciak/.cache/ms-playwright/chromium_headless_shell-1217/chrome-headless-shell-linux64/chrome-headless-shell"
  else
    "/var/home/kosciak/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome"
  end

# Use the proper config key that Playwright.SDK.Config expects
Application.put_env(:playwright, LaunchOptions,
  headless: headless,
  executable_path: executable_path
)

ExUnit.start()
