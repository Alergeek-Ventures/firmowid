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
      class={["landing-nav", @class]}
    >
      <nav class="landing-nav__panel" aria-label={gettext("Main navigation")}>
        <.link kind="unstyled" navigate={~p"/#top"} class="landing-nav__brand">
          Firmowid
        </.link>

        <div class="landing-nav__actions">
          <a href={~p"/#zespol"} class="landing-nav__text">
            {gettext("About us")}
          </a>
          <a href="https://firmowid.pl/blog" class="landing-nav__text">
            {gettext("Blog")}
          </a>
          <a
            href={@repository}
            target="_blank"
            rel="noopener noreferrer"
            class="landing-nav__text"
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
            class="landing-nav__login"
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
    assigns = assign(assigns, :variant_class, "landing-button--#{assigns.variant}")

    ~H"""
    <.link
      kind="unstyled"
      navigate={@navigate}
      external={@external}
      class={["landing-button", @variant_class, @class]}
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
      class={["landing-footer", @class]}
    >
      <div class="landing-container">
        <div class="landing-footer__cta">
          <div class="landing-footer__figure">
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

          <div class="landing-footer__copy">
            <p class="landing-footer__scribble">{gettext("YOUR MOVE!")}</p>
            <h2 class="landing-footer__heading">
              <span class="whitespace-pre-line">{gettext("Run your business\nwith a lighter mind.")}</span>
            </h2>
            <p class="landing-footer__description">
              {gettext(
                "Start with the free plan. No card. No commitment. If the software is not for you, delete your account with one click."
              )}
            </p>

            <div class="landing-footer__actions">
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

        <div class="landing-footer__links">
          <div class="landing-footer__navigation">
            <div>
              <p class="landing-footer__legend">{gettext("Product")}</p>
              <a href={~p"/funkcje"} class="landing-footer__link">{gettext("Features")}</a>
              <a href={~p"/cennik"} class="landing-footer__link">{gettext("Pricing")}</a>
              <a
                href={@repository}
                target="_blank"
                rel="noopener noreferrer"
                class="landing-footer__link"
              >
                {gettext("Source code")}
              </a>
            </div>
            <div>
              <p class="landing-footer__legend">{gettext("Company")}</p>
              <a
                href="https://alergeek.ventures/contact-details"
                target="_blank"
                rel="noopener noreferrer"
                class="landing-footer__link"
              >
                {gettext("Contact")}
              </a>
              <.link kind="unstyled" navigate={~p"/regulamin#top"} class="landing-footer__link">
                {gettext("Terms of Service")}
              </.link>
              <.link
                kind="unstyled"
                navigate={~p"/polityka-prywatnosci#top"}
                class="landing-footer__link"
              >
                {pgettext("footer-policy-link", "Privacy Policy")}
              </.link>
            </div>
          </div>

          <div class="landing-footer__brand">
            <p class="landing-footer__wordmark">Firmowid</p>
            <p class="landing-footer__tagline">
              {gettext("Invoicing, banking, and working hours.")}
              <br />{gettext("Built by entrepreneurs for entrepreneurs.")}
            </p>
          </div>

          <div class="landing-footer__bottom">
            <p class="landing-footer__legal">
              © {Date.utc_today().year} Firmowid · {@legal_entity.name}, {@legal_entity.address} · NIP {@legal_entity.nip} · KRS {@legal_entity.krs} · REGON {@legal_entity.regon}
            </p>
            <div class="landing-footer__socials">
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
