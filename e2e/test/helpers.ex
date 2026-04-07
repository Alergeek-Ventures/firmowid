defmodule Firmowid.E2E.Helpers do
  @moduledoc """
  Helper functions for E2E tests.
  """

  @doc """
  Navigate to a URL and wait for page to load.
  """
  def navigate_to(page, url) do
    Playwright.Page.goto(page, url)
    # wait_for_load_state has a bug in Playwright Elixir, use wait_for_selector instead.
    # Page.wait_for_selector accepts a broader options map including :state.
    Playwright.Page.wait_for_selector(page, "body", %{state: "visible"})
  end

  @doc """
  Login with email and password.
  """
  def login(page, base_url, email, password) do
    navigate_to(page, "#{base_url}/zaloguj")

    Playwright.Page.fill(page, "input[name='user[email]']", email)
    Playwright.Page.fill(page, "input[name='user[password]']", password)
    Playwright.Page.click(page, "button[type='submit']")

    # Wait for login to complete - look for the user menu or dashboard.
    # Use Page.wait_for_selector which accepts %{state: ...} in its type spec.
    Playwright.Page.wait_for_selector(page, "text=Cześć", %{state: "visible", timeout: 10_000})
  end

  @doc """
  Accept cookies if the banner is present.
  """
  def accept_cookies(page) do
    # Check if cookie banner is present and accept it
    if page_has_text?(page, "Akceptuję") do
      Playwright.Page.click(page, "text=Akceptuję")
      Process.sleep(500)
    else
      :ok
    end
  end

  @doc """
  Check if the page contains the given text.
  """
  def page_has_text?(page, text) do
    locator = Playwright.Page.locator(page, "text=#{text}")
    Playwright.Locator.count(locator) > 0
  end

  @doc """
  Wait for text to appear on the page.
  Returns true if found, raises on timeout.
  """
  def wait_for_text(page, text, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    # Use Page.wait_for_selector which accepts %{state: ...} in its type spec,
    # unlike Locator.wait_for which only accepts %{timeout: ...}.
    # wait_for_selector returns an ElementHandle on success or raises on timeout.
    Playwright.Page.wait_for_selector(page, "text=#{text}", %{state: "visible", timeout: timeout})
    true
  rescue
    _ -> false
  end

  @doc """
  Get the current path from the page URL.
  """
  def current_path(page) do
    page
    |> Playwright.Page.url()
    |> URI.parse()
    |> Map.get(:path)
  end

  @doc """
  Take a screenshot and save it to the e2e/screenshots directory.
  """
  def screenshot(page, name) do
    path = Path.join(["e2e", "screenshots", "#{name}.png"])
    File.mkdir_p!(Path.dirname(path))

    Playwright.Page.screenshot(page, %{path: path, full_page: true})
    path
  end

  @doc """
  Wait for an element to be visible.
  """
  def wait_for_element(page, selector, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    # Use Page.wait_for_selector which accepts %{state: ...} in its type spec,
    # unlike Locator.wait_for which only accepts %{timeout: ...}.
    Playwright.Page.wait_for_selector(page, selector, %{state: "visible", timeout: timeout})
  end

  @doc """
  Clear browser cookies and storage.
  """
  def clear_session(page) do
    Playwright.Page.evaluate(page, "() => { localStorage.clear(); sessionStorage.clear(); }")
    Playwright.BrowserContext.clear_cookies(Playwright.Page.context(page))
  end
end
