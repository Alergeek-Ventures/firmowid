defmodule FirmowidWeb.Landing.Components.CookieConsent do
  @moduledoc """
  Cookie consent banner component.

  Displays a bottom-fixed banner on first visit allowing users to accept or reject
  analytics cookies. The preference is stored in a `cookie_consent` cookie readable
  by the server, so `Firmowid.Analytics` can switch between full and anonymous
  PostHog tracking.

  - **Accepted** — full PostHog tracking with user identification.
  - **Rejected** — anonymous PostHog tracking (no distinct user ID, no identification).

  The banner auto-hides when a preference has already been set.
  """
  use FirmowidWeb, :html

  @doc """
  Renders the cookie consent banner.

  Hidden by default via JS — the `CookieConsent` hook checks localStorage
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
                Szczegóły w naszej <a
                  href="/polityka-prywatnosci"
                  class="font-semibold text-white underline hover:text-orange-300"
                >
                  Polityce Prywatności</a>.
              </p>
            </div>
            <div class="flex shrink-0 gap-3">
              <button
                id="cookie-consent-reject"
                class="cursor-pointer rounded-lg border border-white/20 px-4 py-2 text-sm font-medium text-white/70 transition-colors hover:border-white/40 hover:text-white"
              >
                Odrzuć
              </button>
              <button
                id="cookie-consent-accept"
                class="cursor-pointer rounded-lg bg-white px-4 py-2 text-sm font-medium text-black transition-colors hover:bg-white/90"
              >
                Akceptuję
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
