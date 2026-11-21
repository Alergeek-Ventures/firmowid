defmodule FirmowidWeb.Landing.Components.FeaturePage do
  @moduledoc """
  Landing layout of a feature page (`/funkcje/:slug`), in the style of the home
  page and the case studies: a hero with the screenshot (or transfers paired with invoices, a running timer, or the split of each 100 zł of revenue) on a sheet of paper, the
  facts strip, the introduction quoted in a dark block, sections with tables and
  captioned screenshots, logo rows, collapsible questions and the closing call to action.

  The page content comes from `FirmowidWeb.Landing.Utilities.Guides`; the fixed
  texts are in `priv/guides/funkcje/index.yml`, because feature pages are Polish only.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.Landing.Components.Primitives, only: [cta_footer: 1, landing_navbar: 1]

  alias FirmowidWeb.Landing.Utilities.Guides

  @doc "Renders a feature page."
  @spec feature_page(map()) :: Phoenix.LiveView.Rendered.t()
  attr :article, :map, required: true

  # sobelow_skip ["XSS.Raw"]
  # Feature page HTML is compiled from Markdown committed in priv/guides with raw HTML disabled.
  def feature_page(assigns) do
    texts = Guides.feature_page()

    author =
      case assigns.article.landing.author do
        :stanislaw ->
          %{
            name: texts.quote_name,
            role: texts.quote_role,
            image: "/images/team-stanislaw-madej.webp"
          }

        :franek ->
          %{
            name: texts.quote_franek_name,
            role: texts.quote_franek_role,
            image: "/images/team-franek-madej.webp"
          }
      end

    assigns =
      assign(assigns,
        texts: texts,
        layout: assigns.article.layout,
        landing: assigns.article.landing,
        author: author
      )

    ~H"""
    <div
      id="top"
      data-landing-page="true"
      class="flex min-h-screen flex-col bg-grey-100 font-landing text-[#0f0f0f] [--landing-accent:#8b3f13] [--landing-beige:#f0eae6] [--landing-line:#e6d7ce] [--landing-nav-height:--spacing(16)] motion-reduce:**:animate-none! motion-reduce:**:transition-none! lg:[--landing-nav-height:--spacing(24)] [&_a:focus-visible]:outline-2 [&_a:focus-visible]:outline-offset-4 [&_a:focus-visible]:outline-rust-600 [&_summary:focus-visible]:outline-2 [&_summary:focus-visible]:outline-rust-600 **:[[id]]:scroll-mt-[calc(var(--landing-nav-height)+var(--spacing)*6)]"
    >
      <.landing_navbar />

      <main>
        <section class="pt-28 pb-14 lg:pt-36 lg:pb-24">
          <div class="mx-auto grid w-[min(1140px,calc(100%-32px))] items-center gap-12 lg:grid-cols-[minmax(0,1.05fr)_minmax(0,0.95fr)] lg:gap-16">
            <div>
              <a href="/funkcje" class="text-sm font-medium text-grey-700 hover:text-rust-700">
                {@texts.back_label}
              </a>
              <p
                :if={@landing.kicker}
                class="mt-7 text-[13px] font-semibold tracking-[.08em] text-rust-700 uppercase"
              >
                {@landing.kicker}
              </p>
              <h1 class="mt-3 text-[clamp(36px,4.6vw,58px)] leading-[1.05] font-bold tracking-[-0.035em] text-balance">
                {@article.title}
              </h1>
              <p class="mt-6 max-w-[46ch] text-[clamp(17px,1.5vw,19px)] leading-normal text-pretty text-grey-700">
                {@article.description}
              </p>
              <div class="mt-8 flex flex-wrap gap-3">
                <a
                  href="/zarejestruj"
                  class="inline-flex min-h-14 items-center rounded-[4px] bg-[#0f0f0f] px-7 font-medium text-white transition hover:-translate-y-0.5 hover:bg-rust-700"
                >
                  {@texts.cta_primary}
                </a>
                <a
                  href="https://cal.com/franek-madej/firmowid"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex min-h-14 items-center rounded-[4px] border border-[#0f0f0f]/25 px-7 font-medium transition hover:-translate-y-0.5 hover:border-rust-700 hover:text-rust-700"
                >
                  {@texts.cta_secondary}
                </a>
              </div>
              <p class="mt-4 text-[13px] text-grey-600">{@texts.cta_note}</p>
            </div>

            <figure
              :if={@layout.hero || @landing.match != [] || @landing.timer || @landing.split}
              class="relative m-0 mb-10 lg:mb-0"
            >
              <div
                :if={@landing.match != []}
                class="rotate-[1.2deg] rounded-[4px] bg-white p-4 font-sans shadow-[0_1px_0_var(--color-grey-200),0_30px_60px_-30px_rgba(87,54,35,.45)] sm:p-6"
              >
                <div class="grid grid-cols-[minmax(0,1fr)_36px_minmax(0,1fr)] pb-1 text-caps-sm font-semibold tracking-[.08em] text-grey-600 uppercase sm:grid-cols-[minmax(0,1fr)_56px_minmax(0,1fr)]">
                  <span>{@texts.match_transfer}</span>
                  <span></span>
                  <span>{@texts.match_invoice}</span>
                </div>
                <div
                  :for={row <- @landing.match}
                  class="mt-2.5 grid grid-cols-[minmax(0,1fr)_36px_minmax(0,1fr)] items-center sm:grid-cols-[minmax(0,1fr)_56px_minmax(0,1fr)]"
                >
                  <div class="rounded-[4px] border border-grey-200 bg-grey-50 px-3 py-2.5 sm:px-4 sm:py-3">
                    <p class="truncate text-sm font-semibold sm:text-[15px]">{row.payer}</p>
                    <p class="mt-0.5 truncate text-[12.5px] text-grey-600">
                      {row.date} · <span class="font-medium text-[#0f0f0f]">{row.amount}</span>
                    </p>
                  </div>
                  <div class={[
                    "relative h-0 border-t-2",
                    if(row.suggested?,
                      do: "border-dashed border-rust-400",
                      else: "border-teal-700"
                    )
                  ]}>
                    <span class={[
                      "absolute top-1/2 left-1/2 grid size-5 -translate-1/2 place-items-center rounded-full text-caps-sm/none font-bold sm:size-6",
                      if(row.suggested?,
                        do: "bg-rust-200 text-rust-800",
                        else: "bg-teal-700 text-white"
                      )
                    ]}>
                      {if row.suggested?, do: "?", else: "✓"}
                    </span>
                  </div>
                  <div class={[
                    "rounded-[4px] border px-3 py-2.5 sm:px-4 sm:py-3",
                    if(row.suggested?,
                      do: "border-rust-200 bg-(--landing-beige)",
                      else: "border-teal-200 bg-teal-100"
                    )
                  ]}>
                    <p class="truncate text-sm font-semibold sm:text-[15px]">{row.invoice}</p>
                    <p class={[
                      "mt-0.5 truncate text-[12.5px] font-medium",
                      if(row.suggested?, do: "text-rust-800", else: "text-teal-800")
                    ]}>
                      {row.status}
                    </p>
                  </div>
                </div>
              </div>
              <div
                :if={@landing.timer}
                class="rotate-[1.2deg] rounded-[4px] bg-white p-5 font-sans shadow-[0_1px_0_var(--color-grey-200),0_30px_60px_-30px_rgba(87,54,35,.45)] sm:p-7"
              >
                <p class="truncate rounded-[4px] border border-grey-300 bg-white px-3.5 py-2.5 text-[15px] font-medium">
                  {@landing.timer.title}
                </p>
                <p class="mt-2.5 flex items-center justify-between rounded-[4px] border border-grey-300 bg-grey-50 px-3.5 py-2.5 text-[15px] font-medium">
                  {@landing.timer.project}
                  <svg
                    viewBox="0 0 16 16"
                    fill="none"
                    class="size-4 stroke-current stroke-[1.5] [stroke-linecap:round] [stroke-linejoin:round]"
                    aria-hidden="true"
                  >
                    <path d="M4 6l4 4 4-4" />
                  </svg>
                </p>
                <div class="mt-6 flex items-center justify-between gap-4">
                  <p
                    class="feature-timer text-[clamp(34px,4vw,44px)] leading-none font-bold tracking-[-0.02em] text-[#0f0f0f] tabular-nums"
                    style={"--timer-m: #{@landing.timer.minutes}; --timer-s: #{@landing.timer.seconds}; --timer-offset: -#{@landing.timer.minutes * 60 + @landing.timer.seconds}s"}
                    aria-label={@texts.timer_running}
                  >
                    <span aria-hidden="true">{pad(@landing.timer.hours)}:</span><span
                      class="feature-timer__m"
                      aria-hidden="true"
                    ></span><span aria-hidden="true">:</span><span
                      class="feature-timer__s"
                      aria-hidden="true"
                    ></span>
                  </p>
                  <span class="inline-flex min-h-11 items-center rounded-[4px] bg-[#0f0f0f] px-8 text-[15px] font-semibold text-white">
                    {@texts.timer_stop}
                  </span>
                </div>
                <div class="mt-7 flex items-baseline justify-between border-t border-grey-200 pt-5 text-caps-sm font-semibold tracking-[.08em] text-grey-600 uppercase">
                  <span>{@landing.timer.month}</span>
                  <span class="text-[13px] tracking-normal text-[#0f0f0f] normal-case">
                    {@landing.timer.total}
                  </span>
                </div>
                <div
                  :for={project <- @landing.timer.projects}
                  class="mt-3 grid grid-cols-[minmax(0,.9fr)_minmax(0,1.3fr)_auto] items-center gap-3 text-sm"
                >
                  <span class="truncate font-medium">{project.name}</span>
                  <span class="h-2 overflow-hidden rounded-full bg-grey-100">
                    <span
                      class="feature-timer__bar block h-full rounded-full bg-rust-500"
                      style={"width: #{project.share}%"}
                    ></span>
                  </span>
                  <span class="w-[5.5em] text-right font-semibold tabular-nums">
                    {project.hours}
                  </span>
                </div>
              </div>
              <div
                :if={@landing.split}
                class="rotate-[1.2deg] rounded-[4px] bg-white p-5 font-sans shadow-[0_1px_0_var(--color-grey-200),0_30px_60px_-30px_rgba(87,54,35,.45)] sm:p-7"
              >
                <p class="text-caps-sm font-semibold tracking-[.08em] text-grey-600 uppercase">
                  {@landing.split.period}
                </p>
                <p class="mt-3 text-[clamp(22px,2.6vw,30px)] leading-[1.15] font-bold tracking-[-0.02em]">
                  {@texts.split_headline}
                  <span class="rounded-[4px] bg-teal-700 px-2 whitespace-nowrap text-white">
                    {@landing.split.left} zł
                  </span>
                </p>
                <div class="mt-6 flex h-9 overflow-hidden rounded-[4px]" aria-hidden="true">
                  <span
                    :for={{cost, index} <- Enum.with_index(@landing.split.costs)}
                    class="feature-timer__bar block h-full"
                    style={"width: #{cost.share}%; background: #{split_color(index)}"}
                  ></span>
                  <span class="block h-full flex-1 bg-teal-700"></span>
                </div>
                <div
                  :for={{cost, index} <- Enum.with_index(@landing.split.costs)}
                  class="mt-3 flex items-center gap-3 text-sm"
                >
                  <span
                    class="size-2.5 shrink-0 rounded-[2px]"
                    style={"background: #{split_color(index)}"}
                  ></span>
                  <span class="min-w-0 flex-1 truncate font-medium">{cost.name}</span>
                  <span class="font-semibold tabular-nums">{cost.share} {@texts.split_of}</span>
                </div>
                <div class="mt-3 flex items-center gap-3 border-t border-grey-200 pt-3 text-sm">
                  <span class="size-2.5 shrink-0 rounded-[2px] bg-teal-700"></span>
                  <span class="min-w-0 flex-1 truncate font-medium text-teal-800">
                    {@texts.split_left}
                  </span>
                  <span class="font-semibold text-teal-800 tabular-nums">
                    {@landing.split.left} {@texts.split_of}
                  </span>
                </div>
              </div>
              <div
                :if={@layout.hero && @landing.match == [] && !@landing.timer && !@landing.split}
                class="rotate-[1.2deg] rounded-[4px] bg-white p-2.5 shadow-[0_1px_0_var(--color-grey-200),0_30px_60px_-30px_rgba(87,54,35,.45)] sm:p-3.5"
              >
                <img
                  src={@layout.hero.src}
                  width={@layout.hero.width}
                  height={@layout.hero.height}
                  alt={@layout.hero.alt}
                  fetchpriority="high"
                  class="block h-auto w-full rounded-[2px]"
                />
              </div>
              <figcaption
                :if={@landing.note}
                class="absolute -bottom-12 left-2 flex -rotate-3 items-end gap-2 font-['Nothing_You_Could_Do',cursive] text-[22px] leading-none text-rust-600 sm:left-6"
              >
                <svg
                  viewBox="0 0 60 40"
                  fill="none"
                  class="mb-3 w-12 -scale-x-100 stroke-current stroke-2 [stroke-linecap:round] [stroke-linejoin:round]"
                  aria-hidden="true"
                >
                  <path d="M4 34 C 20 36, 40 28, 50 10" /><path d="M38 10 L51 8 L54 21" />
                </svg>
                {@landing.note}
              </figcaption>
            </figure>
          </div>
        </section>

        <section :if={@landing.facts != []} class="border-y border-rust-200 bg-grey-50">
          <dl class="mx-auto grid w-[min(1140px,calc(100%-32px))] grid-cols-1 sm:grid-cols-3">
            <div
              :for={fact <- @landing.facts}
              class="border-rust-200 py-5 sm:border-l sm:px-6 sm:first:border-l-0 sm:first:pl-0"
            >
              <dt class="text-xs font-semibold tracking-[.08em] text-rust-700 uppercase">
                {fact.label}
              </dt>
              <dd class="mt-1.5 text-[17px] font-semibold">{fact.value}</dd>
            </div>
          </dl>
        </section>

        <section :if={@layout.intro != ""} class="pt-16 lg:pt-24">
          <figure class="relative mx-auto w-[min(920px,calc(100%-32px))] rounded-[4px] bg-[#0f0f0f] px-7 py-9 text-[#f5f1ea] sm:p-14">
            <span
              aria-hidden="true"
              class="block h-[.42em] text-[clamp(84px,9vw,120px)] leading-[.8] font-bold text-rust-500"
            >
              “
            </span>
            <blockquote class={[
              "mt-3 font-medium tracking-[-0.01em] [&_a]:underline [&_a]:decoration-rust-500 [&_a]:underline-offset-4 [&_p+p]:mt-5",
              if(String.length(@layout.intro) > 420,
                do: "text-[clamp(18px,1.8vw,22px)] leading-[1.45]",
                else: "text-[clamp(20px,2.3vw,28px)] leading-[1.35]"
              )
            ]}>
              {Phoenix.HTML.raw(@layout.intro)}
            </blockquote>
            <figcaption class="mt-8 flex items-center gap-4 text-[15px] text-[#f5f1ea]/70">
              <img
                src={@author.image}
                width="832"
                height="1248"
                alt=""
                loading="lazy"
                class="size-12 shrink-0 rounded-full bg-[#f5f1ea] object-cover object-[50%_8%]"
              />
              <span><b class="font-semibold text-[#f5f1ea]">{@author.name}</b> · {@author.role}</span>
            </figcaption>
          </figure>
        </section>

        <section
          :for={section <- @layout.sections}
          id={section.id}
          class={[
            "pt-16 last:pb-24 lg:pt-24",
            section.band? && "mt-16 border-y border-rust-200 bg-white pb-16 lg:mt-24 lg:pb-24"
          ]}
        >
          <div class={[
            "mx-auto grid w-[min(1140px,calc(100%-32px))] grid-cols-[minmax(0,1fr)] gap-6 lg:gap-14",
            if(section.wide?, do: "lg:gap-10", else: "lg:grid-cols-[minmax(0,.34fr)_minmax(0,.66fr)]")
          ]}>
            <h2 class={[
              "text-[clamp(28px,3vw,40px)] leading-[1.1] font-bold tracking-[-0.03em] text-balance",
              !section.wide? &&
                "lg:sticky lg:top-[calc(var(--landing-nav-height)+24px)] lg:self-start"
            ]}>
              {Phoenix.HTML.raw(section.title)}
            </h2>
            <div class={section_body_styles()}>
              {Phoenix.HTML.raw(section.html)}
            </div>
          </div>
        </section>
      </main>

      <.cta_footer />
    </div>
    """
  end

  # Cost segments of the split bar, from the largest to the smallest.
  defp split_color(index) do
    Enum.at(
      [
        "var(--color-rust-800)",
        "var(--color-rust-600)",
        "var(--color-rust-400)",
        "var(--color-rust-200)"
      ],
      index,
      "var(--color-grey-300)"
    )
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")

  # Prose inside a section: paragraphs, tables, screenshots, step cards and
  # collapsible questions, all styled from the rendered Markdown.
  defp section_body_styles do
    [
      "min-w-0 text-[17px] leading-[1.65] text-grey-700",
      "[&_p]:max-w-[62ch] [&_p+p]:mt-4 [&_p:has(+.table-scroll)]:mb-4 [&_.table-scroll+p]:mt-4 [&_.table-scroll+p]:text-[13px] [&_.table-scroll+p]:leading-normal [&_.table-scroll+p]:text-grey-600",
      "[&_a]:text-[#0f0f0f] [&_a]:underline [&_a]:decoration-rust-400 [&_a]:underline-offset-[3px] [&_a:hover]:text-rust-700",
      "[&_strong]:text-[#0f0f0f]",
      "[&_figcaption]:mt-3 [&_figcaption]:text-[13px] [&_figcaption]:text-grey-600 [&_figure]:my-8 [&_figure]:first:mt-0 [&_figure_img]:block [&_figure_img]:h-auto [&_figure_img]:w-full [&_figure_img]:rounded-[4px] [&_figure_img]:bg-white [&_figure_img]:p-2 [&_figure_img]:shadow-[0_1px_0_var(--color-grey-200),0_26px_50px_-30px_rgba(87,54,35,.45)]",
      "[&_.table-scroll]:mt-2 [&_.table-scroll]:overflow-x-auto [&_.table-scroll]:rounded-[4px] [&_.table-scroll]:border [&_.table-scroll]:border-grey-200 [&_.table-scroll]:bg-white [&_table]:w-full [&_table]:font-sans [&_table]:text-[14.5px] [&_table]:leading-snug",
      "[&_.table-scroll+.table-scroll]:mt-6 [&_th]:px-4 [&_th]:py-3 [&_th]:text-left [&_th]:text-[11.5px] [&_th]:font-semibold [&_th]:tracking-[.06em] [&_th]:text-grey-600 [&_th]:uppercase [&_thead]:bg-grey-50 [&_thead:not(:has(th:not(:empty)))]:hidden",
      "[&_tbody_tr:first-child_td]:border-t-0 [&_td]:border-t [&_td]:border-grey-200 [&_td]:px-4 [&_td]:py-3 [&_td]:align-top [&_td:first-child]:font-medium [&_td:first-child]:text-[#0f0f0f] [&_thead+tbody_tr:first-child_td]:border-t",
      "[&_ol.steps]:grid [&_ol.steps]:gap-3 [&_ol.steps]:[counter-reset:step] sm:[&_ol.steps]:grid-cols-2 xl:[&_ol.steps]:grid-cols-3",
      "[&_.steps>li]:relative [&_.steps>li]:rounded-[4px] [&_.steps>li]:border [&_.steps>li]:border-grey-200 [&_.steps>li]:bg-white [&_.steps>li]:p-5 [&_.steps>li]:pt-14 [&_.steps>li]:font-sans [&_.steps>li]:text-[14.5px] [&_.steps>li]:leading-snug [&_.steps>li]:[counter-increment:step]",
      "[&_.steps>li]:before:absolute [&_.steps>li]:before:top-4 [&_.steps>li]:before:left-5 [&_.steps>li]:before:grid [&_.steps>li]:before:size-7 [&_.steps>li]:before:place-items-center [&_.steps>li]:before:rounded-full [&_.steps>li]:before:bg-rust-500 [&_.steps>li]:before:text-[13px] [&_.steps>li]:before:font-bold [&_.steps>li]:before:text-[#0f0f0f] [&_.steps>li]:before:content-[counter(step)]",
      "[&_.steps_b]:block [&_.steps_b]:font-landing [&_.steps_b]:text-[17px] [&_.steps_b]:font-semibold [&_.steps_b]:text-[#0f0f0f] [&_.steps_span]:mt-1.5 [&_.steps_span]:block [&_.steps_span:first-of-type]:text-[11.5px] [&_.steps_span:first-of-type]:font-semibold [&_.steps_span:first-of-type]:tracking-[.06em] [&_.steps_span:first-of-type]:text-rust-700 [&_.steps_span:first-of-type]:uppercase",
      "[&_p:has(>img+img)]:flex [&_p:has(>img+img)]:max-w-none [&_p:has(>img+img)]:flex-wrap [&_p:has(>img+img)]:gap-3 [&_p:has(>img+img)>img]:size-14 [&_p:has(>img+img)>img]:rounded-full [&_p:has(>img+img)>img]:bg-white [&_p:has(>img+img)>img]:object-contain [&_p:has(>img+img)>img]:p-2.5 [&_p:has(>img+img)>img]:shadow-[0_0_0_1px_var(--color-grey-200),0_8px_18px_-10px_rgba(87,54,35,.45)]",
      "[&_p:has(>img+img)+ul]:mt-5 [&_p:has(>img+img)+ul]:flex [&_p:has(>img+img)+ul]:flex-wrap [&_p:has(>img+img)+ul]:gap-2 [&_p:has(>img+img)+ul>li]:rounded-full [&_p:has(>img+img)+ul>li]:border [&_p:has(>img+img)+ul>li]:border-grey-200 [&_p:has(>img+img)+ul>li]:bg-white [&_p:has(>img+img)+ul>li]:px-3.5 [&_p:has(>img+img)+ul>li]:py-1.5 [&_p:has(>img+img)+ul>li]:font-sans [&_p:has(>img+img)+ul>li]:text-[14px] [&_p:has(>img+img)+ul>li]:leading-snug [&_p:has(>img+img)+ul>li]:font-medium [&_p:has(>img+img)+ul>li]:text-[#0f0f0f] [&_ul+p]:mt-5",
      "[&_tr.firmowid]:bg-[#0f0f0f] [&_tr.firmowid_a]:text-white [&_tr.firmowid_td]:border-transparent [&_tr.firmowid_td]:text-white",
      "[&_details]:border-b [&_details]:border-rust-200 [&_details:first-of-type]:border-t [&_summary]:flex [&_summary]:cursor-pointer [&_summary]:list-none [&_summary]:items-center [&_summary]:justify-between [&_summary]:gap-6 [&_summary]:py-5 [&_summary]:text-h5 [&_summary]:font-semibold [&_summary]:text-[#0f0f0f] [&_summary::-webkit-details-marker]:hidden",
      "[&_details>div]:pb-6 [&_details>div]:text-base [&_details[open]_summary]:after:content-['−'] [&_summary]:after:shrink-0 [&_summary]:after:text-2xl [&_summary]:after:font-normal [&_summary]:after:text-rust-600 [&_summary]:after:content-['+']"
    ]
  end
end
