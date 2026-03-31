defmodule FirmowidWeb.Landing.Components.Landing do
  @moduledoc """
  Landing page components for Firmowid marketing site.
  Designed to match the Figma export precisely.
  """
  use FirmowidWeb, :html

  # Container max-width matching PDF margins (160px on desktop)
  @container_class "max-w-[1330px] w-full mx-auto px-6 lg:px-10"

  @doc """
  Renders the landing page navbar - minimal, clean design matching Figma.
  Layout: Logo | Nav Links (spread across)
  """
  attr :class, :any, default: nil

  def landing_navbar(assigns) do
    ~H"""
    <nav
      id="landing-navbar"
      class={[
        "fixed top-0 z-50 w-full px-6 pt-2 transition-colors duration-500 md:pt-6 lg:px-10",
        @class
      ]}
      phx-hook="NavbarScroll"
    >
      <div
        id="navbar-container"
        class="mx-auto flex max-w-7xl items-center justify-between rounded-lg bg-black/10 px-6 py-2 backdrop-blur-sm transition-all duration-500"
      >
        <%!-- Logo --%>
        <a
          href="/"
          id="navbar-logo"
          class="text-[28px] font-extrabold text-black no-underline transition-colors duration-500 select-none"
        >
          Firmowid
        </a>

        <%!-- Right nav links - hidden on mobile --%>
        <div class="hidden items-center gap-4 text-[16px] font-medium text-black md:flex">
          <a
            href="https://alergeek.ventures/"
            target="_blank"
            rel="noopener noreferrer"
            class="navbar-link rounded-[5px] px-5 py-[15px] transition-colors duration-500 hover:text-orange-700"
          >
            O nas
          </a>
          <a
            href="#cta-footer"
            class="group navbar-link relative z-20 rounded-[5px] px-4 py-2 transition-colors duration-500 hover:text-orange-700"
          >
            <span class="relative z-10">Wypróbuj</span>
            <img
              src={~p"/images/button_landing_navbar.svg"}
              alt="Decorative frame"
              class="pointer-events-none absolute inset-0 size-full"
            />
            <img
              src={~p"/images/button_landing_navbar_filled.svg"}
              alt="Decorative frame"
              class="pointer-events-none absolute inset-0 size-full opacity-0 transition-opacity duration-500 group-hover:opacity-100"
            />
          </a>
        </div>
      </div>
    </nav>
    """
  end

  @doc """
  Renders the Alergeek attribution and logo.
  """
  attr :class, :any, default: nil

  def alergeek_attribution(assigns) do
    ~H"""
    <div class={["absolute top-[100px] flex w-full flex-col items-center px-6 lg:px-10", @class]}>
      <div class="w-full max-w-7xl pl-6">
        <%!-- Spacer to account for fixed navbar height --%>
        <span class="hidden items-baseline gap-1.5 md:flex">
          <span class="font-light text-black">Opracowane i wdrożone przez</span>
          <a
            href="https://alergeek.ventures/"
            target="_blank"
            rel="noopener noreferrer"
            class="font-logo hover:text-grey-700 font-bold text-black"
          >
            Alergeek Ventures
          </a>
        </span>
      </div>
    </div>
    """
  end

  @doc """
  Renders the hero section with large lowercase headline.
  PDF shows: Large bold headline, smaller description, CTAs, "Dowiedz się więcej" link
  """
  attr :class, :any, default: nil

  def hero_section(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <section class={["flex min-h-screen flex-col", @class]}>
      <div class="flex h-screen w-full flex-1 flex-col px-6 lg:px-10">
        <div class="mx-auto flex w-full max-w-7xl flex-1 flex-col gap-0 md:pl-6">
          <%!-- Scrollable container for main hero content --%>
          <div class="flex flex-1 items-center justify-center overflow-y-auto">
            <div class="grid w-full items-center gap-8 md:grid-cols-2 md:gap-[22px]">
              <%!-- Left column: copy and CTAs, vertically centered --%>
              <div class="flex min-w-[408px] flex-col gap-[25px] pt-32">
                <div class="flex flex-col gap-[30px]">
                  <h1 class="text-[54px] leading-normal font-bold tracking-tight text-black uppercase">
                    prowadź firmę <br />z lżejszą głową
                  </h1>
                  <div class="space-y-4 text-[20px] leading-normal font-medium text-black">
                    <p>
                      Firmowid automatyzuje fakturowanie, integruje się z KSeF,
                      pilnuje budżetów i czasu pracy Twoich pracowników.
                    </p>
                    <p>
                      A Ty? Ty skupiasz się na swoim biznesie.
                    </p>
                  </div>
                </div>
                <div class="flex items-center gap-[25px]">
                  <.link
                    navigate={~p"/zaloguj"}
                    class="hover:bg-grey-200 text-grey-900 relative rounded px-8 py-4 text-base font-medium text-nowrap transition-colors duration-500"
                  >
                    Zaloguj się
                    <img
                      src={~p"/images/button_login.svg"}
                      alt="Arrow right"
                      class="pointer-events-none absolute top-0 right-0 size-full"
                    />
                  </.link>
                  <.link
                    navigate={~p"/zarejestruj"}
                    class="disabled:bg-grey-800 disabled:text-grey-400 rounded bg-black px-8 py-4 text-base font-medium text-nowrap text-white transition-colors duration-400 hover:bg-orange-700 disabled:cursor-default"
                  >
                    Wypróbuj Firmowida
                  </.link>
                </div>
              </div>

              <%!-- Right column: image only --%>
              <div class="flex max-h-[90vh] items-center justify-center self-stretch overflow-hidden">
                <img
                  src={~p"/images/figurine.png"}
                  alt="Firmowid"
                  class="size-full max-h-full max-w-[590px] object-contain object-bottom"
                />
              </div>
            </div>
          </div>

          <%!-- Sticky button at bottom of scroll context --%>
          <div class="bottom-0 flex items-center justify-center">
            <a
              href="#ksef"
              class="bg-grey-100 text-darkGrey mb-2 inline-flex flex-col items-center rounded-md px-8 pt-4 text-base font-medium transition-colors duration-500 hover:text-black"
            >
              Dowiedz się więcej
              <svg
                width="24"
                height="24"
                viewBox="0 0 24 24"
                fill="none"
                xmlns="http://www.w3.org/2000/svg"
              >
                <path
                  d="M7 6L12 11L17 6"
                  stroke="#A5582B"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
                <path
                  d="M7 13L12 18L17 13"
                  stroke="#8B3F13"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </a>
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders a small tag/pill.
  :default - subtle border style
  :accent - filled orange background (for "nowość")
  """
  attr :label, :string, required: true
  attr :variant, :atom, values: [:default, :accent], default: :default

  def tag(assigns) do
    ~H"""
    <span class={[
      "inline-flex rounded-2xl px-4 py-1 text-[14px]",
      if(@variant == :accent,
        do: "text-turquoise-700 bg-[#8BC9C94D]",
        else: "bg-orangeBg text-orangeText"
      )
    ]}>
      {@label}
    </span>
    """
  end

  @doc """
  Renders a feature section with text and image.
  """
  attr :id, :string, default: nil
  attr :class, :any, default: nil
  attr :reverse, :boolean, default: false

  slot :tags
  slot :title
  slot :description
  slot :solution_title
  slot :solution_subtitle
  slot :solutions
  slot :image

  def feature_section(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <section id={@id} class={["py-16 md:py-4", @class]}>
      <div class={@container_class}>
        <div class={[
          "flex flex-col gap-6 rounded-2xl bg-white p-6",
          @reverse && "lg:[&>*:first-child]:order-2"
        ]}>
          <%!-- Header with title and tags in horizontal layout --%>
          <div :if={@title != []} class="flex items-center justify-between gap-6">
            <h2 class="min-w-0 flex-auto text-[40px] font-bold text-black lg:line-clamp-2">
              {render_slot(@title)}
            </h2>
            <div :if={@tags != []} class="flex flex-wrap justify-end gap-2 lg:shrink-0">
              {render_slot(@tags)}
            </div>
          </div>

          <%!-- Main content grid --%>
          <div class="grid items-start gap-10 md:gap-6 lg:grid-cols-[1fr_2fr]">
            <%!-- Left column: description and solutions --%>
            <div class="flex min-w-[378px] flex-col gap-10">
              <%!-- Description text --%>
              <div :if={@description != []} class="space-y-4 text-base/relaxed text-black">
                {render_slot(@description)}
              </div>

              <%!-- Solution section --%>
              <div :if={@solution_title != [] || @solutions != []} class="flex flex-col gap-4">
                <div class="gap-1">
                  <h4 :if={@solution_title != []} class="text-xl font-medium text-black">
                    {render_slot(@solution_title)}
                  </h4>
                  <span :if={@solution_subtitle != []} class="text-grey-500 text-[14px]">
                    {render_slot(@solution_subtitle)}
                  </span>
                </div>
                <div :if={@solutions != []} class="flex flex-col gap-2">
                  {render_slot(@solutions)}
                </div>
              </div>
            </div>

            <%!-- Right column: image --%>
            <div
              :if={@image != []}
              class="flex size-full flex-1 items-center justify-center md:justify-end"
            >
              {render_slot(@image)}
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders a solution item with checkmark in a white background pill.
  When image_container_id and index are provided, adds hover interactivity to show corresponding images.
  """
  attr :class, :any, default: nil
  attr :image_container_id, :string, default: nil
  attr :index, :integer, default: nil

  slot :inner_block, required: true

  def solution_item(assigns) do
    ~H"""
    <div
      id={
        if @image_container_id != nil and @index != nil do
          @image_container_id <> "_item_" <> Integer.to_string(@index)
        end
      }
      class={[
        "group hover:bg-grey-100 flex cursor-pointer items-center space-x-[-2.33px] rounded-lg bg-white px-4 py-3",
        @class
      ]}
      phx-hook={
        if @image_container_id do
          "SolutionItemImageSwitcher"
        end
      }
      data-image-container={@image_container_id}
      data-solution-index={@index}
    >
      <.animated_arrow_static />
      <p class="text-grey-900 text-[16px] leading-normal font-normal transition-all duration-500 group-hover:translate-x-2.5 group-hover:text-orange-700">
        {render_slot(@inner_block)}
      </p>
    </div>
    """
  end

  @doc """
  Renders the highlight/quote banner section.
  PDF shows centered text with bold highlight and a CTA below.
  """
  attr :class, :any, default: nil

  slot :inner_block, required: true
  slot :cta

  def highlight_banner(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <section class={["py-16 md:pt-26 md:pb-2", @class]}>
      <div class={@container_class}>
        <div class="mx-auto space-y-6 text-center">
          <p class="text-base/relaxed font-extralight text-black md:text-[40px]">
            {render_slot(@inner_block)}
          </p>
          <div :if={@cta != []}>
            {render_slot(@cta)}
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the Czasośledź two-column section with time tracking and employee records.
  """
  attr :id, :string, default: nil
  attr :class, :any, default: nil
  slot :title, required: true
  slot :tags, required: false
  slot :description_one, required: true
  slot :description_two, required: true
  slot :left_title, required: true
  slot :left_description, required: true
  slot :left_content, required: true
  slot :right_title, required: true
  slot :right_description, required: true
  slot :right_content, required: true

  def timetracker_section(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <section id={@id} class={["mt-[72px] pt-16 md:pt-4", @class]}>
      <div class={@container_class}>
        <%!-- Header with title, description and tags --%>
        <div class="flex flex-col gap-6">
          <%!-- Title row with tags --%>
          <div class="flex items-start justify-between py-0 pr-0 pl-4">
            <h2 class="max-w-[563px] text-[32px] font-semibold text-black">
              {render_slot(@title)}
            </h2>
            <div :if={@tags != []} class="flex items-center gap-2">
              {render_slot(@tags)}
            </div>
          </div>

          <%!-- Description --%>
          <div class="flex max-w-[579px] flex-col gap-4 py-0 pr-0 pl-4 text-base/normal text-black">
            <p>
              {render_slot(@description_one)}
            </p>
            <p class="max-w-[378px]">
              {render_slot(@description_two)}
            </p>
          </div>

          <%!-- Two column cards --%>
          <div class="flex w-full items-stretch gap-5">
            <%!-- Left card: Monitorowanie czasu pracowników --%>
            <div class="group flex flex-1 flex-col items-center justify-center gap-6 rounded-2xl bg-white p-8 transition-all duration-500 hover:shadow-[0_4px_12px_0_rgba(0,0,0,0.15)]">
              <div class="flex w-full flex-col items-start gap-4">
                <div class="flex w-full items-center gap-3">
                  <div class="size-6 shrink-0 overflow-hidden">
                    <.animated_arrow />
                  </div>
                  <p class="text-2xl font-medium text-black">
                    {render_slot(@left_title)}
                  </p>
                </div>
                <div class="w-full">
                  <p class="text-grey-700 text-base/normal">
                    {render_slot(@left_description)}
                  </p>
                </div>
              </div>
              {render_slot(@left_content)}
            </div>

            <%!-- Right card: Ewidencja --%>
            <div class="group relative flex flex-1 flex-col items-center gap-14 rounded-2xl bg-white p-8 transition-all duration-500 hover:shadow-[0_4px_12px_0_rgba(0,0,0,0.15)]">
              <img
                src={~p"/images/clock.png"}
                alt="Decorative clock"
                class="pointer-events-none absolute bottom-full h-[224px] w-[224px] -translate-x-6 rotate-[12.591deg] opacity-20"
              />
              <div class="flex w-full flex-col items-start gap-4">
                <div class="flex w-full items-center gap-3">
                  <div class="size-6 shrink-0">
                    <.animated_arrow />
                  </div>
                  <p class="text-2xl font-medium text-black">
                    {render_slot(@right_title)}
                  </p>
                </div>
                <p class="text-grey-700 w-full text-base/normal">
                  {render_slot(@right_description)}
                </p>
              </div>
              {render_slot(@right_content)}
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders a mockup placeholder.
  """
  attr :label, :string, default: "Screenshot"
  attr :class, :any, default: nil
  attr :aspect, :string, default: "aspect-[4/3]"

  def mockup(assigns) do
    ~H"""
    <div class={[
      "bg-grey-50 border-grey-200 flex size-full flex-1 items-center justify-center rounded-lg border",
      @aspect,
      @class
    ]}>
      <span class="text-grey-400 text-xs">{@label}</span>
    </div>
    """
  end

  @doc """
  Renders a video placeholder.
  """
  attr :id, :string, default: nil
  attr :label, :string, default: "filmik z procesem"
  attr :class, :any, default: nil

  def video_placeholder(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <section id={@id} class={["py-8", @class]}>
      <div class={@container_class}>
        <div class="bg-grey-50 border-grey-200 flex aspect-video w-full items-center justify-center rounded-lg border">
          <span class="text-grey-400 text-sm italic">{@label}</span>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders a mock calc table.
  """
  attr :class, :any, default: nil

  def budget_analysis(assigns) do
    ~H"""
    <section class={["mx-auto w-full max-w-7xl px-16 lg:px-4", @class]}>
      <div class="flex items-start justify-between py-0 pr-0 pl-4">
        <h2 class="text-[32px] font-semibold text-black">
          Analiza budżetowa
        </h2>
        <%!-- Tags above spreadsheet visualization --%>
        <div class="mt-6 flex flex-wrap justify-center gap-2">
          <.tag label="budżet" />
          <.tag label="analiza" />
        </div>
      </div>
      <div class="mt-8 flex flex-col items-center px-0 pt-0 pb-8">
        <%!-- Spreadsheet visualization --%>
        <div class="w-full">
          <div class="grid grid-cols-[48px_repeat(10,1fr)] grid-rows-[26px_repeat(8,26px)] rounded-t-[16px]">
            <%!-- Top-left empty cell --%>
            <div class="outline-grey-300 flex rounded-tl-[16px] bg-[#f8f9fa] outline -outline-offset-1">
            </div>

            <%!-- Header row (A-I) --%>
            <%= for {letter, _index} <- Enum.with_index(~w(A B C D E F G H I)) do %>
              <div class="outline-grey-300 text-grey-700 flex items-center justify-center bg-[#f8f9fa] text-sm font-normal outline-[0.5px] outline-offset-[-0.5px]">
                {letter}
              </div>
            <% end %>
            <div class="outline-grey-300 text-grey-700 flex items-center justify-center rounded-tr-[16px] bg-[#f8f9fa] text-sm font-normal outline-[0.5px] outline-offset-[-0.5px]">
              J
            </div>

            <%!-- Row numbers column and grid cells --%>
            <%= for row_num <- 1..9 do %>
              <%!-- Row number cell --%>
              <div class={[
                "bg-grey-100 outline-grey-300 text-grey-700 flex items-center justify-center text-sm whitespace-nowrap outline-[0.5px] outline-offset-[-0.5px]",
                if row_num == 9 do
                  "border-grey-300 border-t-[0.5px] bg-transparent outline-0"
                end
              ]}>
                {if row_num < 9, do: row_num, else: nil}
              </div>

              <%!-- Grid cells for the current row --%>
              <%= for col_num <- 1..10 do %>
                <div class={[
                  "text-grey-700 flex items-center justify-center text-sm whitespace-nowrap",
                  if row_num <= Enum.at([8, 6, 4, 2, 4, 2, 2, 3, 1, 0], col_num - 1) do
                    "outline-grey-200 bg-white outline-[0.5px] outline-offset-[-0.5px]"
                  else
                    "bg-transparent"
                  end,
                  if row_num == Enum.at([9, 7, 5, 3, 5, 3, 3, 4, 2, 1], col_num - 1) do
                    "border-grey-200 border-t-[0.5px] bg-transparent"
                  end,
                  if row_num >= Enum.at([nil, 7, 5, 3, nil, 3, nil, nil, 2, 1], col_num - 1) and
                       row_num <= Enum.at([nil, 8, 6, 4, nil, 4, nil, nil, 3, 1], col_num - 1) do
                    "border-grey-200 border-l-[0.5px] bg-transparent"
                  end,
                  if row_num >= Enum.at([nil, nil, nil, 3, nil, nil, 3, nil, nil, nil], col_num - 1) and
                       row_num <= Enum.at([nil, nil, nil, 4, nil, nil, 3, nil, nil, nil], col_num - 1) do
                    "border-grey-200 border-r-[0.5px] bg-transparent"
                  end
                ]}>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <%!-- Text below --%>
        <p class="text-grey-700 mt-[-25px] text-center text-lg/normal font-normal">
          Budżet szybko się dezaktualizuje, odchylenia wychodzą <br />
          z opóźnieniem, dane są rozproszone, a <span class="font-bold text-[#217346]">excel</span>
          już Cię męczy?
        </p>
      </div>
    </section>
    """
  end

  @doc """
  Renders the dark CTA footer section.
  """
  attr :class, :any, default: nil

  def cta_footer(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <section
      id="cta-footer"
      class={["relative mt-[104px] overflow-clip bg-black py-20 text-white", @class]}
    >
      <div class="mx-auto max-w-7xl px-6 lg:px-10">
        <%!-- Main heading --%>
        <h2 class="mx-auto mb-[104px] max-w-[1090px] text-center text-[56px] leading-normal font-bold">
          <span class="font-extralight">To jak? Chcesz wypróbować </span>Firmowida?
        </h2>

        <%!-- Two column layout --%>
        <div class="mx-auto grid max-w-[1248px] shrink grid-rows-[auto_auto] items-center gap-1 md:grid-cols-[auto_auto] xl:gap-18">
          <%!-- Left: Benefits list --%>
          <div class="relative flex-1 space-y-2">
            <%!-- Subheading --%>
            <img
              src={~p"/images/booking_text.svg"}
              alt="Umów spotkanie, a otrzymasz:"
              class="mx-auto"
            />

            <div class="relative z-10 mx-auto flex flex-col items-center gap-2 px-2 pt-10 lg:max-w-[667px] lg:min-w-[530px]">
              <div class="inline-flex flex-row flex-wrap gap-3 gap-y-0 self-center lg:min-w-[566px]">
                <img
                  src={~p"/images/dot.svg"}
                  alt=""
                />
                <p class="text-[24px] leading-normal font-extralight text-balance">
                  dostęp do Firmowida<br class="hidden md:block lg:hidden" /> na
                  <span class="font-bold">3 miesiące</span>
                  <br class="md:hidden" />
                  <span class="ml-2 inline-flex shrink-0 items-center rounded-full bg-[rgba(226,139,88,0.3)] px-4 py-1 align-middle text-sm text-[#f0eae6]">
                    za darmo
                  </span>
                </p>
              </div>
              <div class="inline-flex flex-row flex-wrap gap-3 gap-y-0 self-center px-3">
                <img
                  src={~p"/images/dot.svg"}
                  alt=""
                />
                <p class="shrink text-[24px] leading-normal font-extralight text-nowrap">
                  dostosowanie Firmowida<br class="lg:hidden" /> do Twoich potrzeb
                </p>
              </div>
              <div class="inline-flex flex-row flex-wrap gap-3 gap-y-0 self-center px-4">
                <img
                  src={~p"/images/dot.svg"}
                  alt=""
                />
                <p class="text-[24px] leading-normal font-extralight">
                  pomoc z onboardingiem
                </p>
              </div>
              <img
                src={~p"/images/ellipse.svg"}
                alt="Decorative ellipse"
                class="height-[130%] width-full pointer-events-none absolute inset-0 z-[-1] hidden aspect-auto md:block"
                style="height: 130%; width: 100%; object-fit: fill;"
              />
            </div>
          </div>

          <%!-- Right: CTA button with decorative elements --%>
          <div class="mt-12 flex size-full items-center justify-center">
            <span class="shrink-0 pt-14 pr-6 pb-7 pl-40">
              <a
                href="https://cal.com/franek-madej/firmowid"
                target="_blank"
                rel="noopener noreferrer"
                class="group relative inline-flex items-center justify-center rounded px-8 py-4 text-[20px] font-medium text-white transition-colors duration-500"
              >
                <img
                  src={~p"/images/button.svg"}
                  alt=""
                  class="pointer-events-none absolute top-0 left-0 transition-opacity duration-500 group-hover:opacity-0"
                />
                <img
                  src={~p"/images/button_hover.svg"}
                  alt=""
                  class="pointer-events-none absolute top-0 left-0 opacity-0 transition-opacity duration-500 group-hover:opacity-100"
                /> Znajdź termin
                <img
                  src={~p"/images/arrow_pair.svg"}
                  alt="A pair of decorative arrows"
                  class="pointer-events-none absolute right-full -bottom-2 transition-all duration-500 md:-translate-x-[25.46px] md:group-hover:translate-x-[-17.46px] xl:-translate-x-[33.46px] xl:group-hover:translate-x-[-25.46px]"
                />
                <img
                  src={~p"/images/shine.svg"}
                  alt="A pair of decorative arrows"
                  class="pointer-events-none absolute right-[-21.616px] bottom-full translate-y-[-3px] transition-opacity duration-500 group-hover:opacity-0"
                />
                <img
                  src={~p"/images/shine_emphasis.svg"}
                  alt="A pair of decorative arrows"
                  class="pointer-events-none absolute right-[-25.616px] bottom-full translate-y-[-3px] opacity-0 transition-opacity duration-500 group-hover:opacity-100"
                />
              </a>
            </span>
          </div>
        </div>

        <img
          src={~p"/images/divider.svg"}
          alt="Decorative elements"
          class="pointer-events-none relative mt-[134px] h-auto w-full"
        />

        <%!-- Footer info --%>
        <div class="mt-10 mb-[29px] flex items-start justify-between">
          <div class="gap-1">
            <p class="mb-3 text-base font-bold">Firmowid</p>
            <p class="text-sm font-light">
              Aplikacja do fakturowania, która ułatwia życie przedsiębiorców.
            </p>
            <div class="flex-inline items-center gap-1 text-sm">
              <span class="font-light">Opracowana i wdrożona przez</span>
              <a
                href="https://alergeek.ventures/"
                target="_blank"
                rel="noopener noreferrer"
                class="font-logo hover:text-grey-300 font-bold text-white"
              >
                Alergeek Ventures
              </a>
            </div>
          </div>

          <%!-- Footer columns --%>
          <div class="flex gap-16 lg:gap-32">
            <div class="flex flex-col gap-3 text-base font-bold text-white">
              <a href="#ksef" class="hover:text-grey-300 hidden">O Firmowidzie</a>
              <a
                href="https://alergeek.ventures/"
                target="_blank"
                rel="noopener noreferrer"
                class="hover:text-grey-300"
              >
                O nas
              </a>
              <a
                href="https://cal.com/franek-madej/firmowid"
                target="_blank"
                rel="noopener noreferrer"
                class="hover:text-grey-300"
              >
                Kontakt
              </a>
            </div>
            <div class="flex flex-col gap-3 text-base font-bold text-white">
              <a href="/regulamin" class="hover:text-grey-300">
                Regulamin
              </a>
              <a href="/polityka-prywatnosci" class="hover:text-grey-300">
                Polityka Prywatności
              </a>
            </div>
          </div>
        </div>
        <%!-- Copyright --%>
        <p class="w-full text-xs font-light">
          © {Date.utc_today().year} Firmowid. Wszystkie prawa zastrzeżone.
        </p>
      </div>
    </section>
    """
  end

  @doc """
  Animated SVG arrow pointing right.
  """
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  def animated_arrow(assigns) do
    ~H"""
    <svg
      width="32"
      height="24"
      viewBox="0 0 35 24"
      fill="none"
      class={["transition-all duration-500", @class]}
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M5 12H19"
        class="transition-all duration-500 group-hover:translate-x-[-3.67px] group-hover:scale-x-[1.4] group-hover:stroke-[#8B3F13]"
        stroke="#B5B5B5"
        stroke-width="2"
        stroke-linecap="round"
      />
      <path
        d="M12 5L19 12L12 19"
        class="transition-all duration-500 group-hover:translate-x-[6.33px] group-hover:stroke-[#8B3F13]"
        stroke="#B5B5B5"
        stroke-width="2"
        stroke-linecap="round"
      />
    </svg>
    """
  end

  @doc """
  Animated SVG arrow pointing right. When animated, the start doesn't move
  """
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  def animated_arrow_static(assigns) do
    ~H"""
    <svg
      width="32"
      height="24"
      viewBox="0 0 35 24"
      fill="none"
      class="transition-all duration-500"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M5 12H19"
        class="transition-all duration-500 group-hover:scale-x-[1.4] group-hover:stroke-[#8B3F13]"
        stroke="#B5B5B5"
        stroke-width="2"
        stroke-linecap="round"
      />
      <path
        d="M12 5L19 12L12 19"
        class="transition-all duration-500 group-hover:translate-x-2.5 group-hover:stroke-[#8B3F13]"
        stroke="#B5B5B5"
        stroke-width="2"
        stroke-linecap="round"
      />
    </svg>
    """
  end
end
