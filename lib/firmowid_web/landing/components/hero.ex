defmodule FirmowidWeb.Landing.Components.Hero do
  @moduledoc """
  Hero and top-metrics components for the redesigned landing page.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.LiveView.Rendered

  @benefits [
    "30 dni za darmo",
    "Synchronizacja z KSeF",
    "Bezpieczne przechowywanie danych",
    "Integracja z bankami"
  ]

  @desktop_metrics [
    %{label: "Rozwijany przez Alergeek Ventures przez", value: "2 lata", width: "257px"},
    %{label: "Zgodność z KSeF:", value: "100%", width: "112px"},
    %{label: "Średni czas onboardingu:", value: "15 min", width: "160px"}
  ]

  @mobile_metrics [
    %{label: "Zgodność z KSeF", value: "100%"},
    %{label: "Średni czas onboardingu", value: "15 min"},
    %{label: "Rozwijany przez Alergeek Ventures", value: "2 lata"}
  ]

  @doc """
  Renders the landing-page hero.
  """
  @spec hero_section(map()) :: Rendered.t()
  def hero_section(assigns) do
    assigns = assign(assigns, :benefits, @benefits)

    ~H"""
    <section class="px-4 py-8 sm:px-6 lg:min-h-[calc(100vh-96px)] lg:px-10 lg:py-0">
      <div class="mx-auto max-w-[1416px]">
        <div class="flex items-end justify-between gap-8 px-0 lg:h-[730px] lg:px-[140px] lg:py-20">
          <div class="relative w-full lg:max-w-[501px]">
            <h1 class="relative text-[53px] leading-[0.98] font-bold tracking-[-0.04em] text-[#0f0f0f] sm:max-w-[620px] sm:text-[64px] lg:text-[72px] lg:leading-[1.02]">
              Fakturowanie z KSeF <br />
              <span class="relative inline-block">
                <img
                  src={~p"/images/hero_price_scribble.svg"}
                  alt=""
                  aria-hidden="true"
                  width="287"
                  height="22"
                  decoding="async"
                  class="pointer-events-none absolute bottom-[0.06em] left-[-0.04em] h-[0.24em] w-[4.1em] max-w-none sm:bottom-[0.05em] lg:bottom-[0.07em]"
                />
                <span class="relative">od 5 zł</span>
              </span>
              <br /> miesięcznie
            </h1>

            <p class="mt-6 max-w-[500px] text-[18px] leading-[1.4] text-[#4e4e4e] lg:mt-8 lg:text-[20px]">
              Wszystko w jednym miejscu: faktury, bank, godziny pracy i płace. Bez stresu,
              bez chaosu.
            </p>

            <div class="mt-8 flex flex-col gap-4 sm:max-w-[344px] lg:mt-8 lg:max-w-none lg:flex-row lg:flex-wrap lg:gap-[25px]">
              <.hero_action_button
                navigate={~p"/zarejestruj"}
                variant={:filled}
                analytics_cta="hero_register"
              >
                Zacznij za darmo
              </.hero_action_button>
              <.hero_action_button
                navigate={~p"/zaloguj"}
                variant={:outline}
                analytics_cta="hero_login"
              >
                Zaloguj się
              </.hero_action_button>
            </div>

            <ul class="mt-8 grid gap-3 text-[14px] leading-[19.5px] text-[#4e4e4e] sm:grid-cols-2 sm:gap-x-4 sm:gap-y-2 lg:mt-10 lg:flex lg:flex-wrap lg:gap-x-4 lg:gap-y-2 lg:text-[13px]">
              <li :for={benefit <- @benefits} class="flex items-center gap-1.5 whitespace-nowrap">
                <span class="text-[18px] leading-none font-bold text-[#475e45]">✓</span>
                <span>{benefit}</span>
              </li>
            </ul>
          </div>
          <div class="relative hidden h-[520px] flex-1 lg:block xl:h-[580px]">
            <.hero_screenshot_card
              id="hero-screenshot-timetracker"
              src={~p"/images/landing_screenshots/timetracker.png"}
              webp_srcset={
                "#{~p"/images/landing_screenshots/timetracker-560.webp"} 560w, #{~p"/images/landing_screenshots/timetracker-1120.webp"} 1120w"
              }
              sizes="(min-width: 1280px) 560px, 500px"
              alt="zrzut ekranu z Firmowida - ewidencja czasu pracy i lista ostatnich wpisów"
              width="1923"
              height="963"
              card_class="top-[3.75rem] left-10 z-10 w-[252px] -rotate-[11deg] xl:left-14 xl:w-[286px]"
              image_class="h-full w-auto max-w-none origin-center scale-[1.24] -translate-x-[23%] group-hover:scale-100 group-hover:-translate-x-[6%]"
            />
            <.hero_screenshot_card
              id="hero-screenshot-invoicing-list"
              src={~p"/images/landing_screenshots/invoicing_1.png"}
              webp_srcset={
                "#{~p"/images/landing_screenshots/invoicing_1-420.webp"} 420w, #{~p"/images/landing_screenshots/invoicing_1-840.webp"} 840w"
              }
              sizes="(min-width: 1280px) 420px, 370px"
              alt="zrzut ekranu z Firmowida - nieopłacone faktury i transakcje do dopasowania"
              width="1021"
              height="834"
              card_class="top-3 right-10 z-20 w-[278px] rotate-[9deg] xl:right-10 xl:w-[310px]"
              image_class="h-full w-auto max-w-none origin-center scale-[1.12] -translate-x-[7%] group-hover:scale-100 group-hover:translate-x-0"
            />
            <.hero_screenshot_card
              id="hero-screenshot-invoicing-editor"
              src={~p"/images/landing_screenshots/invoicing_2.png"}
              webp_srcset={
                "#{~p"/images/landing_screenshots/invoicing_2-700.webp"} 700w, #{~p"/images/landing_screenshots/invoicing_2-1400.webp"} 1400w"
              }
              sizes="(min-width: 1280px) 700px, 620px"
              alt="zrzut ekranu z Firmowida - podgląd i edycja faktury z wysyłką do KSeF"
              width="1711"
              height="948"
              fetchpriority="high"
              card_class="bottom-4 left-24 z-30 w-[350px] -rotate-[5deg] xl:left-28 xl:w-[395px]"
              image_class="h-full w-auto max-w-none origin-center scale-[1.22] -translate-x-[8%] -translate-y-[1%] group-hover:scale-100 group-hover:translate-x-[2%]"
            />
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the top metrics section below the hero.
  """
  @spec top_metrics_section(map()) :: Rendered.t()
  def top_metrics_section(assigns) do
    assigns =
      assigns
      |> assign(:desktop_metrics, @desktop_metrics)
      |> assign(:mobile_metrics, @mobile_metrics)

    ~H"""
    <section class="border-y border-[#e6d7ce] bg-[#dea785] px-4 py-8 sm:px-6 lg:flex lg:h-24 lg:items-center lg:bg-[#fafafa] lg:px-10 lg:py-0">
      <div class="mx-auto w-full max-w-[1416px] lg:px-[140px]">
        <div class="grid gap-8 text-center lg:hidden">
          <div :for={metric <- @mobile_metrics} class="flex flex-col items-center gap-2">
            <p class="text-[14px]/4 font-normal text-[#303030]">{metric.label}</p>
            <p class="text-[44px] leading-[1.08] font-bold text-[#0f0f0f]">{metric.value}</p>
          </div>
        </div>

        <div class="hidden h-8 w-full flex-wrap items-baseline justify-between gap-y-4 text-left lg:flex">
          <div
            :for={metric <- @desktop_metrics}
            class="flex items-baseline gap-2"
          >
            <p
              class="text-right text-[13px]/4 font-normal text-[#4e4e4e]"
              style={"width: #{metric.width}"}
            >
              {metric.label}
            </p>
            <p class="text-[22px] leading-[1.24] font-bold text-[#0f0f0f]">
              {metric.value}
            </p>
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc false
  attr :id, :string, required: true
  attr :src, :string, required: true
  attr :webp_srcset, :string, required: true
  attr :sizes, :string, required: true
  attr :alt, :string, required: true
  attr :width, :string, required: true
  attr :height, :string, required: true
  attr :fetchpriority, :string, default: nil
  attr :card_class, :string, required: true
  attr :image_class, :string, required: true

  defp hero_screenshot_card(assigns) do
    ~H"""
    <div class={[
      "group absolute hidden aspect-square overflow-hidden rounded-[28px] border-4 border-[#dea785] bg-[#f7f0eb] shadow-[0_20px_45px_rgba(87,54,35,0.16)] motion-safe:transition-transform motion-safe:duration-300 motion-safe:ease-[cubic-bezier(0.22,1,0.36,1)] motion-safe:hover:z-40 motion-safe:hover:-translate-y-7 motion-safe:hover:scale-[1.45] motion-safe:hover:rotate-0 motion-safe:hover:shadow-[0_46px_96px_rgba(87,54,35,0.3)] lg:block",
      @card_class
    ]}>
      <picture>
        <source type="image/webp" srcset={@webp_srcset} sizes={@sizes} />
        <img
          id={@id}
          src={@src}
          alt={@alt}
          width={@width}
          height={@height}
          loading="eager"
          decoding="async"
          fetchpriority={@fetchpriority}
          data-image-reveal
          phx-hook="ImageLoadReveal"
          class={[
            "absolute top-0 left-0 motion-safe:transition-transform motion-safe:duration-300 motion-safe:ease-[cubic-bezier(0.22,1,0.36,1)]",
            @image_class
          ]}
        />
      </picture>
    </div>
    """
  end

  @doc false
  attr :navigate, :string, required: true
  attr :variant, :atom, values: [:filled, :outline], required: true
  attr :analytics_cta, :string, values: ["hero_register", "hero_login"], required: true
  slot :inner_block, required: true

  defp hero_action_button(assigns) do
    ~H"""
    <.link
      kind="unstyled"
      navigate={@navigate}
      data-landing-cta={@analytics_cta}
      class={[
        "relative inline-flex min-h-[56px] items-center justify-center overflow-hidden rounded-[4px] px-8 py-4 text-base font-medium transition-transform duration-150 hover:-translate-y-0.5",
        @variant == :filled &&
          "bg-[#0f0f0f] text-white shadow-[0_2px_0_rgba(15,15,15,0.18)] before:absolute before:inset-0 before:bg-[url('/images/button_hover.svg')] before:bg-size-[100%_100%] before:bg-no-repeat before:opacity-70 before:content-['']",
        @variant == :outline &&
          "text-[#1a1a1a] before:absolute before:inset-0 before:bg-[url('/images/button_login.svg')] before:bg-size-[100%_100%] before:bg-no-repeat before:content-[''] hover:bg-black/3"
      ]}
    >
      <span class="relative z-10">{render_slot(@inner_block)}</span>
    </.link>
    """
  end
end
