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
    <section class="py-[24px_48px] lg:p-0">
      <div class="mx-auto w-[calc(100%-32px)] max-w-[1139px] lg:grid lg:w-[calc(100%-64px)] lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:items-start lg:gap-8 lg:py-[77px_104px]">
        <div class="min-w-0">
          <a
            href="https://github.com/Alergeek-Ventures/firmowid"
            target="_blank"
            rel="noopener noreferrer"
            class="relative isolate inline-flex min-h-10 items-center gap-2 py-2 pr-4 pl-3 text-[13px] leading-[24px] font-medium [background:url('/images/landing/frames/open-source.svg')_center/100%_100%_no-repeat]"
          >
            <img src={~p"/images/github-mark.svg"} alt="" width="24" height="24" />
            <span>
              {@badge_before}
              <span class="text-(--landing-accent)">
                {pgettext("landing open-source badge", "open source")}
              </span>
              {@badge_after}
            </span>
          </a>

          <h1 class="mt-6 text-3xl leading-[1.14] font-bold tracking-[-0.035em] lg:mt-8.5 lg:text-[72px] lg:leading-[0.966]">
            {pgettext("landing hero headline", "KSeF invoices")}<br />
            {pgettext("landing hero headline", "without limits.")}<br />
            <span class="relative isolate inline-block [&::after]:absolute [&::after]:-right-5 [&::after]:-bottom-2 [&::after]:-left-1 [&::after]:-z-1 [&::after]:h-5 [&::after]:[content:''] [&::after]:[background:url('/images/landing/decorations/hero-underline.svg')_center/100%_100%_no-repeat] lg:[&::after]:-right-7">
              {pgettext("landing hero headline", "For PLN 0.")}
            </span>
          </h1>

          <p class="mt-6 max-w-107.5 text-h5 leading-[27px] text-darkGrey lg:mt-7.5 lg:text-lg lg:leading-[28px]">
            {gettext(
              "Everything in one place: invoices, banking, working hours, leave, and business trips."
            )}
          </p>

          <div class="mt-6 flex flex-col gap-4 lg:mt-7.5 lg:flex-row lg:gap-7">
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

          <ul class="mt-7 grid gap-4 text-[13px] leading-[18px] text-darkGrey lg:mt-8 lg:flex lg:flex-wrap lg:gap-[8px_16px] [&_img]:shrink-0 [&_li]:flex [&_li]:items-baseline [&_li]:gap-2">
            <li>
              <img src={~p"/images/landing/icons/check.svg"} alt="" width="12" height="13" />
              {gettext("Start with the free plan. No card required.")}
            </li>
            <li>
              <img src={~p"/images/landing/icons/check.svg"} alt="" width="12" height="13" />
              {gettext("KSeF synchronization")}
            </li>
            <li>
              <img src={~p"/images/landing/icons/check.svg"} alt="" width="12" height="13" />
              {gettext("Secure data storage")}
            </li>
            <li>
              <img src={~p"/images/landing/icons/check.svg"} alt="" width="12" height="13" />
              {gettext("Bank integrations")}
            </li>
          </ul>
        </div>

        <div
          id="landing-compass"
          phx-hook="LandingHero"
          phx-update="ignore"
          class="relative mt-8 aspect-730/670 w-full lg:m-[-28px_0_0_-2.4%] lg:w-[116.5%]"
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
            class={[
              "absolute inset-0 size-full opacity-[0] [transition:opacity_300ms_ease-in-out] [&.is-active]:opacity-[1]",
              index == 0 && "is-active"
            ]}
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
    <section class="py-10 [background:var(--color-orange-400)] [border-block:1px_solid_var(--landing-line)] lg:bg-grey-50 lg:py-8 [&_a]:text-(--landing-accent) [&_a]:underline-offset-[3px] [&_a]:[text-decoration:underline] [&_p]:flex [&_p]:flex-col-reverse [&_p]:items-center [&_p]:gap-2 [&_p]:text-center [&_p]:text-sm/[20px] lg:[&_p]:flex-row lg:[&_p]:gap-2 lg:[&_p]:text-left lg:[&_p]:text-[13px] [&_strong]:text-3xl [&_strong]:leading-[1.1] [&_strong]:font-bold lg:[&_strong]:text-[26px] lg:[&_strong]:whitespace-nowrap">
      <div class="mx-auto flex w-[calc(100%-32px)] max-w-[1139px] flex-col gap-10 lg:w-[calc(100%-64px)] lg:flex-row lg:justify-between lg:gap-6">
        <p class="order-1 lg:order-0">
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
