defmodule FirmowidWeb.Components.Landing do
  @moduledoc """
  Landing page components for Firmowid marketing site.
  Designed to match the Figma export precisely.
  """
  use Phoenix.Component
  use FirmowidWeb, :verified_routes

  import FirmowidWeb.CoreComponents, only: [icon: 1]

  # Container max-width matching PDF margins (160px on desktop)
  @container_class "max-w-5xl mx-auto px-6 lg:px-10"

  @doc """
  Renders the landing page navbar - minimal, clean design matching PDF.
  Layout: Logo | Nav Links | CTAs (spread across)
  """
  attr :class, :string, default: nil

  def landing_navbar(assigns) do
    ~H"""
    <nav class={["w-full py-4 px-6 lg:px-10", @class]}>
      <div class="max-w-5xl mx-auto flex items-center justify-between">
        <%!-- Logo --%>
        <.link navigate={~p"/"} class="font-medium text-base text-black">
          Firmowid
        </.link>

        <%!-- Center nav links - hidden on mobile --%>
        <div class="hidden md:flex items-center gap-8 text-sm">
          <a href="#ksef" class="text-darkGrey hover:text-black transition-colors">
            O Firmowidzie
          </a>
          <span class="text-grey-400 cursor-default">O nas</span>
          <span class="text-grey-400 cursor-default">Blog</span>
        </div>

        <%!-- CTAs --%>
        <div class="flex items-center gap-2">
          <.link
            navigate={~p"/zaloguj"}
            class="hidden sm:inline-flex px-4 py-2 text-sm text-white bg-black rounded hover:bg-grey-700 transition-colors"
          >
            Zaloguj się
          </.link>
          <.link
            navigate={~p"/zarejestruj"}
            class="px-4 py-2 text-sm text-orangeText bg-orangeBg rounded hover:opacity-90 transition-opacity"
          >
            Wypróbuj Firmowida
          </.link>
        </div>
      </div>
    </nav>
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
    <section class={["pt-12 pb-8 lg:pt-20 lg:pb-12", @class]}>
      <div class={@container_class}>
        <div class="grid lg:grid-cols-[1fr,auto] gap-8 lg:gap-16 items-start">
          <div class="space-y-5 max-w-md">
            <h1 class="text-3xl font-bold text-black leading-[1.15] tracking-tight uppercase">
              prowadź firmę <br />z lżejszą głową
            </h1>
            <p class="text-sm text-darkGrey leading-relaxed">
              Firmowid automatyzuje fakturowanie, integruje się z KSeF,
              pilnuje budżetów i czasu pracy Twoich pracowników.<br />
              A Ty? Ty skupiasz się na swoim biznesie.
            </p>
            <div class="flex items-center gap-3">
              <.link
                navigate={~p"/zaloguj"}
                class="px-5 py-2.5 text-sm font-medium text-white bg-black rounded hover:bg-grey-700 transition-colors"
              >
                Zaloguj się
              </.link>
              <.link
                navigate={~p"/zarejestruj"}
                class="px-5 py-2.5 text-sm font-medium text-orangeText bg-orangeBg rounded hover:opacity-90 transition-opacity"
              >
                Wypróbuj Firmowida
              </.link>
            </div>
            <div class="pt-4">
              <a
                href="#ksef"
                class="inline-flex items-center gap-1.5 text-xs text-darkGrey hover:text-black transition-colors"
              >
                <.icon name="hero-arrow-down-mini" class="w-3 h-3" /> Dowiedz się więcej
              </a>
            </div>
          </div>
          <div class="flex justify-center lg:justify-end lg:pt-4">
            <img
              src={~p"/images/figurine.png"}
              alt="Firmowid"
              class="w-44 lg:w-56 h-auto"
            />
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
      "inline-flex px-2 py-0.5 text-xs rounded",
      if(@variant == :accent,
        do: "bg-orangeBg text-orangeText",
        else: "border border-grey-300 text-darkGrey"
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
  slot :title, required: true
  slot :description, required: true
  slot :solution_title
  slot :solutions
  slot :image

  def feature_section(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <section id={@id} class={["py-16 lg:py-20", @class]}>
      <div class={@container_class}>
        <div class={[
          "grid lg:grid-cols-2 gap-10 lg:gap-16 items-start",
          @reverse && "lg:[&>*:first-child]:order-2"
        ]}>
          <div class="space-y-5">
            <div :if={@tags != []} class="flex flex-wrap gap-2">
              {render_slot(@tags)}
            </div>

            <h2 class="text-2xl font-bold text-black">
              {render_slot(@title)}
            </h2>

            <p class="text-sm text-darkGrey leading-relaxed">
              {render_slot(@description)}
            </p>

            <div :if={@solution_title != [] || @solutions != []} class="pt-4 space-y-3">
              <h4 :if={@solution_title != []} class="text-sm font-semibold text-black">
                {render_slot(@solution_title)}
              </h4>
              <div :if={@solutions != []} class="space-y-2">
                {render_slot(@solutions)}
              </div>
            </div>
          </div>

          <div :if={@image != []} class="flex justify-center lg:justify-end">
            {render_slot(@image)}
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders a solution item with checkmark.
  """
  slot :inner_block, required: true

  def solution_item(assigns) do
    ~H"""
    <div class="flex items-start gap-2.5">
      <.icon name="hero-check-mini" class="w-4 h-4 text-darkGrey flex-shrink-0 mt-0.5" />
      <span class="text-sm text-darkGrey">{render_slot(@inner_block)}</span>
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
    <section class={["py-16 lg:py-20 border-y border-grey-200", @class]}>
      <div class={@container_class}>
        <div class="text-center max-w-2xl mx-auto space-y-6">
          <p class="text-base lg:text-lg text-black leading-relaxed">
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
  Renders the Czasośledź two-column section.
  """
  attr :id, :string, default: nil
  attr :class, :string, default: nil

  slot :tags
  slot :title, required: true
  slot :description
  slot :left_title
  slot :left_description
  slot :left_content
  slot :right_title
  slot :right_description
  slot :right_content

  def timetracker_section(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <section id={@id} class={["py-16 lg:py-20", @class]}>
      <div class={@container_class}>
        <div class="space-y-10">
          <%!-- Header --%>
          <div class="space-y-4 max-w-2xl">
            <div :if={@tags != []} class="flex flex-wrap gap-2">
              {render_slot(@tags)}
            </div>
            <h2 class="text-2xl font-bold text-black">
              {render_slot(@title)}
            </h2>
            <p :if={@description != []} class="text-sm text-darkGrey leading-relaxed">
              {render_slot(@description)}
            </p>
          </div>

          <%!-- Two columns --%>
          <div class="grid lg:grid-cols-2 gap-10 lg:gap-16">
            <div class="space-y-4">
              <h3 :if={@left_title != []} class="text-base font-semibold text-black">
                {render_slot(@left_title)}
              </h3>
              <p :if={@left_description != []} class="text-sm text-darkGrey leading-relaxed">
                {render_slot(@left_description)}
              </p>
              <div :if={@left_content != []} class="pt-2">
                {render_slot(@left_content)}
              </div>
            </div>

            <div class="space-y-4">
              <h3 :if={@right_title != []} class="text-base font-semibold text-black">
                {render_slot(@right_title)}
              </h3>
              <p :if={@right_description != []} class="text-sm text-darkGrey leading-relaxed">
                {render_slot(@right_description)}
              </p>
              <div :if={@right_content != []} class="pt-2">
                {render_slot(@right_content)}
              </div>
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
      "w-full rounded-lg border border-grey-200 bg-grey-50",
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
  attr :label, :string, default: "filmik z procesem"
  attr :class, :string, default: nil

  def video_placeholder(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <div class={["py-8", @class]}>
      <div class={@container_class}>
        <div class="w-full aspect-video rounded-lg border border-grey-200 bg-grey-50 flex items-center justify-center">
          <span class="text-sm text-grey-400 italic">{@label}</span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the footer.
  """
  attr :class, :string, default: nil

  def landing_footer(assigns) do
    assigns = assign(assigns, :container_class, @container_class)

    ~H"""
    <footer class={["py-8 border-t border-grey-200", @class]}>
      <div class={@container_class}>
        <div class="flex flex-col sm:flex-row items-center justify-between gap-4">
          <.link navigate={~p"/"} class="font-semibold text-base text-black">
            Firmowid
          </.link>

          <div class="flex items-center gap-6 text-sm">
            <a href="#ksef" class="text-darkGrey hover:text-black transition-colors">
              O Firmowidzie
            </a>
            <span class="text-grey-400 cursor-default">O nas</span>
            <span class="text-grey-400 cursor-default">Blog</span>
          </div>
        </div>
      </div>
    </footer>
    """
  end
end
