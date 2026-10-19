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
        "sticky top-0 z-50 h-(--landing-nav-height) p-[6px_8px] transition-none lg:p-[20px_32px_10px] lg:[&_.landing-button]:min-h-10.5 lg:[&_.landing-button]:p-[8px_18px] lg:[&_.landing-button]:text-[15px] lg:[&_.landing-button]:leading-[24px] [&.landing-nav--dark_.landing-button--navbar-filled]:bg-[#0f0f0f] [&.landing-nav--dark_.landing-button--navbar-filled]:text-[#f5f1ea] [&.landing-nav--dark_.landing-button--navbar-filled::before]:filter-[grayscale(1)_invert(1)] [&.landing-nav--dark_.landing-button--navbar-filled:hover]:[background:rgb(245_241_234/0.14)] [&.landing-nav--dark_.landing-button--navbar-outline]:text-[#f5f1ea] [&.landing-nav--dark_.landing-nav-brand]:text-[#f5f1ea] [&.landing-nav--dark_.landing-nav-panel]:border-[rgb(245_241_234/0.28)] [&.landing-nav--dark_.landing-nav-panel]:shadow-[0_10px_30px_rgb(0_0_0/0.18)] [&.landing-nav--dark_.landing-nav-panel]:[background:rgb(245_241_234/0.1)] [&.landing-nav--dark_.landing-nav-text]:text-[#f5f1ea] [&.landing-nav--dark_.landing-nav-text:hover]:text-[#d2936d]",
        @class
      ]}
    >
      <nav
        class="landing-nav-panel mx-auto flex min-h-13 max-w-324 items-center justify-between rounded-[8px] p-[6px_16px] [backdrop-filter:blur(12px)] [background:rgb(203_203_203/0.6)] [border:1px_solid_rgb(255_255_255/0.5)] [transition:background-color_180ms_ease,border-color_180ms_ease,box-shadow_180ms_ease] lg:min-h-16.5 lg:p-[6px_24px]"
        aria-label={gettext("Main navigation")}
      >
        <.link
          kind="unstyled"
          navigate={~p"/#top"}
          class="landing-nav-brand text-lg leading-[1.2] font-bold text-[#0f0f0f] [transition:color_180ms_ease] lg:text-[28px]"
        >
          Firmowid
        </.link>

        <div class="hidden items-center gap-3 lg:flex lg:gap-4">
          <a
            href={~p"/#zespol"}
            class="landing-nav-text rounded-[5px] p-[15px_14px] text-base leading-[24px] font-medium text-[#0f0f0f] [transition:color_180ms_ease] lg:text-base [&:hover]:text-orange-600"
          >
            {gettext("About us")}
          </a>
          <a
            href="https://firmowid.pl/blog"
            class="landing-nav-text rounded-[5px] p-[15px_14px] text-base leading-[24px] font-medium text-[#0f0f0f] [transition:color_180ms_ease] lg:text-base [&:hover]:text-orange-600"
          >
            {gettext("Blog")}
          </a>
          <a
            href={@repository}
            target="_blank"
            rel="noopener noreferrer"
            class="landing-nav-text rounded-[5px] p-[15px_14px] text-base leading-[24px] font-medium text-[#0f0f0f] [transition:color_180ms_ease] lg:text-base [&:hover]:text-orange-600"
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
          "text-[#0f0f0f] [&::before]:absolute [&::before]:-z-1 [&::before]:inset-0 [&::before]:[background:url('/images/landing/button-outline.png')_center_/_100%_100%_no-repeat] [&::before]:[content:''] [&::before]:brightness-0 [&:hover]:[background:rgb(15_15_15_/_0.04)]"

        :outline_light ->
          "text-[#f5f1ea] [&::before]:absolute [&::before]:-z-1 [&::before]:inset-0 [&::before]:[background:url('/images/landing/button-outline.png')_center_/_100%_100%_no-repeat] [&::before]:[content:''] [&::before]:filter-none [&:hover]:[background:rgb(245_241_234_/_0.08)]"

        :navbar_filled ->
          "landing-button--navbar-filled text-[#0f0f0f] [&::before]:absolute [&::before]:-z-1 [&::before]:inset-0 [&::before]:[background:url('/images/button_landing_navbar_filled.svg')_center_/_100%_100%_no-repeat] [&::before]:[content:''] [&:hover]:[background:rgb(255_255_255_/_0.55)]"

        :navbar_outline ->
          "landing-button--navbar-outline text-[#0f0f0f] [&::before]:absolute [&::before]:-z-1 [&::before]:inset-0 [&::before]:[background:url('/images/button_landing_navbar.svg')_center_/_100%_100%_no-repeat] [&::before]:[content:''] [&:hover]:[background:rgb(255_255_255_/_0.28)]"
      end

    assigns = assign(assigns, :variant_class, variant_class)

    ~H"""
    <.link
      kind="unstyled"
      navigate={@navigate}
      external={@external}
      class={[
        "landing-button relative isolate inline-flex min-h-13 items-center justify-center gap-2.5 rounded-[4px] p-[14px_32px] text-center text-base leading-[24px] font-medium [transition:background-color_150ms_ease,color_150ms_ease,transform_150ms_ease] active:transform-[translateY(1px)] disabled:pointer-events-none disabled:opacity-[0.45] aria-disabled:pointer-events-none aria-disabled:opacity-[0.45] motion-reduce:active:transform-none [&:hover]:transform-[translateY(-1px)] motion-reduce:[&:hover]:transform-none",
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
      <div class="mx-auto w-[calc(100%-32px)] max-w-[1139px] lg:w-[calc(100%-64px)]">
        <div class="flex flex-col gap-12 py-[72px_96px] text-left lg:flex-row lg:items-start lg:gap-29.5 lg:py-[104px_72px]">
          <div class="-order-1 mx-auto w-60 lg:order-0 lg:m-0 lg:w-85 lg:flex-[0_0_340px] lg:basis-85 [&_img]:block [&_img]:h-auto [&_img]:w-full lg:[&_img]:h-138 lg:[&_img]:w-full lg:[&_img]:object-cover lg:[&_img]:object-center">
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
            <p class="mb-5 font-['Nothing_You_Could_Do',cursive] text-3xl leading-none text-[#d2936d] lg:text-[32px]">
              {gettext("YOUR MOVE!")}
            </p>
            <h2 class="landing-footer-heading text-[48px] leading-[.96] font-bold tracking-[-0.03em] lg:max-w-160 lg:text-[64px] lg:leading-[.92]">
              {gettext("Run your business")}<br />
              {gettext("with a lighter mind.")}
            </h2>
            <p class="mt-4 max-w-140 text-h5 leading-[27px] text-grey-300 lg:mt-5 lg:max-w-170 lg:text-h5 lg:leading-[27px]">
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

        <div class="py-[40px_32px] [border-top:1px_solid_rgb(245_241_234/0.2)] lg:grid lg:grid-cols-[minmax(0,1fr)_auto] lg:items-start lg:gap-x-17 lg:py-[48px_40px]">
          <div class="grid grid-cols-2 gap-6 lg:col-2 lg:row-1 lg:gap-17">
            <div>
              <p class="mb-4 text-xs font-bold tracking-[0.08em] uppercase">
                {gettext("Product")}
              </p>
              <a
                href={~p"/funkcje"}
                class="block py-1 text-[15px] text-[rgb(245_241_234/0.75)] [&:hover]:text-white"
              >{gettext("Features")}</a>
              <a
                href={~p"/cennik"}
                class="block py-1 text-[15px] text-[rgb(245_241_234/0.75)] [&:hover]:text-white"
              >{gettext("Pricing")}</a>
              <a
                href={@repository}
                target="_blank"
                rel="noopener noreferrer"
                class="block py-1 text-[15px] text-[rgb(245_241_234/0.75)] [&:hover]:text-white"
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
                class="block py-1 text-[15px] text-[rgb(245_241_234/0.75)] [&:hover]:text-white"
              >
                {gettext("Contact")}
              </a>
              <.link
                kind="unstyled"
                navigate={~p"/regulamin#top"}
                class="block py-1 text-[15px] text-[rgb(245_241_234/0.75)] [&:hover]:text-white"
              >
                {gettext("Terms of Service")}
              </.link>
              <.link
                kind="unstyled"
                navigate={~p"/polityka-prywatnosci#top"}
                class="block py-1 text-[15px] text-[rgb(245_241_234/0.75)] [&:hover]:text-white"
              >
                {pgettext("footer-policy-link", "Privacy Policy")}
              </.link>
            </div>
          </div>

          <div class="order-1 mt-10 pt-8 [border-top:1px_solid_rgb(245_241_234/0.2)] lg:order-0 lg:col-1 lg:row-1 lg:mt-0 lg:max-w-75 lg:pt-0 lg:[border-top:0]">
            <p class="text-lg font-bold lg:text-[24px]">Firmowid</p>
            <p class="mt-3 text-[13px] leading-normal text-[rgb(245_241_234/0.6)]">
              {gettext("Invoicing, banking, and working hours.")}
              <br />{gettext("Built by entrepreneurs for entrepreneurs.")}
            </p>
          </div>

          <div class="mt-8 flex flex-col-reverse text-caps-sm leading-[1.6] text-[rgb(245_241_234/0.6)] lg:col-span-full lg:row-2 lg:mt-8 lg:flex-row lg:items-center lg:justify-between lg:gap-8 lg:pt-7 lg:[border-top:1px_solid_rgb(245_241_234/0.2)]">
            <p>
              © {Date.utc_today().year} Firmowid · {@legal_entity.name}, {@legal_entity.address} · NIP {@legal_entity.nip} · KRS {@legal_entity.krs} · REGON {@legal_entity.regon}
            </p>
            <div class="mt-5 flex gap-4.5 text-[13px] lg:mt-0">
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
