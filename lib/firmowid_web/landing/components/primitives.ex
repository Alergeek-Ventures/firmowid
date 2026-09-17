defmodule FirmowidWeb.Landing.Components.Primitives do
  @moduledoc """
  Shared landing-page primitives.

  This module contains reusable public-facing components that are shared between
  the homepage and legal pages.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the landing-page navbar.
  """
  @spec landing_navbar(map()) :: Rendered.t()
  attr :class, :any, default: nil

  def landing_navbar(assigns) do
    ~H"""
    <header
      id="landing-navbar"
      phx-hook="LandingNavbarTheme"
      class={["landing-nav sticky top-0 z-50 h-24 px-4 pt-4 sm:px-6 lg:px-10 lg:pt-6", @class]}
    >
      <nav class="landing-nav__panel mx-auto flex max-w-[1296px] items-center justify-between rounded-lg border border-white/50 bg-black/10 p-4 shadow-[0_10px_30px_rgba(15,15,15,0.05)] backdrop-blur-sm sm:px-6 lg:py-2">
        <.link
          kind="unstyled"
          navigate={~p"/#top"}
          class="landing-nav__text text-base font-extrabold text-[#0f0f0f] sm:text-[28px]"
        >
          Firmowid
        </.link>

        <div class="hidden items-center gap-2 lg:flex">
          <a
            href="/#zespol"
            class="landing-nav__text rounded-[5px] px-5 py-[15px] text-base font-medium text-[#0f0f0f] transition-colors hover:text-[#7a4a2d]"
          >
            {gettext("About us")}
          </a>
          <a
            href="/#cta-footer"
            data-landing-cta="navbar_trial"
            class="landing-nav__text landing-nav__trial rounded-[5px] border-2 border-[#f5f5f5] px-4 py-2 text-base font-medium text-[#0f0f0f] transition-colors hover:border-[#d7c8bd] hover:bg-white/40"
          >
            {gettext("Try it")}
          </a>
        </div>
      </nav>
    </header>
    """
  end

  @doc """
  Renders the final CTA and footer section.
  """
  @spec cta_footer(map()) :: Rendered.t()
  attr :class, :any, default: nil

  def cta_footer(assigns) do
    ~H"""
    <section
      id="cta-footer"
      data-landing-dark-surface
      class={[
        "relative overflow-clip bg-[#0f0f0f] text-white",
        @class
      ]}
    >
      <div class="mx-auto max-w-[1419px] px-4 pt-20 pb-0 sm:px-6 lg:px-[140px] lg:pt-[120px]">
        <div class="flex flex-col gap-10 lg:flex-row lg:items-start lg:justify-between lg:gap-8">
          <div class="max-w-[680px]">
            <p class="hidden font-['Nothing_You_Could_Do',cursive] text-[32px] leading-normal text-[#d2936d] lg:block">
              {gettext("YOUR MOVE!")}
            </p>
            <h2 class="mt-2 text-[48px] leading-[0.98] font-bold tracking-[-0.03em] text-[#fafafa] lg:mt-4 lg:text-[64px] lg:leading-[57px]">
              {gettext("Run your business")} <br />{gettext("with a lighter mind.")}
            </h2>
            <p class="mt-1 text-right font-['Nothing_You_Could_Do',cursive] text-[41px] leading-[1.2] text-[#d2936d] lg:hidden">
              {gettext("YOUR MOVE!")}
            </p>
            <p class="mt-6 max-w-[680px] text-[18px] leading-[27px] text-[#dddddd]">
              {gettext(
                "30 days free. No credit card. No commitment. If the software is not for you, delete your account with one click."
              )}
            </p>

            <div class="mt-8 flex flex-col gap-6 sm:max-w-[358px] lg:max-w-none lg:flex-row lg:gap-8">
              <.link
                kind="unstyled"
                navigate={~p"/zarejestruj"}
                data-landing-cta="footer_register"
                class="relative flex w-full shrink-0 items-center justify-center overflow-hidden rounded-sm border-2 border-[#d2936d] bg-[#d2936d] p-4 text-base font-medium text-black transition-transform duration-150 before:absolute before:inset-0 before:bg-[url('/images/button_hover.svg')] before:bg-size-[100%_100%] before:bg-no-repeat before:opacity-45 before:content-[''] hover:-translate-y-0.5 lg:w-auto lg:text-[20px]"
              >
                <span class="relative z-10">{gettext("Start for free")}</span>
              </.link>
              <a
                href="https://cal.com/franek-madej/firmowid"
                data-landing-cta="footer_demo_booking"
                target="_blank"
                rel="noopener noreferrer"
                class="relative flex shrink-0 items-center justify-center overflow-hidden rounded-sm border-2 border-white/80 p-4 text-base font-medium text-white transition-transform duration-150 hover:-translate-y-0.5 hover:bg-white/5 lg:text-[20px]"
              >
                <span class="relative z-10">{gettext("Book a 15-minute call")}</span>
              </a>
            </div>
          </div>

          <div class="hidden lg:block lg:pr-[33px]">
            <img
              id="cta-footer-figurine"
              src={~p"/images/figurine.png"}
              alt="Ilustracja Firmowida"
              width="905"
              height="1280"
              loading="lazy"
              decoding="async"
              data-image-reveal
              phx-hook="ImageLoadReveal"
              class="h-auto w-[427px] object-contain object-bottom"
            />
          </div>
        </div>

        <div class="mt-16 border-t border-[rgba(78,78,78,0.3)] pt-10 lg:mt-[60px] lg:pt-[104px]">
          <div class="grid gap-8 lg:grid-cols-[260px_1fr] lg:items-start lg:justify-between">
            <div>
              <p class="text-[16px] font-bold text-[#f5f1ea] lg:text-[22px]">Firmowid</p>
              <p class="mt-2 text-[12px] leading-[1.4] text-[rgba(245,241,234,0.6)] lg:text-[14px]">
                {gettext("Invoicing, banking, and working hours.")}
                <br class="hidden lg:block" />{gettext("Built by entrepreneurs for entrepreneurs.")}
              </p>
            </div>

            <div class="grid gap-8 sm:grid-cols-3 lg:flex lg:justify-end lg:gap-[68px]">
              <div class="space-y-4">
                <p class="text-[12px] font-semibold tracking-[0.12em] text-[#f5f1ea] uppercase">
                  {gettext("Product")}
                </p>
                <div class="space-y-2 text-[14px] text-[rgba(245,241,234,0.6)]">
                  <a href="/#funkcje" class="block hover:text-white">{gettext("Features")}</a>
                  <a href="/#cennik" class="block hover:text-white">{gettext("Pricing")}</a>
                  <a
                    href="https://github.com/Alergeek-Ventures/firmowid"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="block hover:text-white"
                  >{gettext("Source code")}</a>
                </div>
              </div>
              <div class="space-y-4">
                <p class="text-[12px] font-semibold tracking-[0.12em] text-[#f5f1ea] uppercase">
                  {gettext("Company")}
                </p>
                <div class="space-y-2 text-[14px] text-[rgba(245,241,234,0.6)]">
                  <a
                    href="https://alergeek.ventures/contact-details"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="block hover:text-white"
                  >
                    {gettext("Contact")}
                  </a>
                  <.link kind="unstyled" navigate={~p"/regulamin#top"} class="block hover:text-white">
                    {gettext("Terms of Service")}
                  </.link>
                  <.link
                    kind="unstyled"
                    navigate={~p"/polityka-prywatnosci#top"}
                    class="block hover:text-white"
                  >
                    {pgettext("footer-policy-link", "Privacy Policy")}
                  </.link>
                </div>
              </div>
            </div>
          </div>

          <div class="mt-8 border-t border-[rgba(78,78,78,0.3)] py-8 lg:mt-8 lg:pb-10">
            <div class="flex flex-col gap-4 text-[10px] text-[rgba(245,241,234,0.6)] lg:flex-row lg:items-center lg:justify-between lg:text-xs">
              <p>
                {gettext("© %{year} Firmowid (Alergeek Ventures). All rights reserved.",
                  year: Date.utc_today().year
                )}
              </p>
              <div class="hidden gap-4 lg:flex">
                <a
                  href="https://pl.linkedin.com/showcase/firmowid/"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="hover:text-white"
                >
                  LinkedIn
                </a>
                <a
                  href="https://x.com/firmowid"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="hover:text-white"
                >
                  Twitter
                </a>
                <a
                  href="https://www.facebook.com/Firmowid/"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="hover:text-white"
                >
                  Facebook
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
