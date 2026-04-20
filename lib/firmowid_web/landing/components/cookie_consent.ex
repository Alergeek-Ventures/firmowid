defmodule FirmowidWeb.Landing.Components.CookieConsent do
  @moduledoc """
  Cookie consent banner component.

  Displays a bottom-fixed banner on first visit allowing users to accept or reject
  analytics cookies. The preference is stored in a `cookie_consent` cookie used
  by frontend telemetry initialization.

  - **Accepted** — frontend PostHog and Sentry initialization is allowed.
  - **Rejected** — frontend analytics/monitoring SDKs are not initialized.

  The banner auto-hides when a preference has already been set.
  """
  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  @doc """
  Renders the cookie consent banner.

  Hidden by default via JS — the `CookieConsent` hook checks cookies
  and reveals the banner only when no preference has been recorded.
  """
  def cookie_consent_banner(assigns) do
    ~H"""
    <div
      id="cookie-consent-banner"
      phx-hook="CookieConsent"
      class="fixed inset-x-0 bottom-0 z-100 hidden"
    >
      <div class="mx-auto max-w-4xl p-4">
        <div class="rounded-xl border border-white/10 bg-black/95 px-6 py-5 shadow-2xl backdrop-blur-sm">
          <div class="flex flex-col items-start gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div class="flex-1 text-sm text-white/80">
              <p>
                Używamy plików cookies do analityki, aby ulepszać Firmowida.
                Szczegóły w naszej <.link
                  kind="unstyled"
                  navigate={~p"/polityka-prywatnosci"}
                  class="font-semibold text-white underline hover:text-orange-300"
                >
                   Polityce Prywatności</.link>.
              </p>
            </div>
            <div class="flex shrink-0 gap-3">
              <FirmowidWeb.DesignSystem.Components.Button.button
                id="cookie-consent-reject"
                type="button"
                variant="outline"
                size="small"
                class="border-white/20 text-white/70 hover:border-white/40 hover:bg-transparent hover:text-white active:bg-white/10 disabled:border-white/10 disabled:text-white/40"
              >
                Odrzuć
              </FirmowidWeb.DesignSystem.Components.Button.button>
              <FirmowidWeb.DesignSystem.Components.Button.button
                id="cookie-consent-accept"
                type="button"
                variant="secondary"
                size="small"
                class="bg-white text-black hover:bg-white/90 active:bg-white/80"
              >
                Akceptuję
              </FirmowidWeb.DesignSystem.Components.Button.button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
