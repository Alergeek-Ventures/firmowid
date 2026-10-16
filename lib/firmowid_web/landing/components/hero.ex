defmodule FirmowidWeb.Landing.Components.Hero do
  @moduledoc """
  Hero, animated compass and development metrics for the public website.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.Landing.Components.Primitives, only: [landing_button: 1]

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the hero and four aligned compass exports.
  """
  @spec hero_section(map()) :: Rendered.t()
  def hero_section(assigns) do
    [badge_before, badge_after] =
      "Firmowid is %{open_source}"
      |> gettext(open_source: "__OPEN_SOURCE__")
      |> String.split("__OPEN_SOURCE__", parts: 2)

    assigns =
      assigns
      |> assign(:states, for(state <- 1..4, do: "character-#{state}.svg"))
      |> assign(badge_before: badge_before, badge_after: badge_after)

    ~H"""
    <section class="landing-hero">
      <div class="landing-container landing-hero__layout">
        <div class="min-w-0">
          <a
            href="https://github.com/Alergeek-Ventures/firmowid"
            target="_blank"
            rel="noopener noreferrer"
            class="landing-hero__badge"
          >
            <img src={~p"/images/github-mark.svg"} alt="" width="24" height="24" />
            <span>
              {@badge_before}
              <span class="landing-hero__badge-accent">
                {pgettext("landing open-source badge", "open source")}
              </span>
              {@badge_after}
            </span>
          </a>

          <h1 class="landing-hero__heading">
            {pgettext("landing hero headline", "KSeF invoices")}<br />
            {pgettext("landing hero headline", "without limits.")}<br />
            <span class="landing-hero__price">
              {pgettext("landing hero headline", "For PLN 0.")}
            </span>
          </h1>

          <p class="landing-hero__description">
            {gettext(
              "Everything in one place: invoices, banking, working hours, leave, and business trips."
            )}
          </p>

          <div class="landing-hero__actions">
            <.landing_button navigate={~p"/zarejestruj"} data-landing-cta="hero_register">
              {gettext("Start for free")}
            </.landing_button>
            <.landing_button
              navigate={~p"/zaloguj"}
              variant={:outline}
              data-landing-cta="hero_login"
            >
              {gettext("Log in")}
            </.landing_button>
          </div>

          <ul class="landing-hero__benefits">
            <li>
              <span aria-hidden="true">✓</span>
              {gettext("Start with the free plan. No card required.")}
            </li>
            <li>
              <span aria-hidden="true">✓</span>
              {gettext("KSeF synchronization")}
            </li>
            <li>
              <span aria-hidden="true">✓</span>
              {gettext("Secure data storage")}
            </li>
            <li>
              <span aria-hidden="true">✓</span>
              {gettext("Bank integrations")}
            </li>
          </ul>
        </div>

        <div
          id="landing-compass"
          phx-hook="LandingHero"
          phx-update="ignore"
          class="landing-compass"
          role="img"
          aria-label={
            gettext("Firmowid connects invoices and KSeF, banking, time tracking, and your team.")
          }
        >
          <img
            :for={{state, index} <- Enum.with_index(@states, 0)}
            src={~p"/images/landing/#{state}"}
            alt=""
            width="730"
            height="670"
            decoding="async"
            fetchpriority={if index == 0, do: "high", else: "auto"}
            data-state={index}
            class={["landing-compass__state", index == 0 && "is-active"]}
          />
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the development metrics in their desktop and mobile reading orders.
  """
  @spec top_metrics_section(map()) :: Rendered.t()
  def top_metrics_section(assigns) do
    [before_company, after_company] =
      "Developed by %{company} for"
      |> gettext(company: "Alergeek Ventures")
      |> String.split("Alergeek Ventures", parts: 2)

    assigns = assign(assigns, before_company: before_company, after_company: after_company)

    ~H"""
    <section class="landing-metrics">
      <div class="landing-container landing-metrics__layout">
        <p class="landing-metrics__development">
          <span>
            {@before_company}
            <a href="https://alergeek.ventures" target="_blank" rel="noopener noreferrer">
              Alergeek Ventures
            </a>
            {@after_company}
          </span>
          <strong>{gettext("2 years")}</strong>
        </p>
        <p>
          <span>{gettext("Supported banks and fintechs")}</span>
          <strong>29</strong>
        </p>
        <p>
          <span>{gettext("Average onboarding time")}</span>
          <strong>{gettext("%{minutes} min", minutes: 15)}</strong>
        </p>
      </div>
    </section>
    """
  end
end
