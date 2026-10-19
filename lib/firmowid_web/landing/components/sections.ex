defmodule FirmowidWeb.Landing.Components.Sections do
  @moduledoc """
  Main content sections for the public website.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.Landing.Components.Primitives, only: [landing_button: 1]

  alias Phoenix.LiveView.Rendered

  @repository "https://github.com/Alergeek-Ventures/firmowid"

  @problems [
    %{
      title: gettext_noop("Scattered tools"),
      description:
        gettext_noop(
          "One program for invoicing, another for time tracking, and yet another for bank reconciliation. Data does not match and reports are prepared manually."
        )
    },
    %{
      title: gettext_noop("Invoices appear in KSeF and you do not even know"),
      description:
        gettext_noop(
          "To find out about a new invoice, you have to log in to KSeF. Firmowid downloads documents continuously, and paid plans email you as soon as a new invoice arrives."
        )
    },
    %{
      title: gettext_noop("A budget that is outdated the day it is created"),
      description:
        gettext_noop(
          "Who worked how much? What fit within the project budget? By the time you prepare a summary, the week is over."
        )
    }
  ]

  @features [
    %{
      tags: [gettext_noop("invoicing"), "KSeF"],
      title: gettext_noop("Invoices that reach KSeF by themselves"),
      description:
        gettext_noop(
          "Create, send, receive. Firmowid connects to the National e-Invoice System and tracks every regulatory change for you."
        ),
      bullets: [
        gettext_noop("Automatic KSeF compliance validation"),
        gettext_noop("Invoice import and export (file, email, scan)"),
        gettext_noop("Integration with business accounts, including foreign accounts"),
        gettext_noop("Error notifications before documents reach the tax office")
      ],
      visual: :invoices
    },
    %{
      tags: [gettext_noop("invoicing"), gettext_noop("bank accounts")],
      title: gettext_noop("Transactions matched to invoices"),
      description:
        gettext_noop(
          "Every transaction is automatically assigned to the right invoice. No more manually matching transfers at the end of the month."
        ),
      bullets: [
        gettext_noop("Automatic transaction matching to invoices"),
        gettext_noop("Integration with major Polish banks"),
        gettext_noop("One-click export for accounting"),
        gettext_noop("Alerts for unpaid invoices")
      ],
      visual: :banking
    },
    %{
      tags: [gettext_noop("record-keeping"), gettext_noop("working hours")],
      title: gettext_noop("Hours that count themselves"),
      description:
        gettext_noop(
          "Your employees track their hours, but you still do not know what your team really costs? Firmowid keeps everything under control."
        ),
      bullets: [
        gettext_noop("Real-time working hours monitoring"),
        gettext_noop("Hours recorded per project and employee"),
        gettext_noop("Labor costs visible in reports immediately"),
        gettext_noop("One-click time tracking export")
      ],
      visual: :time
    },
    %{
      tags: [gettext_noop("HR"), gettext_noop("leave and business trips")],
      title: gettext_noop("Leave, business trips and team documents in one place."),
      description:
        gettext_noop(
          "Employees submit leave requests and settle business trips in Firmowid, and you approve them with one click. Records show how many hours everyone worked - ready for payroll."
        ),
      bullets: [
        gettext_noop("Leave requests with approval"),
        gettext_noop("Business trips"),
        gettext_noop("Employee contracts and documents"),
        gettext_noop("Tracked hours ready for payroll")
      ],
      visual: :team
    }
  ]

  @steps [
    %{
      title: gettext_noop("Create an account"),
      description: gettext_noop("Email, password, company name. Start with the free plan. No card required.")
    },
    %{
      title: gettext_noop("Integrate your data"),
      description:
        gettext_noop(
          "We will connect your bank account and KSeF. We will import contacts from a file or your previous system."
        )
    },
    %{
      title: gettext_noop("Create your first invoice"),
      description:
        gettext_noop("Choose a contact, click “create”. Firmowid will handle the rest — including sending it to KSeF.")
    }
  ]

  @team [
    %{
      name: "Franek Madej",
      role: gettext_noop("CEO · Alergeek Ventures"),
      image: "/images/team-franek-madej.png",
      bio:
        gettext_noop(
          "For a decade, he has advised companies on software development, including startups from the Y Combinator ecosystem. He is obsessed with polished products and turning complex processes into simple tools."
        )
    },
    %{
      name: "Stanisław Madej",
      role: gettext_noop("COO · Alergeek Ventures"),
      image: "/images/team-stanislaw-madej.png",
      bio:
        gettext_noop(
          "At Alergeek Ventures, he handles company logistics and manages a team of 20. A happy Firmowid user, he uses it for daily tasks, leaving more time for management and less for invoices and settlements."
        )
    }
  ]

  @doc """
  Renders the audience/problem section.
  """
  @spec audience_section(map()) :: Rendered.t()
  def audience_section(assigns) do
    assigns = assign(assigns, :problems, localize(@problems, [:title, :description]))

    ~H"""
    <section
      id="dla-kogo"
      data-landing-dark-surface
      class="bg-[#0f0f0f] py-18 text-white lg:py-26 [&_.landing-eyebrow]:text-orange-500 [&_.landing-section-intro_>_p:not(.landing-eyebrow)]:text-grey-300 [&_article_p]:text-grey-300"
    >
      <div class="mx-auto w-[calc(100%-var(--spacing)*8)] max-w-284.75 lg:w-[calc(100%-var(--spacing)*16)]">
        <div class="landing-section-intro max-w-180 lg:max-w-170 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:mt-6 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-h5/6.75 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-darkGrey lg:[&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:max-w-170 [&_h2]:text-[2.25rem] [&_h2]:leading-[1.1] [&_h2]:font-bold [&_h2]:tracking-[-0.03em] lg:[&_h2]:text-[3rem] lg:[&_h2]:leading-[1.04] lg:[&.text-center]:mx-auto lg:[&.text-center_>_p:not(.landing-eyebrow)]:mx-auto">
          <p class="landing-eyebrow mb-4 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
            {gettext("Who it is for")}
          </p>
          <h2>
            {gettext("You run a business.")}<br class="hidden lg:block" />
            {gettext("You do not want to manage spreadsheets.")}
          </h2>
          <p>
            {gettext(
              "Firmowid was created for Polish SMEs that are tired of jumping from one program to another and recording everything in spreadsheets."
            )}
          </p>
        </div>

        <div class="mt-10 grid gap-9 bg-[url('/images/landing/decorations/dark-separator.svg')] bg-size-[100%_--spacing(0.5)] bg-top bg-no-repeat pt-9 lg:mt-12 lg:grid-cols-3 lg:gap-10 lg:pt-10 [&_.landing-eyebrow]:mb-5 [&_h3]:mb-5 [&_h3]:text-xl [&_h3]:leading-[1.3] [&_h3]:font-semibold [&_h3]:tracking-[-0.01em] [&_p]:text-base [&_p]:leading-[1.4]">
          <article :for={{problem, index} <- Enum.with_index(@problems, 1)}>
            <p class="landing-eyebrow mb-4 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
              0{index}
            </p>
            <h3>{problem.title}</h3>
            <p>{problem.description}</p>
          </article>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the four product features with noninteractive previews.
  """
  @spec capabilities_section(map()) :: Rendered.t()
  def capabilities_section(assigns) do
    assigns = assign(assigns, :features, localize_features(@features))

    ~H"""
    <section id="funkcje" class="py-18 lg:py-26">
      <div class="mx-auto w-[calc(100%-var(--spacing)*8)] max-w-284.75 lg:w-[calc(100%-var(--spacing)*16)]">
        <div class="landing-section-intro max-w-180 lg:max-w-284.75 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:mt-6 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-h5/6.75 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-darkGrey lg:[&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:max-w-115 [&_h2]:text-[2.25rem] [&_h2]:leading-[1.1] [&_h2]:font-bold [&_h2]:tracking-[-0.03em] lg:[&_h2]:text-[3rem] lg:[&_h2]:leading-[1.04] lg:[&.text-center]:mx-auto lg:[&.text-center]:max-w-140 lg:[&.text-center_>_p:not(.landing-eyebrow)]:mx-auto">
          <p class="landing-eyebrow mb-4 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
            {gettext("What Firmowid can do")}
          </p>
          <h2>
            {gettext("Four things your business needs.")}
            {gettext("In one place.")}
          </h2>
          <p class="lg:hidden">
            {gettext(
              "Firmowid was created for Polish SMEs that are tired of jumping from one program to another and recording everything in spreadsheets."
            )}
          </p>
        </div>

        <article
          :for={feature <- @features}
          class="landing-feature mt-8 grid gap-6 rounded-2xl border border-[#e3b79b] bg-white p-6 lg:mt-20 lg:grid-cols-2 lg:items-center lg:gap-20 lg:border-0 lg:bg-transparent lg:p-0 lg:last:pb-0 [&_h3]:mt-4 [&_h3]:mb-5 [&_h3]:text-lg [&_h3]:leading-[1.15] [&_h3]:font-bold [&_h3]:tracking-[-0.01em] lg:[&_h3]:text-[2.25rem] lg:[&_h3]:leading-[1.05] lg:[&_li]:flex lg:[&_li]:items-start lg:[&_li]:gap-3 [&_ul]:hidden lg:[&_ul]:mt-7 lg:[&_ul]:grid lg:[&_ul]:gap-3.5 lg:[&_ul]:text-base/normal lg:[&+.landing-feature]:mt-16 lg:[&+.landing-feature]:bg-[url('/images/landing/decorations/feature-separator.svg')] lg:[&+.landing-feature]:bg-size-[100%_--spacing(0.5)] lg:[&+.landing-feature]:bg-top lg:[&+.landing-feature]:bg-no-repeat lg:[&+.landing-feature]:pt-16 lg:[&:nth-of-type(even)_>_:first-child]:order-2"
        >
          <div>
            <p class="flex flex-wrap gap-2.5 text-xs font-bold tracking-[0.06em] text-(--landing-accent) uppercase lg:flex [&_span]:inline-block [&_span]:p-0 [&_span]:text-sm [&_span]:font-semibold [&_span]:tracking-[0.08em] [&_span]:uppercase lg:[&_span]:rounded-full lg:[&_span]:bg-[#f7e0d3] lg:[&_span]:px-4 lg:[&_span]:py-1 lg:[&_span]:font-normal lg:[&_span]:tracking-normal lg:[&_span]:normal-case [&_span+span]:border-0 [&_span+span::before]:mr-2.5 [&_span+span::before]:content-['·'] lg:[&_span+span::before]:content-none">
              <span :for={tag <- feature.tags}>{tag}</span>
            </p>
            <h3>{feature.title}</h3>
            <p class="text-base/6.75 text-darkGrey lg:text-h5">
              {feature.description}
            </p>
            <ul>
              <li :for={bullet <- feature.bullets}>
                <img
                  src={~p"/images/landing/icons/arrow.svg"}
                  alt=""
                  width="24"
                  height="24"
                  class="shrink-0"
                />{bullet}
              </li>
            </ul>
          </div>
          <.product_preview visual={feature.visual} />
        </article>
      </div>
    </section>
    """
  end

  @doc false
  @spec product_preview(map()) :: Rendered.t()
  attr :visual, :atom, required: true

  defp product_preview(assigns) do
    ~H"""
    <div
      class={[
        "@container relative min-w-0 rounded-2xl border border-(--landing-line) bg-[#f5f5f5] text-caps-sm leading-[1.4] shadow-[0_0.875rem_2.125rem_rgb(80_50_30/8%)] lg:px-5.5 lg:py-6.5 lg:text-xs [&_h4]:mb-4.5 [&_h4]:text-sm [&_h4]:font-semibold lg:[&_h4]:text-base",
        @visual == :invoices &&
          "p-4 [&_.landing-preview-amount]:size-full [&_.landing-preview-amount]:rounded-none [&_.landing-preview-amount]:p-[2.2cqw_1cqw] [&_.landing-preview-amount]:text-center [&_.landing-preview-amount]:text-[1.5cqw] [&_.landing-preview-amount]:text-(--landing-accent) [&_.landing-preview-amount--teal]:text-turquoise-700 [&_.landing-preview-head]:bg-transparent [&_.landing-preview-head]:p-3 [&_.landing-preview-head]:text-[1.4cqw] [&_.landing-preview-head]:font-normal [&_.landing-preview-row]:grid [&_.landing-preview-row]:grid-cols-[minmax(0,1fr)_18%_22%] [&_.landing-preview-row]:gap-0 [&_.landing-preview-row]:rounded-none [&_.landing-preview-row]:bg-white [&_.landing-preview-row]:p-0 [&_.landing-preview-row]:text-[1.5cqw] [&_.landing-preview-status]:mx-1 [&_.landing-preview-status]:border-0 [&_.landing-preview-status]:bg-[#f5f5f5] [&_.landing-preview-status]:p-0.75 [&_.landing-preview-status]:text-center [&_.landing-preview-status]:text-[1.1cqw] [&_.landing-preview-status]:leading-none [&_.landing-preview-status]:whitespace-nowrap [&_.landing-preview-status.landing-preview-status--paid]:bg-green-100",
        @visual == :banking && "p-4",
        @visual == :time &&
          "aspect-528/400 px-4 py-6 [&_.landing-preview-caption]:mt-[8cqw] [&_.landing-preview-caption]:text-left [&_.landing-preview-caption]:text-[2.3cqw] [&_.landing-preview-caption]:text-grey-600 [&_.landing-preview-head]:mb-[4cqw] [&_.landing-preview-head]:bg-transparent [&_.landing-preview-head]:p-0 [&_.landing-preview-head]:text-[2.4cqw] [&_.landing-preview-head]:text-(--landing-accent) [&_.landing-preview-head_>_span:last-child]:bg-[#e6d7ce] [&_.landing-preview-head_>_span:last-child]:text-[3.5cqw] [&_.landing-preview-overlay]:right-[-4%] [&_.landing-preview-overlay]:bottom-[-7%] [&_.landing-preview-overlay]:left-auto [&_.landing-preview-overlay]:flex [&_.landing-preview-overlay]:w-[54%] [&_.landing-preview-overlay]:flex-col [&_.landing-preview-overlay]:items-stretch [&_.landing-preview-overlay]:gap-[1.5cqw] [&_.landing-preview-overlay]:p-[4cqw] [&_.landing-preview-overlay]:[background:#f5f5f5_url('/images/figurine_timeracker.png')_left_bottom/40%_auto_no-repeat] [&_.landing-preview-overlay_small]:text-center [&_.landing-preview-overlay_small]:text-[1.5cqw] [&_.landing-preview-overlay_small]:text-(--landing-accent) [&_.landing-preview-overlay_strong]:pt-[3cqw] [&_.landing-preview-overlay_strong]:text-center [&_.landing-preview-overlay_strong]:text-[2.7cqw] [&_.landing-preview-overlay_strong]:text-(--landing-accent) [&_.landing-preview-row]:rounded-none [&_.landing-preview-row]:border-b [&_.landing-preview-row]:border-[#eee] [&_.landing-preview-row]:bg-transparent [&_.landing-preview-row]:p-[1.8cqw_0] [&_.landing-preview-row]:text-[2.4cqw] [&_.landing-preview-row:nth-of-type(3)]:mt-[8cqw]",
        @visual == :team &&
          "aspect-528/400 px-4 pt-5 pb-15 [&_.landing-preview-avatar]:size-[10cqw] [&_.landing-preview-avatar]:text-[3cqw] [&_.landing-preview-caption]:m-0 [&_.landing-preview-caption]:bg-white [&_.landing-preview-caption]:p-[2cqw] [&_.landing-preview-caption]:text-left [&_.landing-preview-caption]:text-[1.5cqw] [&_.landing-preview-caption]:text-grey-600 [&_.landing-preview-head]:m-0 [&_.landing-preview-head]:rounded-t-sm [&_.landing-preview-head]:rounded-b-none [&_.landing-preview-head]:bg-white [&_.landing-preview-head]:p-[2cqw] [&_.landing-preview-head]:text-[1.6cqw] [&_.landing-preview-overlay]:right-auto [&_.landing-preview-overlay]:bottom-[-6%] [&_.landing-preview-overlay]:left-[-4%] [&_.landing-preview-overlay]:w-[55%] [&_.landing-preview-overlay]:gap-[2cqw] [&_.landing-preview-overlay]:p-[2.5cqw] [&_.landing-preview-pending.landing-preview-row]:mb-[3cqw] [&_.landing-preview-pending.landing-preview-row]:pb-[3cqw] [&_.landing-preview-row]:m-0 [&_.landing-preview-row]:min-h-[5.6cqw] [&_.landing-preview-row]:rounded-none [&_.landing-preview-row]:bg-white [&_.landing-preview-row]:p-[1.3cqw_2cqw] [&_.landing-preview-row]:text-[1.7cqw] [&_.landing-preview-row_small]:text-[1.5cqw] [&_.landing-preview-row+.landing-preview-row]:mt-0 [&_.landing-preview-status]:rounded-full [&_.landing-preview-status]:border-0 [&_.landing-preview-status]:p-[0.5cqw_2cqw] [&_.landing-preview-status]:text-[1.5cqw]"
      ]}
      role="img"
      aria-label={gettext("Illustrative product preview")}
    >
      <%= case @visual do %>
        <% :invoices -> %>
          <div class="landing-preview-head mb-1 flex items-center justify-between gap-2 rounded-md bg-[#eadcd4] px-3 py-2 font-semibold [&_span:last-child]:rounded-sm [&_span:last-child]:bg-white [&_span:last-child]:px-2 [&_span:last-child]:py-0.5 [&_span:last-child]:text-caps-sm">
            <span>{gettext("Counterparty")}</span>
            <span>{gettext("Status")}</span>
          </div>
          <div
            :for={row <- contractor_invoices()}
            class="landing-preview-row flex flex-wrap items-center gap-1.5 rounded-lg bg-[#faf7f5] p-3 text-caps-sm [&_small]:text-caps-sm [&_small]:font-normal [&_small]:text-darkGrey [&+.landing-preview-row]:mt-1.5"
          >
            <span class="landing-preview-contractor flex items-center gap-[1cqw] overflow-hidden p-[1cqw] whitespace-nowrap [&_img]:size-[4cqw] [&_img]:shrink-0 [&_img]:border [&_img]:border-grey-200 [&_img]:object-contain [&_small]:overflow-hidden [&_small]:text-[1.4cqw] [&_small]:text-ellipsis [&_strong]:shrink-0 [&_strong]:font-semibold [&.landing-preview-contractor_small]:text-[1.4cqw] lg:[&.landing-preview-contractor_small]:text-caps-sm"><img
              src={~p"/images/ksef.png"}
              alt=""
              width="24"
              height="24"
            /><strong>{row.name}</strong> <small>{row.note}</small></span>
            <span class={[
              "landing-preview-status ml-auto rounded-sm border border-(--landing-line) bg-white px-2 py-0.75 text-[0.5rem] uppercase lg:text-caps-sm",
              row.paid &&
                "landing-preview-status--paid border-[#c6dcbf] [&.landing-preview-status--paid]:bg-[#dcecd8]"
            ]}>
              {row.status}
            </span>
            <span class={[
              "landing-preview-amount ml-auto rounded-sm bg-[#eadcd4] px-3 py-2 font-semibold whitespace-nowrap",
              row.tone == :teal &&
                "landing-preview-amount--teal [&.landing-preview-amount--teal]:bg-[#cfe6e6]"
            ]}>
              {gettext("%{amount} PLN", amount: row.amount)}
            </span>
          </div>
        <% :banking -> %>
          <div class="grid grid-cols-2 gap-[3cqw] [&_.landing-preview-caption]:mt-auto [&_.landing-preview-caption]:pt-[3cqw] [&_.landing-preview-caption]:pb-[1cqw] [&_.landing-preview-caption]:text-[2.3cqw] [&_.landing-preview-head]:gap-0.75 [&_.landing-preview-head]:p-[2cqw] [&_.landing-preview-head]:text-[2.2cqw] [&_.landing-preview-head_>_span:last-child]:p-[1cqw_2cqw] [&_.landing-preview-head_>_span:last-child]:text-[2cqw] [&_.landing-preview-match]:mt-0 [&_.landing-preview-match]:p-[1cqw] [&_.landing-preview-match]:text-[1.5cqw] [&_.landing-preview-row]:min-h-[10cqw] [&_.landing-preview-row]:gap-[1.2cqw] [&_.landing-preview-row]:bg-white [&_.landing-preview-row]:p-[1.6cqw] [&_.landing-preview-row]:text-[1.8cqw] [&_.landing-preview-row_>_span:first-child]:min-w-0 [&_.landing-preview-row_>_span:first-child]:flex-1 [&_.landing-preview-row_>_span:first-child]:truncate [&_.landing-preview-row_img]:ml-auto [&_.landing-preview-row_img]:h-[2.4cqw] [&_.landing-preview-row_img]:w-[4cqw] [&_.landing-preview-row_img]:object-contain [&_.landing-preview-row_small]:w-[65%] [&_.landing-preview-row_small]:text-[1.5cqw] [&_.landing-preview-row_small]:text-grey-500 [&_.landing-preview-row_strong]:text-[1.8cqw] [&_.landing-preview-row_strong]:font-semibold [&_>_div]:flex [&_>_div]:flex-col [&_>_div]:rounded-sm [&_>_div]:bg-[#f0eae6] [&_>_div]:p-[1.6cqw] [&_>_div+div]:bg-turquoise-100">
            <div>
              <div class="landing-preview-head mb-1 flex items-center justify-between gap-2 rounded-md bg-[#eadcd4] px-3 py-2 font-semibold [&_span:last-child]:rounded-sm [&_span:last-child]:bg-white [&_span:last-child]:px-2 [&_span:last-child]:py-0.5 [&_span:last-child]:text-caps-sm">
                <span>{gettext("Transactions to match")}</span>
                <span>6</span>
              </div>
              <div
                :for={row <- unmatched_transactions()}
                class="landing-preview-row flex flex-wrap items-center gap-1.5 rounded-lg bg-[#faf7f5] p-3 text-caps-sm [&_small]:text-caps-sm [&_small]:font-normal [&_small]:text-darkGrey [&+.landing-preview-row]:mt-1.5"
              >
                <span>{row.name}</span>
                <strong class={[
                  "text-[#a22a2a]",
                  String.starts_with?(row.amount, "+") &&
                    "text-green-600"
                ]}>{pgettext("landing bank amount", "%{amount} PLN", amount: row.amount)}</strong>
                <small>{row.date}</small>
                <img
                  src={~p"/images/invoicing_badges/mbk_wa_1.svg"}
                  alt="mBank"
                  width="22"
                  height="12"
                />
              </div>
              <p class="landing-preview-caption mt-4 text-center text-caps-sm text-(--landing-accent)">
                {gettext("See all")}
              </p>
            </div>
            <div>
              <div class="landing-preview-head mb-1 flex items-center justify-between gap-2 rounded-md bg-turquoise-200 px-3 py-2 font-semibold [&_span:last-child]:rounded-sm [&_span:last-child]:bg-white [&_span:last-child]:px-2 [&_span:last-child]:py-0.5 [&_span:last-child]:text-caps-sm">
                <span>{gettext("Matched")}</span>
                <span>36</span>
              </div>
              <div
                :for={row <- matched_transactions()}
                class="landing-preview-row flex flex-wrap items-center gap-1.5 rounded-lg bg-[#faf7f5] p-3 text-caps-sm [&_small]:text-caps-sm [&_small]:font-normal [&_small]:text-darkGrey [&+.landing-preview-row]:mt-1.5"
              >
                <span>{row.name} <small>{row.reference}</small></span>
                <strong>{pgettext("landing bank amount", "%{amount} PLN", amount: row.amount)}</strong>
                <span class="landing-preview-match mt-1.5 flex flex-[1_1_100%] items-center gap-1.5 rounded-sm bg-[#dcecd8] px-2 py-1 text-caps-sm text-greenText [&_progress]:h-1 [&_progress]:flex-1 [&_progress]:accent-green-600">
                  {row.confidence}%
                  <progress value={row.confidence} max="100">{row.confidence}%</progress>
                </span>
              </div>
              <p class="landing-preview-caption mt-4 text-center text-caps-sm text-(--landing-accent)">
                {gettext("See all")}
              </p>
            </div>
          </div>
        <% :time -> %>
          <div class="landing-preview-head mb-1 flex items-center justify-between gap-2 rounded-md bg-[#eadcd4] px-3 py-2 font-semibold [&_span:last-child]:rounded-sm [&_span:last-child]:bg-white [&_span:last-child]:px-2 [&_span:last-child]:py-0.5 [&_span:last-child]:text-caps-sm">
            <span>{gettext("Today's sessions")}</span>
            <span>00:51</span>
          </div>
          <div
            :for={row <- sessions()}
            class="landing-preview-row flex flex-wrap items-center gap-1.5 rounded-lg bg-[#faf7f5] p-3 text-caps-sm [&_small]:text-caps-sm [&_small]:font-normal [&_small]:text-darkGrey [&+.landing-preview-row]:mt-1.5"
          >
            <span>{row.name}</span>
            <span class="ml-auto">{row.project}</span>
            <span>{row.duration}</span>
          </div>
          <p class="landing-preview-caption mt-4 text-center text-caps-sm text-(--landing-accent)">
            {gettext("Tuesday")} · {gettext("Wednesday")}
          </p>
          <div class="landing-preview-overlay absolute right-[6%] -bottom-4.5 left-[14%] flex flex-wrap items-center gap-2.5 rounded-xl border border-(--landing-line) bg-white p-4 text-caps-sm shadow-[0_0.75rem_1.75rem_rgb(0_0_0/12%)] [&_strong]:text-sm">
            <span class="bg-[#ddd] p-[1.2cqw] text-[1.5cqw]">{gettext("Equipment testing")}</span>
            <span class="flex justify-between bg-[#e6d7ce] p-[1.6cqw] text-[1.5cqw] text-(--landing-accent)">Qubiq
            <span aria-hidden="true">⌄</span></span>
            <span class="text-[1.5cqw]">◯ {gettext("Working from home")}</span>
            <strong>{gettext("16 hours 23 min")}</strong>
            <small>{gettext("in October")}</small>
            <span class="self-center rounded-sm bg-(--landing-accent) p-[1cqw_4cqw] text-[1.5cqw] text-white">{gettext(
              "Start"
            )}</span>
          </div>
        <% :team -> %>
          <div class="landing-preview-head mb-1 flex items-center justify-between gap-2 rounded-md bg-[#eadcd4] px-3 py-2 font-semibold [&_span:last-child]:rounded-sm [&_span:last-child]:bg-white [&_span:last-child]:px-2 [&_span:last-child]:py-0.5 [&_span:last-child]:text-caps-sm">
            <span>{gettext("Leave requests to approve")}</span>
          </div>
          <div class="landing-preview-pending landing-preview-row flex flex-wrap items-center gap-1.5 rounded-lg bg-[#faf7f5] p-3 text-caps-sm [&_>_span:last-child]:rounded-full [&_>_span:last-child]:bg-turquoise-100 [&_>_span:last-child]:p-[1cqw_3cqw] [&_>_span:last-child]:text-[1.5cqw] [&_>_span:last-child]:text-turquoise-700 [&_small]:text-caps-sm [&_small]:font-normal [&_small]:text-darkGrey [&+.landing-preview-row]:mt-1.5">
            <span>☼ {gettext("Annual leave")}</span><small>02–06.11.2026</small><span>{gettext(
              "Pending"
            )}</span>
          </div>
          <p class="landing-preview-caption mt-4 text-center text-caps-sm text-(--landing-accent)">
            {gettext("Used this year:")} 11 · {gettext("Available:")} 15
          </p>
          <div
            :for={row <- leave_requests()}
            class="landing-preview-row flex flex-wrap items-center gap-1.5 rounded-lg bg-[#faf7f5] p-3 text-caps-sm [&_small]:text-caps-sm [&_small]:font-normal [&_small]:text-darkGrey [&+.landing-preview-row]:mt-1.5"
          >
            <span>{row.name}</span>
            <span class="ml-auto">{row.date}</span>
            <span class={[
              "landing-preview-status ml-auto rounded-sm border border-(--landing-line) bg-white px-2 py-0.75 text-[0.5rem] uppercase lg:text-caps-sm",
              row.approved &&
                "landing-preview-status--paid border-[#c6dcbf] [&.landing-preview-status--paid]:bg-[#dcecd8]"
            ]}>
              {row.status}
            </span>
          </div>
          <div class="landing-preview-overlay absolute right-[6%] -bottom-4.5 left-[14%] flex flex-wrap items-center gap-2.5 rounded-xl border border-(--landing-line) bg-white p-4 text-caps-sm shadow-[0_0.75rem_1.75rem_rgb(0_0_0/12%)] [&_strong]:text-sm">
            <span class="landing-preview-avatar grid size-8.5 place-content-center rounded-full text-xs font-bold text-white [background:var(--color-turquoise-400)]">KK</span>
            <span class="landing-preview-contact flex min-w-0 flex-1 flex-col items-start gap-[1cqw] [&_img]:size-[3cqw] [&_small]:flex [&_small]:items-center [&_small]:gap-[1cqw] [&_small]:text-[1.7cqw] [&_strong]:whitespace-nowrap [&.landing-preview-contact_strong]:text-[2.7cqw]">
              <strong>Katarzyna Kowalska</strong>
              <small><img src={~p"/images/slack.png"} width="16" height="16" alt="Slack" />{gettext(
                "Write on Slack"
              )}</small>
            </span>
          </div>
      <% end %>
    </div>
    """
  end

  defp contractor_invoices do
    [
      %{
        name: "SoftSystem sp. z o. o.",
        note: gettext("programming services"),
        status: gettext("Unmatched"),
        amount: "−90 000",
        tone: :warm,
        paid: false
      },
      %{
        name: "CyberSec Innovations sp. z o. o.",
        note: gettext("security audit"),
        status: gettext("Sending"),
        amount: "12 000",
        tone: :teal,
        paid: false
      },
      %{
        name: "WebCraft Masters sp. j.",
        note: gettext("website project"),
        status: gettext("Matched"),
        amount: "−15 750",
        tone: :warm,
        paid: true
      },
      %{
        name: "CodeWave Dynamics",
        note: gettext("software license"),
        status: gettext("Draft"),
        amount: "300",
        tone: :teal,
        paid: false
      },
      %{
        name: "CloudSync Systems",
        note: gettext("hosting services"),
        status: gettext("Unmatched"),
        amount: "−15 750",
        tone: :warm,
        paid: false
      },
      %{
        name: "DataShield Security",
        note: gettext("data protection"),
        status: gettext("Matched"),
        amount: "+5 200",
        tone: :warm,
        paid: true
      }
    ]
  end

  defp unmatched_transactions do
    [
      %{name: "Freshbus Sp. z o.o.", date: "05.10.2026", amount: "+ 2 304,50"},
      %{name: "Tech Innovations Ltd.", date: "07.10.2026", amount: "− 1 500,00"},
      %{name: "GreenTech Innovations", date: "08.10.2026", amount: "+ 5 500,00"},
      %{name: "Freshbus Sp. z o.o.", date: "09.10.2026", amount: "− 2 304,50"},
      %{name: "Tech Innovations Ltd.", date: "09.10.2026", amount: "− 1 500,00"},
      %{name: "Green Solutions Inc.", date: "12.10.2026", amount: "− 3 875,00"}
    ]
  end

  defp matched_transactions do
    [
      %{
        name: "Freshbus Sp. z o.o.",
        reference: "FV/2026/10/43",
        amount: "2 304,50",
        confidence: 100
      },
      %{
        name: "TechCorp Ltd.",
        reference: "INV/2026/10/56",
        amount: "1 850,00",
        confidence: 100
      },
      %{
        name: "Green Energy Co.",
        reference: "BILL/2026/09/98",
        amount: "3 500,00",
        confidence: 80
      },
      %{
        name: "Innovate Solutions Inc.",
        reference: "RCPT/2026/10/77",
        amount: "1 200,75",
        confidence: 100
      }
    ]
  end

  defp sessions do
    [
      %{name: gettext("Database maintenance"), project: "CODEXA", duration: "00:51"},
      %{name: gettext("Database maintenance"), project: "CODEXA", duration: "00:51"},
      %{name: gettext("Equipment testing"), project: "QUBIQ", duration: "01:42"},
      %{name: gettext("Database maintenance"), project: "CODEXA", duration: "00:51"}
    ]
  end

  defp leave_requests do
    [
      %{
        name: gettext("Annual leave"),
        date: "15.07 - 24.07.2026",
        status: gettext("Approved"),
        approved: true
      },
      %{
        name: gettext("Unpaid leave"),
        date: "10.04.2026",
        status: gettext("Approved"),
        approved: true
      },
      %{
        name: gettext("Medical leave"),
        date: "16.02 - 19.02.2026",
        status: gettext("Rejected"),
        approved: false
      },
      %{
        name: gettext("Annual leave"),
        date: "02.01.2026",
        status: gettext("Approved"),
        approved: true
      }
    ]
  end

  @doc """
  Renders the assistant early-access offer with an illustrative conversation.
  """
  @spec assistants_section(map()) :: Rendered.t()
  def assistants_section(assigns) do
    ~H"""
    <section id="asystent" class="bg-turquoise-200 py-18 lg:py-26">
      <div class="mx-auto grid w-[calc(100%-var(--spacing)*8)] max-w-284.75 grid-cols-1 gap-10 *:min-w-0 lg:w-[calc(100%-var(--spacing)*16)] lg:grid-cols-[minmax(0,1fr)_--spacing(125)] lg:gap-20 [&_.landing-eyebrow]:text-turquoise-700 [&_.landing-pill]:border-0 [&_.landing-pill]:bg-turquoise-700 [&_.landing-pill]:px-2.25 [&_.landing-pill]:py-0.75 [&_.landing-pill]:text-caps-sm [&_.landing-pill]:tracking-normal [&_.landing-pill]:text-white lg:[&_.landing-section-intro_h2]:max-w-130 lg:[&_.landing-section-intro.landing-section-intro_>_p]:max-w-none">
        <div class="landing-section-intro max-w-180 lg:max-w-284.75 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:mt-6 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-h5/6.75 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-darkGrey lg:[&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:max-w-115 [&_h2]:text-[2.25rem] [&_h2]:leading-[1.1] [&_h2]:font-bold [&_h2]:tracking-[-0.03em] lg:[&_h2]:text-[3rem] lg:[&_h2]:leading-[1.04] lg:[&.text-center]:mx-auto lg:[&.text-center]:max-w-140 lg:[&.text-center_>_p:not(.landing-eyebrow)]:mx-auto">
          <p class="landing-eyebrow mb-4 flex flex-wrap items-center gap-3 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
            {gettext("Firmowid in ChatGPT and Claude")}
            <span class="landing-pill inline-flex items-center rounded-full border border-current px-3.5 py-1.25 text-caps-sm font-bold tracking-[0.04em] uppercase">{gettext(
              "Early access"
            )}</span>
          </p>
          <h2>{gettext("An assistant to help you with your business")}</h2>
          <p>
            {gettext(
              "Write what you need - Firmowid will issue an invoice, create a correction or find any document. Before anything reaches KSeF, you will see a preview and confirm it yourself."
            )}
          </p>

          <ul class="mt-8 grid gap-4 text-base/normal [&_li]:flex [&_li]:items-baseline [&_li]:gap-2.5 [&_li]:text-[#4e4e4e]">
            <li>
              <img
                src={~p"/images/landing/icons/check.svg"}
                alt=""
                width="12"
                height="13"
                class="shrink-0"
              />{gettext("Issuing invoices - with a preview and KSeF submission")}
            </li>
            <li>
              <img
                src={~p"/images/landing/icons/check.svg"}
                alt=""
                width="12"
                height="13"
                class="shrink-0"
              />{gettext("Corrections, e.g. “give a 10% discount on invoice BC/01/10/2026”")}
            </li>
            <li>
              <img
                src={~p"/images/landing/icons/check.svg"}
                alt=""
                width="12"
                height="13"
                class="shrink-0"
              />{gettext("Reading sales and cost invoices")}
            </li>
          </ul>
          <p class="landing-assistants-soon mt-6 flex items-start gap-2.5 text-base/normal">
            <img
              src={~p"/images/landing/icons/clock.svg"}
              alt=""
              width="14"
              height="21"
              class="shrink-0"
            />{gettext(
              "Coming soon: financial analysis - invoices and real bank transactions in one place"
            )}
          </p>

          <div class="mt-10 flex items-center gap-2 lg:mt-16 [&>img]:h-12.5 [&>img]:w-8.5 [&>img]:object-contain">
            <img
              src={~p"/images/landing/character-head.png"}
              alt=""
              width="70"
              height="103"
              loading="lazy"
            />
            <div aria-hidden="true" class="relative h-40 min-w-0 flex-1">
              <img
                src={~p"/images/landing/decorations/assistant-top.svg"}
                alt=""
                width="249"
                height="62"
                class="absolute right-0 bottom-1/2 h-15.5 w-full"
              />
              <img
                src={~p"/images/landing/decorations/assistant-middle.svg"}
                alt=""
                width="251"
                height="1"
                class="absolute top-1/2 h-px w-full"
              />
              <img
                src={~p"/images/landing/decorations/assistant-bottom.svg"}
                alt=""
                width="248"
                height="63"
                class="absolute top-1/2 right-0 h-15.75 w-full"
              />
            </div>
            <ul class="grid shrink-0 grow-0 basis-40 gap-7 text-sm leading-[1.3] [&_img]:size-9.5 [&_li]:flex [&_li]:items-center [&_li]:gap-2 [&_li:nth-child(2)_img]:filter-[invert(61%)_sepia(65%)_saturate(555%)_hue-rotate(332deg)_brightness(90%)] [&_small]:block [&_small]:text-darkGrey [&_strong]:font-bold">
              <li>
                <img src={~p"/images/landing/chatgpt.svg"} width="38" height="38" alt="" /><span><strong>ChatGPT</strong><small>{gettext(
                  "app"
                )}</small></span>
              </li>
              <li>
                <img src={~p"/images/landing/claude.svg"} width="38" height="38" alt="" /><span><strong>Claude</strong><small>{gettext(
                  "connector"
                )}</small></span>
              </li>
              <li>
                <img src={~p"/images/landing/mcp.svg"} width="38" height="38" alt="" /><span>{gettext(
                  "Any MCP-compatible tool"
                )}</span>
              </li>
            </ul>
          </div>

          <p class="landing-assistants-footnote mt-14 text-sm/5 text-grey-500">
            {gettext(
              "*Already used by early adopters among our users. Gradually rolling out to everyone. Available in the Entrepreneur and Company plans."
            )}
          </p>
        </div>

        <div
          class="self-center rounded-2xl bg-white p-6 text-sm leading-[1.55] shadow-[0_1.125rem_2.75rem_rgb(47_67_67/10%)] lg:rounded-3xl lg:p-5.5"
          role="img"
          aria-label={gettext("Example conversation and invoice confirmation preview")}
        >
          <p class="ml-10 rounded-2xl rounded-br-none bg-[#dde4e4] px-4.5 py-3.5">
            {gettext("Issue an invoice for Północny Kod: 120 h at PLN 180 net.")}
          </p>
          <p class="mt-5 text-xs text-darkGrey">
            {gettext("Using the Firmowid app")}
          </p>
          <p class="mt-2">
            {gettext(
              "I prepared the invoice for Północny Kod sp. z o.o. for PLN 26,568.00 gross. Check the preview and confirm - only then does it reach KSeF."
            )}
          </p>

          <div class="mt-4 rounded-xl border border-(--landing-line) bg-[#f5f5f5] p-5 [&_.landing-button]:mx-auto [&_.landing-button]:mt-4 [&_.landing-button]:flex [&_.landing-button]:min-h-9 [&_.landing-button]:w-max [&_.landing-button]:max-w-full [&_.landing-button]:bg-turquoise-700 [&_.landing-button]:px-3.5 [&_.landing-button]:py-2 [&_.landing-button]:text-sm [&_h3]:mb-4 [&_h3]:text-lg [&_h3]:font-semibold">
            <h3>{gettext("Confirm invoice")}</h3>
            <div class="bg-[#ddd] p-3.5">
              <div class="relative mx-auto aspect-210/297 w-[74%] bg-white px-3 py-4.5 font-[Arial,sans-serif] text-[0.21875rem] leading-[1.6] shadow-[0_0.0625rem_0.25rem_#ccc] lg:px-5 lg:py-5.5 lg:text-[0.28125rem] [&_>_strong]:text-[0.3125rem] lg:[&_>_strong]:text-[0.375rem] [&_dl]:mt-2.5 [&_dl]:ml-auto [&_dl]:w-1/2 [&_dl_>_div]:flex [&_dl_>_div]:justify-between [&_dl_>_div:last-child]:mt-1.5 [&_dl_>_div:last-child]:font-bold">
                <strong>{gettext("VAT invoice %{number}", number: "01/10/2026")}</strong>
                <p>14.10.2026</p>
                <div class="mt-4.5 flex justify-between gap-2 border-t border-grey-200 pt-2.5 lg:mt-6 lg:pt-4">
                  <p>{gettext("Seller")}<br /><strong>Bytecraft Collective sp. z o.o.</strong></p><p>
                    {gettext("Buyer")}<br /><strong>Północny Kod sp. z o.o.</strong>
                  </p>
                </div>
                <div class="mt-4 flex justify-between border-y border-grey-200 py-2 lg:mt-6">
                  <span>{gettext("Programming services")}</span><span>{gettext("%{hours} h",
                    hours: 120
                  )}</span><span>{gettext("%{amount} PLN", amount: "180,00")}</span>
                </div>
                <dl>
                  <div>
                    <dt>{gettext("Net value")}</dt><dd>
                      {gettext("%{amount} PLN", amount: "21 600,00")}
                    </dd>
                  </div><div>
                    <dt>{gettext("VAT %{rate}%", rate: 23)}</dt><dd>
                      {gettext("%{amount} PLN", amount: "4 968,00")}
                    </dd>
                  </div><div>
                    <dt>{gettext("Total")}</dt><dd>
                      {gettext("%{amount} PLN", amount: "26 568,00")}
                    </dd>
                  </div>
                </dl>
                <p class="mt-4.5">
                  {gettext("Payment")}<br />14.11.2026
                </p>
                <p class="absolute bottom-3 font-bold">
                  Firmowid.pl
                </p>
              </div>
            </div>
            <span class="landing-button relative isolate inline-flex min-h-13 items-center justify-center gap-2.5 rounded-sm bg-[#0f0f0f] px-8 py-3.5 text-center text-base/6 font-medium text-white">{gettext(
              "Confirm and send to KSeF"
            )}</span>
            <p class="mt-4 text-xs text-darkGrey">
              {gettext("No document has been issued yet. Check the preview before confirming.")}
            </p>
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the customer quote with its supporting figures.
  """
  @spec proof_section(map()) :: Rendered.t()
  def proof_section(assigns) do
    ~H"""
    <section class="bg-white py-18 lg:py-26">
      <div class="mx-auto grid w-[calc(100%-var(--spacing)*8)] max-w-284.75 gap-10 lg:w-[calc(100%-var(--spacing)*16)] lg:grid-cols-[minmax(0,2.2fr)_minmax(0,1fr)] lg:items-center lg:gap-16 [&_blockquote]:relative [&_blockquote]:max-w-225 [&_blockquote]:pl-7 [&_blockquote]:text-2xl [&_blockquote]:leading-[1.35] [&_blockquote]:font-medium lg:[&_blockquote]:text-[2rem] [&_blockquote::after]:text-(--landing-accent) [&_blockquote::after]:content-['”'] [&_blockquote::before]:absolute [&_blockquote::before]:-top-4.5 [&_blockquote::before]:left-0 [&_blockquote::before]:text-[4rem] [&_blockquote::before]:leading-none [&_blockquote::before]:text-(--landing-accent) [&_blockquote::before]:content-['„']">
        <div>
          <blockquote>
            {gettext(
              "For two years, we patched together three different programs with Excel. Now one person does what three people used to do — and reports are ready at the end of the month, not a week later."
            )}
          </blockquote>
          <div class="mt-8 flex items-center gap-3.5">
            <span class="grid size-12 flex-none place-content-center rounded-full bg-[#8fa487] text-base font-bold text-white">EG</span>
            <div>
              <p class="text-base font-bold">
                {gettext("CEO of a television production company")}
              </p>
              <p class="mt-1 text-sm text-darkGrey">
                {gettext("beta program participant")}
              </p>
            </div>
          </div>
        </div>

        <div class="grid content-start gap-8 text-sm text-darkGrey lg:bg-[url('/images/landing/decorations/testimonial-separator.svg')] lg:bg-size-[--spacing(0.5)_--spacing(19.25)] lg:bg-left lg:bg-no-repeat lg:pl-16 [&_strong]:mb-1.5 [&_strong]:block [&_strong]:text-3xl [&_strong]:leading-[1.1] [&_strong]:font-bold [&_strong]:text-(--landing-accent)">
          <p>
            <strong>{gettext("%{hours} h", hours: "−12")}</strong>{gettext(
              "less administrative work per week"
            )}
          </p>
          <p><strong>0</strong>{gettext("KSeF errors since implementation")}</p>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the three onboarding steps.
  """
  @spec how_it_works_section(map()) :: Rendered.t()
  def how_it_works_section(assigns) do
    assigns = assign(assigns, :steps, localize(@steps, [:title, :description]))

    ~H"""
    <section id="jak-dziala" class="bg-grey-100 py-18 lg:py-26">
      <div class="mx-auto w-[calc(100%-var(--spacing)*8)] max-w-284.75 lg:w-[calc(100%-var(--spacing)*16)]">
        <div class="landing-section-intro mx-auto max-w-180 text-center lg:max-w-284.75 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:mt-6 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-h5/6.75 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-darkGrey lg:[&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:max-w-115 [&_h2]:text-[2.25rem] [&_h2]:leading-[1.1] [&_h2]:font-bold [&_h2]:tracking-[-0.03em] lg:[&_h2]:text-[3rem] lg:[&_h2]:leading-[1.04] lg:[&.text-center]:mx-auto lg:[&.text-center]:max-w-140 lg:[&.text-center_>_p:not(.landing-eyebrow)]:mx-auto">
          <p class="landing-eyebrow mb-4 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
            {gettext("How Firmowid works")}
          </p>
          <h2>{gettext("From zero to your first invoice in 15 minutes")}</h2>
        </div>

        <div class="relative mt-16 grid gap-10 lg:mt-20 lg:grid-cols-3 lg:gap-12 [&_article]:relative [&_article]:grid [&_article]:grid-cols-[--spacing(8)_minmax(0,1fr)] [&_article]:gap-x-5 [&_article]:gap-y-1 lg:[&_article]:block lg:[&_article]:text-center [&_article_>_p]:col-2 lg:[&_article_>_p]:col-auto [&_article_>_span]:row-[1/3] [&_article_>_span]:grid [&_article_>_span]:size-8 [&_article_>_span]:place-content-center [&_article_>_span]:rounded-full [&_article_>_span]:border-2 [&_article_>_span]:border-darkGrey [&_article_>_span]:bg-white [&_article_>_span]:text-sm [&_article_>_span]:font-bold lg:[&_article_>_span]:mx-auto lg:[&_article_>_span]:mb-6 lg:[&_article_>_span]:size-14 lg:[&_article_>_span]:text-xl [&_article:not(:last-child)::after]:absolute [&_article:not(:last-child)::after]:top-11 [&_article:not(:last-child)::after]:-bottom-10 [&_article:not(:last-child)::after]:left-3.75 [&_article:not(:last-child)::after]:border-l-2 [&_article:not(:last-child)::after]:border-dashed [&_article:not(:last-child)::after]:border-grey-200 [&_article:not(:last-child)::after]:content-[''] lg:[&_article:not(:last-child)::after]:top-6.75 lg:[&_article:not(:last-child)::after]:bottom-auto lg:[&_article:not(:last-child)::after]:left-1/2 lg:[&_article:not(:last-child)::after]:w-[calc(100%+var(--spacing)*12)] lg:[&_article:not(:last-child)::after]:border-t-2 lg:[&_article:not(:last-child)::after]:border-l-0 [&_article:nth-child(2)_>_span]:border-(--landing-accent) [&_article:nth-child(2)_>_span]:bg-(--landing-accent) [&_article:nth-child(2)_>_span]:text-white [&_h3]:mb-2 [&_h3]:text-lg [&_h3]:leading-[1.3] [&_h3]:font-semibold [&_h3]:tracking-[-0.01em] lg:[&_h3]:text-xl [&_p]:text-base [&_p]:leading-[1.4]">
          <article :for={{step, index} <- Enum.with_index(@steps, 1)} class="after:z-0">
            <span class="relative z-10">{index}</span>
            <h3>{step.title}</h3>
            <p>{step.description}</p>
          </article>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the self-hosting and open-source band.
  """
  @spec open_source_section(map()) :: Rendered.t()
  def open_source_section(assigns) do
    assigns = assign(assigns, :repository, @repository)

    ~H"""
    <section
      id="kod-zrodlowy"
      data-landing-dark-surface
      class="bg-[#0f0f0f] py-18 text-white lg:py-26 [&_.landing-eyebrow]:text-orange-500 [&_.landing-section-intro_>_p:not(.landing-eyebrow)]:text-grey-300 [&_article_p]:text-grey-300"
    >
      <div class="mx-auto grid w-[calc(100%-var(--spacing)*8)] max-w-284.75 gap-10 lg:w-[calc(100%-var(--spacing)*16)] lg:grid-cols-2 lg:gap-20 [&_article_p]:text-base [&_article_p]:leading-[1.4] [&_h3]:mb-5 [&_h3]:text-xl [&_h3]:leading-[1.3] [&_h3]:font-semibold [&_h3]:tracking-[-0.01em]">
        <div class="landing-section-intro max-w-180 lg:max-w-284.75 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:mt-6 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-h5/6.75 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-darkGrey lg:[&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:max-w-115 [&_h2]:text-[2.25rem] [&_h2]:leading-[1.1] [&_h2]:font-bold [&_h2]:tracking-[-0.03em] lg:[&_h2]:text-[3rem] lg:[&_h2]:leading-[1.04] lg:[&.text-center]:mx-auto lg:[&.text-center]:max-w-140 lg:[&.text-center_>_p:not(.landing-eyebrow)]:mx-auto">
          <p class="landing-eyebrow mb-4 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
            {gettext("Open source")}
          </p>
          <h2>{gettext("Your data on your server.")}</h2>
          <p>
            {gettext("Firmowid is open source. Host it yourself, without limits or fees.")}
          </p>
          <div class="mt-10 flex flex-wrap items-center gap-5">
            <.landing_button external={@repository} variant={:orange}>
              {gettext("View on GitHub")}
              <img src={~p"/images/github-mark.svg"} alt="" width="24" height="24" />
            </.landing_button>
            <a
              class="inline-flex min-h-7.75 min-w-36.5 items-center justify-center bg-[url('/images/landing/frames/license.svg')] bg-size-[100%_100%] bg-center bg-no-repeat px-3.5 py-1.25 text-caps-sm font-bold tracking-[0.04em]"
              href={@repository}
            >
              {gettext("AGPL-3.0 license")}
            </a>
          </div>
        </div>

        <div class="rounded-2xl border border-grey-800 bg-grey-900 px-7 py-2 lg:self-center [&_article]:py-6 [&_article_h3]:mb-2.5 [&_article+article]:border-t [&_article+article]:border-grey-800 [&_h3]:flex [&_h3]:items-center [&_h3]:gap-2.5 [&_h3]:text-[#f5f1ea] [&_h3::before]:h-3.25 [&_h3::before]:w-3 [&_h3::before]:flex-none [&_h3::before]:bg-orange-500 [&_h3::before]:mask-[url('/images/landing/icons/check.svg')] [&_h3::before]:mask-contain [&_h3::before]:mask-center [&_h3::before]:mask-no-repeat [&_h3::before]:content-['']">
          <article>
            <h3>{gettext("No limits")}</h3>
            <p>{gettext("Invoices, bank accounts and users without plan limits.")}</p>
          </article>
          <article>
            <h3>{gettext("No fees")}</h3>
            <p>{gettext("Install on your own server and pay no subscription.")}</p>
          </article>
          <article>
            <h3>{gettext("Full control")}</h3>
            <p>{gettext("The code is public, your data stays with you. AGPL-3.0 license.")}</p>
          </article>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the founders using the existing portraits and biography text.
  """
  @spec team_section(map()) :: Rendered.t()
  def team_section(assigns) do
    assigns = assign(assigns, :team, localize(@team, [:role, :bio]))

    ~H"""
    <section id="zespol" class="py-18 lg:py-26">
      <div class="mx-auto grid w-[calc(100%-var(--spacing)*8)] max-w-284.75 gap-10 lg:w-[calc(100%-var(--spacing)*16)] lg:grid-cols-[minmax(0,1fr)_--spacing(143)] lg:items-center lg:gap-7 lg:[&_.landing-section-intro.landing-section-intro_>_p]:max-w-none [&_h3]:mt-6 [&_h3]:mb-1.5 [&_h3]:text-lg [&_h3]:font-bold">
        <div class="landing-section-intro max-w-180 lg:max-w-284.75 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:mt-6 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-h5/6.75 [&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:text-darkGrey lg:[&_>_p:not(.landing-eyebrow,.landing-assistants-soon,.landing-assistants-footnote)]:max-w-115 [&_h2]:text-[2.25rem] [&_h2]:leading-[1.1] [&_h2]:font-bold [&_h2]:tracking-[-0.03em] lg:[&_h2]:text-[3rem] lg:[&_h2]:leading-[1.04] lg:[&.text-center]:mx-auto lg:[&.text-center]:max-w-140 lg:[&.text-center_>_p:not(.landing-eyebrow)]:mx-auto">
          <p class="landing-eyebrow mb-4 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
            {gettext("Who is behind it")}
          </p>
          <h2>{gettext("Two people. One office in Krakow.")}</h2>
          <p>
            {gettext(
              "Firmowid is not a product made by a hundred managers for a hundred processes. It is a tool made by people who run a company themselves and know what working with KSeF, payroll, and month-end closing really looks like."
            )}
          </p>
        </div>

        <div class="grid gap-5 md:grid-cols-2 lg:gap-4 [&_article]:rounded-2xl [&_article]:p-5 [&_article]:[background:#fff_url('/images/landing/frames/team-card.svg')_center/100%_100%_no-repeat] lg:[&_article]:p-6 [&_article:nth-child(2)_.landing-team-portrait]:bg-turquoise-600 [&_article:nth-child(2)_.landing-team-portrait_img]:top-[-12%] [&_article:nth-child(2)_.landing-team-portrait_img]:left-[-26%] [&_article:nth-child(2)_.landing-team-portrait_img]:w-[153%]">
          <article :for={person <- @team}>
            <div class="landing-team-portrait relative aspect-square overflow-hidden rounded-lg bg-orange-500 [&_img]:absolute [&_img]:top-[-22.4%] [&_img]:left-[-6%] [&_img]:h-auto [&_img]:w-[113%] [&_img]:max-w-none">
              <img
                src={person.image}
                alt={gettext("Portrait of %{name}", name: person.name)}
                width="832"
                height="1248"
                loading="lazy"
                decoding="async"
              />
            </div>
            <h3>{person.name}</h3>
            <p class="mb-5 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
              {person.role}
            </p>
            <p class="text-sm leading-[1.55] text-darkGrey">{person.bio}</p>
          </article>
        </div>
      </div>
    </section>
    """
  end

  defp localize(records, fields) do
    Enum.map(records, fn record ->
      Enum.reduce(fields, record, fn field, record ->
        Map.update!(record, field, &Gettext.gettext(Firmowid.Gettext, &1))
      end)
    end)
  end

  defp localize_features(features) do
    Enum.map(features, fn feature ->
      %{
        feature
        | tags: Enum.map(feature.tags, &Gettext.gettext(Firmowid.Gettext, &1)),
          title: Gettext.gettext(Firmowid.Gettext, feature.title),
          description: Gettext.gettext(Firmowid.Gettext, feature.description),
          bullets: Enum.map(feature.bullets, &Gettext.gettext(Firmowid.Gettext, &1))
      }
    end)
  end
end
