defmodule FirmowidWeb.Components.Landing do
  @moduledoc """
  Landing page components for Firmowid marketing site.
  Designed to match the Figma export precisely.
  """
  use Phoenix.Component
  use FirmowidWeb, :verified_routes

  # Container max-width matching PDF margins (160px on desktop)
  @container_class "max-w-[1330px] w-full mx-auto px-6 lg:px-10"

  @doc """
  Renders the landing page navbar - minimal, clean design matching Figma.
  Layout: Logo | Nav Links (spread across)
  """
  attr :class, :string, default: nil

  def landing_navbar(assigns) do
    ~H"""
    <nav
      id="landing-navbar"
      class={[
        "fixed w-full top-0 z-50 pt-2 md:pt-6 px-6 lg:px-10 transition-colors duration-500",
        @class
      ]}
      phx-hook="NavbarScroll"
    >
      <div
        id="navbar-container"
        class="max-w-7xl mx-auto flex items-center justify-between backdrop-blur-[8px] rounded-lg bg-opacity-10 bg-black px-6 py-2 transition-all duration-500"
      >
        <%!-- Logo --%>
        <.link
          navigate={~p"/"}
          id="navbar-logo"
          class="font-extrabold text-[28px] text-black transition-colors duration-500"
        >
          Firmowid
        </.link>

        <%!-- Right nav links - hidden on mobile --%>
        <div class="hidden md:flex items-center gap-4 text-sm">
          <a
            href="#ksef"
            class="navbar-link px-5 py-[15px] font-medium text-black hover:text-grey-700 transition-colors duration-500 rounded-[5px]"
          >
            O Firmowidzie
          </a>
          <span class="navbar-link px-5 py-[15px] font-medium text-black hover:text-grey-700 transition-colors duration-500 rounded-[5px]">
            O nas
          </span>
          <span class="navbar-link px-5 py-[15px] font-medium text-black hover:text-grey-700 transition-colors duration-500 rounded-[5px]">
            Blog
          </span>
        </div>
      </div>
    </nav>
    """
  end

  @doc """
  Renders the Alergeek attribution and logo.
  """
  attr :class, :string, default: nil

  def alergeek_attribution(assigns) do
    ~H"""
    <div class="absolute w-full px-6 lg:px-10 flex flex-col top-[100px] items-center">
      <div class="max-w-7xl w-full pl-6">
        <%!-- Spacer to account for fixed navbar height --%>
        <span class="hidden md:flex items-baseline gap-1.5">
          <span class="text-black font-light">Opracowane i wdrożone przez</span>
          <span class="text-black font-bold font-logo">Alergeek Ventures</span>
        </span>
      </div>
    </div>
    """
  end

  @doc """
  Renders the hero section with large lowercase headline.
  PDF shows: Large bold headline, smaller description, CTAs, "Dowiedz się więcej" link
  """
  attr :class, :string, default: nil

  def hero_section(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <section class={["min-h-screen flex flex-col", @class]}>
      <div class="w-full flex-1 px-6 lg:px-10 flex flex-col">
        <div class="max-w-7xl mx-auto w-full flex-1 flex flex-col md:pl-6 gap-0">
          <%!-- Scrollable container for main hero content --%>
          <div class="flex-1 overflow-y-auto flex items-center justify-center">
            <div
              class="grid md:grid-cols-2 gap-8 md:gap-[22px] w-full"
              style="grid-auto-columns: 1fr;"
            >
              <%!-- Left column: copy and CTAs, vertically centered --%>
              <div class="flex flex-col pt-32 justify-center gap-[25px] min-w-[408px]">
                <div class="flex flex-col gap-[30px]">
                  <h1 class="text-[54px] font-bold text-black leading-normal tracking-tight uppercase">
                    prowadź firmę <br />z lżejszą głową
                  </h1>
                  <div class="space-y-4 text-[20px] font-medium text-black leading-normal">
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
                    class="relative text-nowrap px-8 py-4 rounded text-base font-medium text-grey-900 hover:bg-grey-200 transition-colors duration-500"
                  >
                    Zaloguj się
                    <img
                      src={~p"/images/button_login.svg"}
                      alt="Arrow right"
                      class="pointer-events-none absolute w-full h-full top-0 right-0"
                    />
                  </.link>
                  <.link
                    navigate={~p"/zarejestruj"}
                    class="text-nowrap px-8 py-4 rounded text-base font-medium text-white bg-black hover:bg-orange-700 disabled:cursor-default disabled:bg-grey-800 disabled:text-grey-400 transition-colors duration-500"
                  >
                    Wypróbuj Firmowida
                  </.link>
                </div>
              </div>

              <%!-- Right column: image only --%>
              <div class="flex items-center justify-center flex-1 overflow-hidden">
                <img
                  src={~p"/images/figurine.png"}
                  alt="Firmowid"
                  class="w-full h-auto max-w-[590px] object-cover object-bottom"
                />
              </div>
            </div>
          </div>

          <%!-- Sticky button at bottom of scroll context --%>
          <div class="sticky bottom-0 flex items-center justify-center bg-grey-100">
            <a
              href="#ksef"
              class="inline-flex flex-col items-center px-8 pt-4 mb-2 text-base font-medium text-darkGrey hover:text-black transition-colors duration-500"
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
      "inline-flex px-4 py-1 text-[14px] rounded-2xl",
      if(@variant == :accent,
        do: "bg-[#8BC9C94D] text-turquoise-700",
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
  attr :class, :string, default: nil
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
          "flex flex-col gap-6 bg-white p-6 rounded-2xl",
          @reverse && "lg:[&>*:first-child]:order-2"
        ]}>
          <%!-- Header with title and tags in horizontal layout --%>
          <div :if={@title != []} class="flex items-center justify-between gap-6">
            <h2 class="flex-auto lg:line-clamp-2 min-w-0 text-[40px] font-bold text-black">
              {render_slot(@title)}
            </h2>
            <div :if={@tags != []} class="flex flex-wrap gap-2 lg:shrink-0 justify-end">
              {render_slot(@tags)}
            </div>
          </div>

          <%!-- Main content grid --%>
          <div class="grid lg:grid-cols-[1fr,2fr] gap-10 md:gap-6 items-start">
            <%!-- Left column: description and solutions --%>
            <div class="flex flex-col gap-10 min-w-[378px]">
              <%!-- Description text --%>
              <div :if={@description != []} class="space-y-4 text-base text-black leading-relaxed">
                {render_slot(@description)}
              </div>

              <%!-- Solution section --%>
              <div :if={@solution_title != [] || @solutions != []} class="flex flex-col gap-4">
                <div class="gap-1">
                  <h4 :if={@solution_title != []} class="text-xl font-medium text-black">
                    {render_slot(@solution_title)}
                  </h4>
                  <span :if={@solution_subtitle != []} class="text-[14px] text-grey-500">
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
              class="flex flex-1 items-center justify-center md:justify-end w-full h-full"
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
      class="flex items-center space-x-[-2.33px] bg-white rounded-lg py-3 px-4 hover:bg-grey-100 group cursor-pointer"
      phx-hook={
        if @image_container_id do
          "SolutionItemImageSwitcher"
        end
      }
      data-image-container={@image_container_id}
      data-solution-index={@index}
    >
      <.animated_arrow_static />
      <p class="text-[16px] leading-normal text-grey-900 font-normal group-hover:text-orange-700 group-hover:translate-x-2.5 transition-all duration-500">
        {render_slot(@inner_block)}
      </p>
    </div>
    """
  end

  @doc """
  Renders the highlight/quote banner section.
  PDF shows centered text with bold highlight and a CTA below.
  """
  attr :class, :string, default: nil

  slot :inner_block, required: true
  slot :cta

  def highlight_banner(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <section class={["py-16 md:pb-2 md:pt-26", @class]}>
      <div class={@container_class}>
        <div class="text-center mx-auto space-y-6">
          <p class="text-base md:text-[40px] text-black font-extralight leading-relaxed">
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
  attr :class, :string, default: nil
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
    <section id={@id} class={["py-16 md:py-4", @class]}>
      <div class={@container_class}>
        <%!-- Header with title, description and tags --%>
        <div class="flex flex-col gap-6">
          <%!-- Title row with tags --%>
          <div class="flex items-start justify-between pl-4 pr-0 py-0">
            <h2 class="text-[32px] font-semibold text-black max-w-[563px]">
              {render_slot(@title)}
            </h2>
            <div :if={@tags != []} class="flex gap-2 items-center">
              {render_slot(@tags)}
            </div>
          </div>

          <%!-- Description --%>
          <div class="flex flex-col gap-4 pl-4 pr-0 py-0 max-w-[579px] text-base text-black leading-[1.5]">
            <p>
              {render_slot(@description_one)}
            </p>
            <p class="max-w-[378px]">
              {render_slot(@description_two)}
            </p>
          </div>

          <%!-- Two column cards --%>
          <div class="flex gap-5 items-stretch w-full">
            <%!-- Left card: Monitorowanie czasu pracowników --%>
            <div class="bg-white flex flex-col flex-1 gap-6 items-center justify-center p-8 rounded-2xl group hover:shadow-[0_4px_12px_0_rgba(0,0,0,0.15)]">
              <div class="flex flex-col gap-4 items-start w-full">
                <div class="flex gap-3 items-center w-full">
                  <div class="w-6 h-6 shrink-0 overflow-hidden">
                    <.animated_arrow />
                  </div>
                  <p class="text-2xl font-medium text-black">
                    {render_slot(@left_title)}
                  </p>
                </div>
                <div class="w-full">
                  <p class="text-base text-grey-700 leading-[1.5]">
                    {render_slot(@left_description)}
                  </p>
                </div>
              </div>
              {render_slot(@left_content)}
            </div>

            <%!-- Right card: Ewidencja --%>
            <div class="relative bg-white flex flex-col flex-1 gap-14 items-center p-8 rounded-2xl group hover:shadow-[0_4px_12px_0_rgba(0,0,0,0.15)]">
              <img
                src={~p"/images/clock.png"}
                alt="Decorative clock"
                class="pointer-events-none absolute bottom-full rotate-[12.591deg] h-[224px] w-[224px] opacity-20 -translate-x-6"
              />
              <div class="flex flex-col gap-4 items-start w-full">
                <div class="flex gap-3 items-center w-full">
                  <div class="w-6 h-6 shrink-0">
                    <.animated_arrow />
                  </div>
                  <p class="text-2xl font-medium text-black">
                    {render_slot(@right_title)}
                  </p>
                </div>
                <p class="text-base text-grey-700 leading-[1.5] w-full">
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
  attr :class, :string, default: nil
  attr :aspect, :string, default: "aspect-[4/3]"

  def mockup(assigns) do
    ~H"""
    <div class={[
      "w-full h-full flex-1 rounded-lg border border-grey-200 bg-grey-50",
      "flex items-center justify-center",
      @aspect,
      @class
    ]}>
      <span class="text-xs text-grey-400">{@label}</span>
    </div>
    """
  end

  @doc """
  Renders a video placeholder.
  """
  attr :id, :string, default: nil
  attr :label, :string, default: "filmik z procesem"
  attr :class, :string, default: nil

  def video_placeholder(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <section id={@id} class={["py-8", @class]}>
      <div class={@container_class}>
        <div class="w-full aspect-video rounded-lg border border-grey-200 bg-grey-50 flex items-center justify-center">
          <span class="text-sm text-grey-400 italic">{@label}</span>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders a mock calc table.
  """
  attr :class, :string, default: nil

  def budget_analysis(assigns) do
    ~H"""
    <section class="w-full mx-auto px-16 lg:px-4  max-w-7xl">
      <div class="flex items-start justify-between pl-4 pr-0 py-0">
        <h2 class="text-[32px] font-semibold text-black">
          Analiza budżetowa
        </h2>
        <%!-- Tags above spreadsheet visualization --%>
        <div class="flex flex-wrap gap-2 mt-6 justify-center">
          <.tag label="budżet" />
          <.tag label="analiza" />
        </div>
      </div>
      <div class="flex flex-col items-center pb-8 pt-0 px-0 mt-8">
        <%!-- Spreadsheet visualization --%>
        <div class="w-full">
          <div class="grid grid-cols-[48px_repeat(10,1fr)] grid-rows-[26px_repeat(8,26px)] rounded-t-[16px]">
            <%!-- Top-left empty cell --%>
            <div class="flex bg-[#f8f9fa] outline outline-[1px] outline-grey-300 outline-offset-[-1px] rounded-tl-[16px]">
            </div>

            <%!-- Header row (A-I) --%>
            <%= for {letter, _index} <- Enum.with_index(~w(A B C D E F G H I)) do %>
              <div class="flex items-center justify-center text-sm text-grey-700 font-normal bg-[#f8f9fa] outline outline-[0.5px] outline-grey-300 outline-offset-[-0.5px]">
                {letter}
              </div>
            <% end %>
            <div class="flex items-center justify-center text-sm text-grey-700 font-normal bg-[#f8f9fa] outline outline-[0.5px] outline-grey-300 outline-offset-[-0.5px] rounded-tr-[16px]">
              J
            </div>

            <%!-- Row numbers column and grid cells --%>
            <%= for row_num <- 1..9 do %>
              <%!-- Row number cell --%>
              <div class={[
                "flex items-center justify-center text-sm text-grey-700 whitespace-nowrap bg-grey-100 outline outline-[0.5px] outline-grey-300 outline-offset-[-0.5px]",
                if row_num == 9 do
                  "outline-0 bg-transparent border-t-[0.5px] border-grey-300"
                end
              ]}>
                {if row_num < 9, do: row_num, else: nil}
              </div>

              <%!-- Grid cells for the current row --%>
              <%= for col_num <- 1..10 do %>
                <div class={[
                  "flex items-center justify-center text-sm text-grey-700 whitespace-nowrap",
                  if row_num <= Enum.at([8, 6, 4, 2, 4, 2, 2, 3, 1, 0], col_num - 1) do
                    "bg-white outline outline-[0.5px] outline-grey-200 outline-offset-[-0.5px]"
                  else
                    "bg-transparent"
                  end,
                  if row_num == Enum.at([9, 7, 5, 3, 5, 3, 3, 4, 2, 1], col_num - 1) do
                    "bg-transparent border-t-[0.5px] border-grey-200"
                  end,
                  if row_num >= Enum.at([nil, 7, 5, 3, nil, 3, nil, nil, 2, 1], col_num - 1) and
                       row_num <= Enum.at([nil, 8, 6, 4, nil, 4, nil, nil, 3, 1], col_num - 1) do
                    "bg-transparent border-l-[0.5px] border-grey-200"
                  end,
                  if row_num >= Enum.at([nil, nil, nil, 3, nil, nil, 3, nil, nil, nil], col_num - 1) and
                       row_num <= Enum.at([nil, nil, nil, 4, nil, nil, 3, nil, nil, nil], col_num - 1) do
                    "bg-transparent border-r-[0.5px] border-grey-200"
                  end
                ]}>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <%!-- Text below --%>
        <p class="font-normal leading-[1.5] text-lg text-grey-700 text-center mt-[-25px]">
          Budżet szybko się dezaktualizuje, odchylenia wychodzą <br />
          z opóźnieniem, dane są rozproszone, a <span class="text-[#217346] font-bold">excel</span>
          już Cię męczy?
        </p>
      </div>
    </section>
    """
  end

  @doc """
  Renders the dark CTA footer section.
  """
  attr :class, :string, default: nil

  def cta_footer(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <section id="cta-footer" class={["bg-black text-white py-20 relative overflow-clip", @class]}>
      <div class="max-w-7xl mx-auto px-6 lg:px-10">
        <%!-- Main heading --%>
        <h2 class="text-center text-[56px] font-bold leading-[1.5] max-w-[1090px] mx-auto mb-[104px]">
          <span class="font-extralight">To jak? Chcesz wypróbować </span>Firmowida?
        </h2>

        <%!-- Two column layout --%>
        <div class="grid grid-rows-[auto,auto] md:grid-cols-[auto,auto] shrink items-center gap-1 xl:gap-18 max-w-[1248px] mx-auto">
          <%!-- Left: Benefits list --%>
          <div class="flex-1 space-y-2 relative">
            <%!-- Subheading --%>
            <img
              src={~p"/images/booking_text.svg"}
              alt="Umów spotkanie, a otrzymasz:"
              class="mx-auto"
            />

            <div class="flex flex-col relative z-10 lg:max-w-[667px] lg:min-w-[530px] mx-auto pt-10 px-2 items-center gap-2">
              <div class="inline-flex flex-row self-center gap-3 flex-wrap gap-y-0 lg:min-w-[566px]">
                <img
                  src={~p"/images/dot.svg"}
                  alt=""
                />
                <p class="text-[24px] font-extralight leading-normal text-balance">
                  dostęp do Firmowida<br class="hidden md:block lg:hidden" /> na
                  <span class="font-bold">3 miesiące</span>
                  <br class="md:hidden" />
                  <span class="inline-flex items-center align-middle bg-[rgba(226,139,88,0.3)] text-[#f0eae6] px-4 py-1 rounded-full text-sm ml-2 shrink-0">
                    za darmo
                  </span>
                </p>
              </div>
              <div class="inline-flex flex-row self-center gap-3 flex-wrap gap-y-0 px-3">
                <img
                  src={~p"/images/dot.svg"}
                  alt=""
                />
                <p class="text-[24px] font-extralight leading-normal text-nowrap shrink">
                  dostosowanie Firmowida<br class="lg:hidden" /> do Twoich potrzeb
                </p>
              </div>
              <div class="inline-flex flex-row self-center gap-3 flex-wrap gap-y-0 px-4">
                <img
                  src={~p"/images/dot.svg"}
                  alt=""
                />
                <p class="text-[24px] font-extralight leading-normal">
                  pomoc z onboardingiem
                </p>
              </div>
              <img
                src={~p"/images/ellipse.svg"}
                alt="Decorative ellipse"
                class="pointer-events-none hidden md:block absolute top-0 right-0 left-0 bottom-0 width-full height-[130%] aspect-auto z-[-1]"
                style="height: 130%; width: 100%; object-fit: fill;"
              />
            </div>
          </div>

          <%!-- Right: CTA button with decorative elements --%>
          <div class="flex w-full h-full justify-center items-center mt-12">
            <span class="pl-40 pr-6 pt-14 pb-7 shrink-0">
              <button class="relative text-white px-8 py-4 rounded text-[20px] font-medium transition-colors duration-500 group">
                <img
                  src={~p"/images/button.svg"}
                  alt=""
                  class="pointer-events-none absolute left-0 top-0 group-hover:opacity-0 transition-opacity duration-500"
                />
                <img
                  src={~p"/images/button_hover.svg"}
                  alt=""
                  class="pointer-events-none absolute left-0 top-0 opacity-0 group-hover:opacity-100 transition-opacity duration-500"
                /> Znajdź termin
                <img
                  src={~p"/images/arrow_pair.svg"}
                  alt="A pair of decorative arrows"
                  class="pointer-events-none absolute right-full md:-translate-x-[25.46px] xl:-translate-x-[33.46px] -bottom-2 xl:group-hover:translate-x-[-25.46px] md:group-hover:translate-x-[-17.46px] transition-all duration-500"
                />
                <img
                  src={~p"/images/shine.svg"}
                  alt="A pair of decorative arrows"
                  class="pointer-events-none absolute right-[-21.616px] bottom-full translate-y-[-3px] group-hover:opacity-0 transition-opacity duration-500"
                />
                <img
                  src={~p"/images/shine_emphasis.svg"}
                  alt="A pair of decorative arrows"
                  class="pointer-events-none absolute right-[-25.616px] bottom-full translate-y-[-3px] opacity-0 group-hover:opacity-100 transition-opacity duration-500"
                />
              </button>
            </span>
          </div>
        </div>

        <img
          src={~p"/images/divider.svg"}
          alt="Decorative elements"
          class="pointer-events-none relative w-full mt-[134px] h-auto"
        />

        <%!-- Footer info --%>
        <div class="flex items-start justify-between mb-[29px] mt-10">
          <div class="gap-1">
            <p class="font-bold text-base mb-3">Firmowid</p>
            <p class="font-light text-sm">
              Aplikacja do fakturowania, która ułatwia życie przedsiębiorców.
            </p>
            <div class="flex-inline items-center gap-1 text-sm">
              <span class="font-light">Opracowana i wdrożona przez</span>
              <span class="font-logo font-bold">Alergeek Ventures</span>
            </div>
          </div>

          <%!-- Footer columns --%>
          <div class="flex gap-32">
            <%!-- <div class="space-y-3 font-bold text-base">
              <p>O Firmowidzie</p>
              <p>O nas</p>
              <p>Kontakt</p>
              <p>Blog</p>
            </div> --%>
            <div class="space-y-3 font-bold text-base">
              <p>O Firmowidzie</p>
              <p>O nas</p>
              <p>Kontakt</p>
            </div>
          </div>
        </div>
        <%!-- Copyright --%>
        <p class="text-xs font-light w-full">© 2025 Firmowid. Wszystkie prawa zastrzeżone.</p>
      </div>
    </section>
    """
  end

  @doc """
  Animated SVG arrow pointing right.
  """
  attr :id, :string, default: nil
  attr :class, :string, default: nil

  def animated_arrow(assigns) do
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
        class="transition-all duration-500 group-hover:stroke-[#8B3F13] group-hover:translate-x-[-3.67px] group-hover:scale-x-[1.4]"
        stroke="#B5B5B5"
        stroke-width="2"
        stroke-linecap="round"
      />
      <path
        d="M12 5L19 12L12 19"
        class="transition-all duration-500 group-hover:stroke-[#8B3F13] group-hover:translate-x-[6.33px]"
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
  attr :class, :string, default: nil

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
        class="transition-all duration-500 group-hover:stroke-[#8B3F13] group-hover:scale-x-[1.4]"
        stroke="#B5B5B5"
        stroke-width="2"
        stroke-linecap="round"
      />
      <path
        d="M12 5L19 12L12 19"
        class="transition-all duration-500 group-hover:stroke-[#8B3F13] group-hover:translate-x-[10px]"
        stroke="#B5B5B5"
        stroke-width="2"
        stroke-linecap="round"
      />
    </svg>
    """
  end
end
