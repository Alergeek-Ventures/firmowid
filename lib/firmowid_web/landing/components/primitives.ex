defmodule FirmowidWeb.Landing.Components.Primitives do
  @moduledoc """
  Navigation, actions and footer shared by public pages.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.LiveView.Rendered

  @legal_entity Application.compile_env!(:firmowid, :legal_entity)

  @repository "https://github.com/Alergeek-Ventures/firmowid"

  @doc """
  Renders the landing-page navbar.
  """
  @spec landing_navbar(map()) :: Rendered.t()
  attr :class, :any, default: nil

  def landing_navbar(assigns) do
    assigns = assign(assigns, :repository, @repository)

    ~H"""
    <header
      id="landing-navbar"
      phx-hook="LandingNavbarTheme"
      class={[
        "sticky top-0 z-50 h-(--landing-nav-height) px-2 py-1.5 transition-none lg:px-8 lg:pt-5 lg:pb-2.5 lg:[&_.landing-button]:min-h-9 lg:[&_.landing-button]:px-3 lg:[&_.landing-button]:py-1.5 lg:[&_.landing-button]:text-base/6 [&.landing-nav--dark_.landing-button--navbar-outline]:text-[#f5f1ea] [&.landing-nav--dark_.landing-nav-brand]:text-[#f5f1ea] [&.landing-nav--dark_.landing-nav-panel]:border-[rgb(245_241_234/0.28)] [&.landing-nav--dark_.landing-nav-panel]:shadow-[0_0.625rem_1.875rem_rgb(0_0_0/0.18)] [&.landing-nav--dark_.landing-nav-panel]:[background:rgb(245_241_234/0.1)] [&.landing-nav--dark_.landing-nav-text]:text-[#f5f1ea] [&.landing-nav--dark_.landing-nav-text:hover]:text-[#d2936d]",
        @class
      ]}
    >
      <nav
        class="landing-nav-panel mx-auto flex h-13 max-w-324 items-center justify-between rounded-lg border border-white/50 bg-[rgb(203_203_203/0.6)] px-4 py-1.5 backdrop-blur-md transition-[background-color,border-color,box-shadow] duration-180 lg:h-16.5 lg:px-6"
        aria-label={gettext("Main navigation")}
      >
        <.link
          kind="unstyled"
          navigate={~p"/#top"}
          class="landing-nav-brand text-lg leading-[1.2] font-extrabold text-[#0f0f0f] transition-colors duration-180 lg:text-2xl"
        >
          Firmowid
        </.link>

        <div class="hidden items-center gap-3 lg:flex lg:gap-4">
          <a
            href={~p"/#zespol"}
            class="landing-nav-text min-w-21.5 rounded-sm p-3.5 text-center text-base/6 font-medium text-[#0f0f0f] transition-colors duration-180 hover:text-orange-600"
          >
            {gettext("About us")}
          </a>
          <a
            href="https://firmowid.pl/blog"
            class="landing-nav-text min-w-19 rounded-sm p-3.5 text-center text-base/6 font-medium text-[#0f0f0f] transition-colors duration-180 hover:text-orange-600"
          >
            {gettext("Blog")}
          </a>
          <a
            href={@repository}
            target="_blank"
            rel="noopener noreferrer"
            class="landing-nav-text min-w-24 rounded-sm p-3.5 text-center text-base/6 font-medium text-[#0f0f0f] transition-colors duration-180 hover:text-orange-600"
          >
            GitHub
          </a>
          <.landing_button
            navigate={~p"/zarejestruj"}
            variant={:navbar_filled}
            data-landing-cta="navbar_trial"
          >
            {gettext("Try it")}
          </.landing_button>
          <.landing_button
            navigate={~p"/zaloguj"}
            variant={:navbar_outline}
          >
            {gettext("Log in")}
          </.landing_button>
        </div>
      </nav>
    </header>
    """
  end

  @doc """
  Renders a public-page action with brush artwork.
  """
  @spec landing_button(map()) :: Rendered.t()
  attr :navigate, :string, default: nil
  attr :external, :string, default: nil

  attr :variant, :atom,
    values: [
      :black,
      :orange,
      :outline,
      :outline_light,
      :navbar_filled,
      :navbar_outline
    ],
    default: :black

  attr :class, :any, default: nil

  attr :rest, :global, include: ~w(target rel data-landing-cta data-landing-plan data-landing-billing-period)

  slot :inner_block, required: true

  def landing_button(assigns) do
    variant_class =
      case assigns.variant do
        :black ->
          "bg-[#0f0f0f] text-white [&:hover]:[background:var(--color-grey-800)]"

        :orange ->
          "bg-[#d2936d] text-[#0f0f0f] [&:hover]:bg-[#e9c3ac]"

        :outline ->
          "min-w-37.75 text-[#0f0f0f] before:h-[54px] before:w-[153px] before:bg-[url('/images/landing/frames/button-login.svg')] before:bg-auto before:bg-center before:bg-no-repeat lg:w-37.75 lg:px-5 [.landing-pricing-card_&]:w-52 [.landing-pricing-card_&]:max-w-full [.landing-pricing-card_&]:min-w-0 [.landing-pricing-card_&]:self-center [.landing-pricing-card_&]:before:w-[210px] [.landing-pricing-card_&]:before:bg-[url('/images/landing/frames/button-pricing.svg')]"

        :outline_light ->
          "text-[#f5f1ea] before:h-[59px] before:w-[294px] before:bg-[url('/images/landing/frames/button-light.svg')] before:bg-auto before:bg-center before:bg-no-repeat hover:before:bg-[url('/images/landing/frames/button-light-hover.svg')]"

        :navbar_filled ->
          "h-9 min-h-9 w-27.25 bg-white text-[#0f0f0f] before:h-[38px] before:w-[110px] before:bg-grey-100 before:mask-[url('/images/landing/frames/nav-trial-dark.svg')] before:mask-size-auto before:mask-center before:mask-no-repeat"

        :navbar_outline ->
          "landing-button--navbar-outline h-9 min-h-9 w-29.75 text-[#0f0f0f] before:h-[38px] before:w-[120px] before:bg-white before:mask-[url('/images/landing/frames/nav-login.svg')] before:mask-size-auto before:mask-center before:mask-no-repeat"
      end

    assigns = assign(assigns, :variant_class, variant_class)

    ~H"""
    <.link
      kind="unstyled"
      navigate={@navigate}
      external={@external}
      class={[
        "landing-button relative isolate inline-flex items-center justify-center gap-2.5 px-8 py-3.5 text-center text-base/6 font-medium focus-visible:outline-2 focus-visible:outline-offset-4 disabled:pointer-events-none disabled:opacity-45 aria-disabled:pointer-events-none aria-disabled:opacity-45",
        if(@variant == :navbar_filled, do: "rounded-md", else: "rounded-sm"),
        if(@variant in [:outline, :outline_light, :navbar_filled, :navbar_outline],
          do:
            "before:pointer-events-none before:absolute before:top-1/2 before:left-1/2 before:-z-10 before:-translate-1/2"
        ),
        if(@variant not in [:navbar_filled, :navbar_outline], do: "min-h-13"),
        @variant_class,
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Renders the final CTA and the footer.
  """
  @spec cta_footer(map()) :: Rendered.t()
  attr :class, :any, default: nil

  def cta_footer(assigns) do
    assigns =
      assigns
      |> assign(:legal_entity, @legal_entity)
      |> assign(:repository, @repository)

    ~H"""
    <section
      id="cta-footer"
      data-landing-dark-surface
      class={["overflow-clip bg-grey-900 text-[#f5f1ea] lg:bg-[#0f0f0f]", @class]}
    >
      <div class="mx-auto w-[calc(100%-var(--spacing)*8)] max-w-284.75 lg:w-[calc(100%-var(--spacing)*16)]">
        <div class="flex flex-col gap-12 pt-18 pb-24 text-left lg:flex-row lg:items-start lg:gap-29.5 lg:pt-26 lg:pb-18">
          <div class="-order-1 mx-auto w-60 lg:order-0 lg:m-0 lg:w-85 lg:shrink-0 lg:grow-0 lg:basis-85 [&_img]:block [&_img]:h-auto [&_img]:w-full lg:[&_img]:h-138 lg:[&_img]:w-full lg:[&_img]:object-cover lg:[&_img]:object-center">
            <img
              id="cta-footer-figurine"
              src={~p"/images/figurine.png"}
              alt={gettext("Firmowid character holding a tablet")}
              width="905"
              height="1280"
              loading="lazy"
              decoding="async"
              data-image-reveal
              phx-hook="ImageLoadReveal"
            />
          </div>

          <div class="flex flex-col lg:flex-1 lg:pt-0 lg:[&_.landing-footer-heading]:order-0">
            <p class="mb-5 font-['Nothing_You_Could_Do',cursive] text-3xl leading-none text-[#d2936d] lg:text-[2rem]">
              {gettext("YOUR MOVE!")}
            </p>
            <h2 class="landing-footer-heading text-[3rem] leading-[.96] font-bold tracking-[-0.03em] lg:max-w-160 lg:text-[4rem] lg:leading-[.92]">
              {gettext("Run your business")}<br />
              {gettext("with a lighter mind.")}
            </h2>
            <p class="mt-4 max-w-140 text-h5/6.75 text-grey-300 lg:mt-5 lg:max-w-170 lg:text-h5">
              {gettext(
                "Start with the free plan. No card. No commitment. If the software is not for you, delete your account with one click."
              )}
            </p>

            <div class="mt-10 flex flex-col gap-4 lg:max-w-155 lg:flex-row lg:gap-6 [&_.landing-button]:min-h-14.5 lg:[&_.landing-button]:min-w-0 lg:[&_.landing-button]:flex-1 lg:[&_.landing-button]:px-3">
              <.landing_button
                navigate={~p"/zarejestruj"}
                variant={:orange}
                data-landing-cta="footer_register"
              >
                {gettext("Start for free")}
              </.landing_button>
              <.landing_button
                external="https://cal.com/franek-madej/firmowid"
                variant={:outline_light}
                data-landing-cta="footer_demo_booking"
                target="_blank"
                rel="noopener noreferrer"
              >
                {gettext("Book a 15-minute call")}
              </.landing_button>
            </div>
          </div>
        </div>

        <div class="border-t border-[#f5f1ea]/20 pt-10 pb-8 lg:grid lg:grid-cols-[minmax(0,1fr)_auto] lg:items-start lg:gap-x-17 lg:pt-12 lg:pb-10">
          <div class="grid grid-cols-2 gap-6 lg:col-2 lg:row-1 lg:gap-17">
            <div>
              <p class="mb-4 text-xs font-bold tracking-[0.08em] uppercase">
                {gettext("Product")}
              </p>
              <a
                href={~p"/funkcje"}
                class="block py-1 text-base text-[rgb(245_241_234/0.75)] [&:hover]:text-white"
              >{gettext("Features")}</a>
              <a
                href={~p"/cennik"}
                class="block py-1 text-base text-[rgb(245_241_234/0.75)] [&:hover]:text-white"
              >{gettext("Pricing")}</a>
              <a
                href={@repository}
                target="_blank"
                rel="noopener noreferrer"
                class="block py-1 text-base text-[rgb(245_241_234/0.75)] [&:hover]:text-white"
              >
                {gettext("Source code")}
              </a>
            </div>
            <div>
              <p class="mb-4 text-xs font-bold tracking-[0.08em] uppercase">
                {gettext("Company")}
              </p>
              <a
                href="https://alergeek.ventures/contact-details"
                target="_blank"
                rel="noopener noreferrer"
                class="block py-1 text-base text-[rgb(245_241_234/0.75)] [&:hover]:text-white"
              >
                {gettext("Contact")}
              </a>
              <.link
                kind="unstyled"
                navigate={~p"/regulamin#top"}
                class="block py-1 text-base text-[rgb(245_241_234/0.75)] [&:hover]:text-white"
              >
                {gettext("Terms of Service")}
              </.link>
              <.link
                kind="unstyled"
                navigate={~p"/polityka-prywatnosci#top"}
                class="block py-1 text-base text-[rgb(245_241_234/0.75)] [&:hover]:text-white"
              >
                {pgettext("footer-policy-link", "Privacy Policy")}
              </.link>
            </div>
          </div>

          <div class="order-1 mt-10 border-t border-[#f5f1ea]/20 pt-8 lg:order-0 lg:col-1 lg:row-1 lg:mt-0 lg:max-w-75 lg:border-t-0 lg:pt-0">
            <p class="text-lg font-bold lg:text-xl">Firmowid</p>
            <p class="mt-3 text-sm/normal text-[rgb(245_241_234/0.6)]">
              {gettext("Invoicing, banking, and working hours.")}
              <br />{gettext("Built by entrepreneurs for entrepreneurs.")}
            </p>
          </div>

          <div class="mt-8 flex flex-col-reverse bg-[url('/images/landing/decorations/dark-separator.svg')] bg-size-[100%_--spacing(0.5)] bg-top bg-no-repeat pt-7 text-caps-sm leading-[1.6] text-[rgb(245_241_234/0.6)] lg:col-span-full lg:row-2 lg:mt-8 lg:flex-row lg:items-center lg:justify-between lg:gap-8">
            <p>
              © {Date.utc_today().year} Firmowid · {@legal_entity.name}, {@legal_entity.address} · NIP {@legal_entity.nip} · KRS {@legal_entity.krs} · REGON {@legal_entity.regon}
            </p>
            <div class="mt-5 flex gap-4.5 text-sm lg:mt-0">
              <a href={@repository} target="_blank" rel="noopener noreferrer">GitHub</a>
              <a
                href="https://pl.linkedin.com/showcase/firmowid/"
                target="_blank"
                rel="noopener noreferrer"
              >
                LinkedIn
              </a>
              <a href="https://x.com/firmowid" target="_blank" rel="noopener noreferrer">
                Twitter
              </a>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
