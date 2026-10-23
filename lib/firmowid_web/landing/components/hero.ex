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
    <section class="pt-6 pb-12 lg:p-0">
      <div class="mx-auto w-[calc(100%-var(--spacing)*8)] max-w-284.75 lg:grid lg:w-[calc(100%-var(--spacing)*16)] lg:grid-cols-2 lg:items-start lg:gap-8 lg:py-19.5 lg:pt-19.25 lg:pb-19.75">
        <div class="min-w-0">
          <a
            href="https://github.com/Alergeek-Ventures/firmowid"
            target="_blank"
            rel="noopener noreferrer"
            class="relative -left-1 isolate inline-flex h-[36px] w-[221px] shrink-0 items-center justify-center gap-2 overflow-visible rounded-[25px] text-[13px]/6 font-medium transition-colors duration-300 ease-[ease] after:pointer-events-none after:absolute after:inset-[-2px] after:bg-[url('/images/landing/frames/open-source.svg')] after:bg-size-[100%_100%] after:bg-center after:bg-no-repeat after:content-[''] hover:bg-oranger-300"
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

          <h1 class="mt-7.5 text-[42px] leading-[1.1] font-bold tracking-[-0.125rem] lg:text-[4.5rem] lg:leading-[73.44px]">
            {String.replace(pgettext("landing hero headline", "KSeF invoices"), " ", "\u00A0",
              global: false
            )}<br />
            {pgettext("landing hero headline", "without limits.")}<br />
            <span class="relative bottom-1 isolate inline-block after:absolute after:-right-6 after:-bottom-1 after:-left-1 after:-z-1 after:h-5 after:bg-[url('/images/landing/decorations/hero-underline.svg')] after:bg-size-[100%_100%] after:bg-center after:bg-no-repeat after:content-['']">
              {pgettext("landing hero headline", "For PLN 0.")}
            </span>
          </h1>

          <p class="mt-6 max-w-107.5 text-h5/6.75 text-darkGrey lg:mt-5.25 lg:text-lg/7">
            {gettext(
              "Everything in one place: invoices, banking, working hours, leave, and business trips."
            )}
          </p>

          <div class="mt-6 flex flex-col gap-4 lg:mt-7.5 lg:flex-row lg:items-center lg:gap-6.25">
            <.landing_button navigate={~p"/zarejestruj"} data-landing-cta="hero_register">
              {gettext("Start for free")}
            </.landing_button>
            <.landing_button
              navigate={~p"/zaloguj"}
              variant={:outline}
              class="min-w-38.75 lg:h-14 lg:w-38.75"
              data-landing-cta="hero_login"
            >
              {gettext("Log in")}
            </.landing_button>
          </div>

          <ul class="mt-8 grid gap-4 text-[13px]/4.5 text-grey-600 lg:flex lg:flex-wrap lg:gap-x-4 lg:gap-y-2.5 [&_img]:shrink-0 [&_li]:flex [&_li]:items-center [&_li]:gap-2">
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
          class="relative mt-8 aspect-730/670 w-full lg:-mt-7 lg:ml-[-2.4%] lg:w-[116.5%]"
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
            data-active={to_string(index == 0)}
            class="absolute inset-0 size-full opacity-0 transition-opacity duration-300 ease-in-out data-[active=true]:opacity-100"
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
    <section class="border-y border-(--landing-line) bg-orange-400 py-10 text-grey-700 lg:bg-grey-50 lg:py-8 [&_a]:font-semibold [&_a]:text-(--landing-accent) [&_a]:no-underline max-lg:[&_a]:font-normal max-lg:[&_a]:text-grey-700 [&_p]:flex [&_p]:flex-col [&_p]:items-center [&_p]:gap-5 [&_p]:text-center [&_p]:text-sm/4 lg:[&_p]:flex-row lg:[&_p]:items-baseline lg:[&_p]:gap-2 lg:[&_p]:text-left lg:[&_p]:text-[13px]/5 [&_strong]:text-[44px] [&_strong]:leading-none [&_strong]:font-bold [&_strong]:whitespace-nowrap [&_strong]:text-black lg:[&_strong]:text-[1.375rem]">
      <div class="mx-auto flex w-[calc(100%-var(--spacing)*8)] max-w-284.75 flex-col gap-10 lg:mt-0.75 lg:w-[calc(100%-var(--spacing)*16)] lg:flex-row lg:justify-between lg:gap-6">
        <p class="order-1 lg:order-0">
          <span>
            {@before_company}
            <a
              href="https://alergeek.ventures"
              target="_blank"
              rel="noopener noreferrer"
              class="relative after:pointer-events-none after:absolute after:-bottom-0.5 after:left-0 after:h-px after:w-full after:bg-current after:opacity-0 after:transition-opacity after:duration-200 hover:after:opacity-100 focus-visible:after:opacity-100"
            >Alergeek Ventures</a>
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
