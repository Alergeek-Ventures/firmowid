defmodule FirmowidWeb.Landing.Components.Sections do
  @moduledoc """
  Main content sections for the public website.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.Landing.Components.Primitives, only: [landing_button: 1]

  alias FirmowidWeb.Landing.Utilities.Guides
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
      title: gettext_noop("Invoices that reach KSeF automatically"),
      description:
        gettext_noop(
          "You issue an invoice, and Firmowid sends it to KSeF and shows the KSeF number on it. It downloads cost invoices from KSeF every 2 hours."
        ),
      bullets: [
        gettext_noop("Unlimited sending to KSeF, including in the Free plan"),
        gettext_noop("Connection with a Trusted Profile, a KSeF certificate or a token"),
        gettext_noop("Bilingual invoices in foreign currencies"),
        gettext_noop("Corrections shown under the original invoice, with before and after tables")
      ],
      visual: :invoices,
      image: "/images/guides/funkcje/faktury-lista.webp",
      path: "/ksef"
    },
    %{
      tags: [gettext_noop("invoicing"), gettext_noop("bank accounts")],
      title: gettext_noop("Transactions matched to invoices"),
      description:
        gettext_noop(
          "Firmowid downloads transfers from your bank and matches them to invoices on its own. You check only the matches it is not sure about."
        ),
      bullets: [
        gettext_noop("29 banks and fintechs, including Revolut and Wise"),
        gettext_noop("Up to 90 days of history on the first connection"),
        gettext_noop("New transfers every other day"),
        gettext_noop("Read-only bank connection: Firmowid does not order transfers")
      ],
      visual: :banking,
      image: "/images/guides/pomoc/transakcja-sugestie.webp",
      page: "bank"
    },
    %{
      tags: [gettext_noop("cost invoices"), gettext_noop("accounting office")],
      title: gettext_noop("Cost invoices in one place, without retyping"),
      description:
        gettext_noop(
          "Invoices from KSeF arrive by themselves. You add paper ones with a photo and Firmowid reads the data. At the end of the month your accounting office gets one ZIP file."
        ),
      bullets: [
        gettext_noop("Cost invoices imported from KSeF automatically"),
        gettext_noop("Photo, scan or PDF with the data read for you"),
        gettext_noop("Internal comment on every document"),
        gettext_noop("Monthly ZIP package for your accounting office")
      ],
      visual: :costs,
      image: "/images/guides/funkcje/faktury-zakupowe.webp",
      page: "faktury-kosztowe"
    },
    %{
      tags: [gettext_noop("analysis"), gettext_noop("profitability")],
      title: gettext_noop("How much your company and each project really earn"),
      description:
        gettext_noop(
          "Income, expenses and net result month by month, also for each project. Firmowid counts only paid invoices, so the numbers match your bank account."
        ),
      bullets: [
        gettext_noop("Net result by month and by project"),
        gettext_noop("Expense categories suggested from the counterparty's PKD code"),
        gettext_noop("How much of every 100 PLN of income stayed"),
        gettext_noop("Unpaid invoices shown separately")
      ],
      visual: :analysis,
      image: "/images/guides/funkcje/analiza-podsumowanie.webp",
      page: "analiza"
    },
    %{
      tags: [gettext_noop("record-keeping"), gettext_noop("working hours")],
      title: gettext_noop("Hours that count themselves"),
      description:
        gettext_noop(
          "An employee starts the timer under a project or enters hours by hand. The hours go to the monthly timesheet and to the cost of the project."
        ),
      bullets: [
        gettext_noop("Start and stop timer that stops by itself after 12 hours"),
        gettext_noop("Hours assigned to a project and a person"),
        gettext_noop("Monthly timesheet signed with a Trusted Profile"),
        gettext_noop("Timesheet as a PDF and a payout report")
      ],
      visual: :time,
      image: "/images/guides/funkcje/czas-formularz.webp",
      page: "czas-pracy"
    },
    %{
      tags: [gettext_noop("HR"), gettext_noop("leave and business trips")],
      title: gettext_noop("Leave, business trips and team documents in one place."),
      description:
        gettext_noop(
          "An employee submits a leave request or settles a business trip in Firmowid, and you approve it in the Inbox. Employee contracts and documents are in the same program."
        ),
      bullets: [
        gettext_noop("Leave requests approved in the Inbox"),
        gettext_noop("Business trips: travel order, advance, domestic and foreign allowances"),
        gettext_noop("Employee contracts and documents"),
        gettext_noop("Four roles: employee, invoicing, accounting, admin")
      ],
      visual: :team,
      image: "/images/guides/funkcje/zespol.webp",
      page: "zespol"
    },
    %{
      tags: [gettext_noop("inbox"), gettext_noop("everyday work")],
      title: gettext_noop("Everything that needs your attention, on one list"),
      description:
        gettext_noop(
          "The inbox gathers what is waiting: KSeF or bank connection problems, team requests to approve and overdue invoices. Each employee sees only their own matters."
        ),
      bullets: [
        gettext_noop("Urgent matters first: KSeF, bank, company details"),
        gettext_noop("Leave requests, business trips and timesheet changes to approve"),
        gettext_noop("Overdue invoices without a matched payment"),
        gettext_noop("A separate list of their own tasks for every employee")
      ],
      visual: :inbox,
      image: "/images/guides/funkcje/skrzynka.webp",
      page: "skrzynka"
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
      image: "/images/team-franek-madej.webp",
      bio:
        gettext_noop(
          "For a decade, he has advised companies on software development, including startups from the Y Combinator ecosystem. He is obsessed with polished products and turning complex processes into simple tools."
        )
    },
    %{
      name: "Stanisław Madej",
      role: gettext_noop("COO · Alergeek Ventures"),
      image: "/images/team-stanislaw-madej.webp",
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
      class="bg-[#0f0f0f] py-18 text-white lg:pt-20 lg:pb-26"
    >
      <div class="mx-auto w-[calc(100%-var(--spacing)*8)] max-w-284.75 lg:w-[calc(100%-var(--spacing)*16)]">
        <div class="max-w-180 lg:max-w-170">
          <p class="mb-4 text-xs font-bold tracking-[0.08em] text-rust-500 uppercase lg:mb-1.5">
            {gettext("Who it is for")}
          </p>
          <h2 class="text-[38px] leading-[1.1] font-bold tracking-[-0.03em] lg:text-[48px] lg:leading-[50px] lg:tracking-[-1px]">
            {gettext("You run a business.")}<br />
            <span class="lg:whitespace-pre-line">{gettext("You do not want to manage spreadsheets.")}</span>
          </h2>
          <p class="mt-6 text-h5/6.75 text-grey-300 lg:mt-4 lg:max-w-156">
            {gettext(
              "Firmowid connects KSeF invoices, bank transfers and your team's hours, so you can see how much each project leaves."
            )}
          </p>
        </div>

        <div class="mt-10 grid gap-9 bg-[url('/images/landing/decorations/dark-separator.svg')] bg-size-[100%_--spacing(0.5)] bg-top bg-no-repeat pt-9 lg:mt-7.5 lg:grid-cols-3 lg:gap-x-[32.5px] lg:pt-8.5 [&_h3]:mb-5 [&_h3]:text-xl/[1.3] [&_h3]:font-semibold [&_h3]:tracking-[-0.01em] lg:[&_h3]:mb-3 lg:[&_h3]:text-[22px]/7">
          <article
            :for={{problem, index} <- Enum.with_index(@problems, 1)}
            class="lg:row-span-3 lg:grid lg:grid-rows-subgrid lg:gap-y-0"
          >
            <p class="mb-5 text-base/[1.4] font-bold tracking-[0.08em] text-rust-500 uppercase lg:mb-2.5 lg:text-xs">
              0{index}
            </p>
            <h3>{problem.title}</h3>
            <p class="text-base/[1.4] text-grey-300 lg:text-[15px]">{problem.description}</p>
          </article>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the product features with screenshots from the app.
  """
  attr :heading_tag, :string,
    default: "h2",
    values: ["h1", "h2"],
    doc: "the features page uses the section heading as its only page heading"

  @spec capabilities_section(map()) :: Rendered.t()
  def capabilities_section(assigns) do
    assigns =
      assign(assigns,
        features: localize_features(@features),
        link_label: Guides.feature_link_label()
      )

    ~H"""
    <section id="funkcje" class="py-18 lg:py-26">
      <div class="mx-auto w-[calc(100%-var(--spacing)*8)] max-w-284.75 lg:w-[calc(100%-var(--spacing)*16)]">
        <div class="max-w-180 lg:max-w-284.75">
          <p class="mb-4 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
            {gettext("What Firmowid can do")}
          </p>
          <.dynamic_tag
            tag_name={@heading_tag}
            class="text-[38px] leading-[1.1] font-bold tracking-[-0.03em] lg:max-w-279 lg:text-[48px] lg:leading-[50px] lg:tracking-[-1px]"
          >
            {gettext("Everything your business needs.")}<br class="hidden lg:block" />
            {gettext("In one place.")}
          </.dynamic_tag>
          <p class="mt-6 text-h5/6.75 text-grey-700 lg:hidden lg:max-w-115">
            {gettext(
              "Firmowid connects KSeF invoices, bank transfers and your team's hours, so you can see how much each project leaves."
            )}
          </p>
        </div>

        <article
          :for={feature <- @features}
          class="group relative mt-8 grid gap-6 rounded-2xl border border-[#e3b79b] bg-white p-6 lg:mt-16 lg:grid-cols-2 lg:items-center lg:gap-20 lg:border-0 lg:bg-transparent lg:p-0 lg:last:pb-0 lg:[&+article]:bg-[url('/images/landing/decorations/feature-separator.svg')] lg:[&+article]:bg-size-[100%_--spacing(0.5)] lg:[&+article]:bg-top lg:[&+article]:bg-no-repeat lg:[&+article]:pt-16 lg:[&:nth-of-type(even)_>_:first-child]:order-2"
        >
          <div class="font-normal">
            <p class="flex flex-wrap gap-2 text-xs font-bold tracking-[0.06em] text-(--landing-accent) uppercase lg:flex [&_span]:inline-block [&_span]:p-0 [&_span]:text-sm [&_span]:font-semibold [&_span]:tracking-[0.08em] [&_span]:uppercase max-lg:[&_span]:text-xs lg:[&_span]:rounded-full lg:[&_span]:bg-[#f2dfd4] lg:[&_span]:px-4 lg:[&_span]:py-1 lg:[&_span]:font-normal lg:[&_span]:tracking-normal lg:[&_span]:normal-case [&_span+span]:border-0 [&_span+span::before]:mr-2.5 [&_span+span::before]:content-['·'] lg:[&_span+span::before]:content-none">
              <span :for={tag <- feature.tags}>{tag}</span>
            </p>
            <h3 class={[
              "my-4 text-lg leading-[1.15] font-bold tracking-[-0.03em] text-grey-900 lg:text-[2.25rem] lg:leading-[1.05]",
              feature.visual == :banking && "lg:max-w-115",
              feature.visual == :team && "lg:max-w-100"
            ]}>
              <a
                href={feature_href(feature)}
                class={[
                  "after:absolute after:inset-0 after:rounded-2xl after:content-['']",
                  feature.visual == :team && "whitespace-pre-line"
                ]}
              >
                {feature.title}
              </a>
            </h3>
            <p class="text-base/6.75 text-grey-700 lg:text-h5">
              {feature.description}
            </p>
            <ul class="hidden text-grey-700 lg:mt-7 lg:grid lg:gap-3 lg:text-base/normal">
              <li :for={bullet <- feature.bullets} class="flex items-start gap-3">
                <img
                  src={~p"/images/landing/icons/arrow.svg"}
                  alt=""
                  width="24"
                  height="24"
                  class="shrink-0"
                />{bullet}
              </li>
            </ul>
            <p
              aria-hidden="true"
              class="mt-6 text-sm font-semibold text-(--landing-accent) transition-opacity lg:opacity-0 lg:group-focus-within:opacity-100 lg:group-hover:opacity-100"
            >
              {@link_label} →
            </p>
          </div>
          <img
            src={feature.image}
            alt={feature.title}
            width="1600"
            height={if feature.visual == :inbox, do: "1000", else: "1217"}
            loading="lazy"
            decoding="async"
            class="h-auto w-full min-w-0 rounded-2xl border border-(--landing-line) bg-grey-100 shadow-[0_0.875rem_2.125rem_rgb(80_50_30/8%)]"
          />
        </article>
      </div>
    </section>
    """
  end

  @doc """
  Renders the assistant offer with an illustrative conversation.
  """
  @spec assistants_section(map()) :: Rendered.t()
  def assistants_section(assigns) do
    ~H"""
    <section id="asystent" class="bg-teal-200 py-18 lg:py-26">
      <div class="mx-auto grid w-[calc(100%-var(--spacing)*8)] max-w-284.75 grid-cols-1 gap-10 *:min-w-0 lg:w-[calc(100%-var(--spacing)*16)] lg:grid-cols-[minmax(0,1fr)_--spacing(125)] lg:gap-20">
        <div class="max-w-180 lg:max-w-284.75">
          <p class="mb-4 flex flex-wrap items-center gap-3 text-xs font-bold tracking-[0.08em] text-teal-700 uppercase">
            {gettext("AI assistant in Firmowid, ChatGPT and Claude")}
          </p>
          <h2 class="max-w-125 text-[30px] leading-[1.15] font-bold tracking-normal text-grey-900 lg:text-[48px] lg:leading-[1.15]">
            {gettext("An AI assistant that prepares the invoice and finds its transfer")}
          </h2>
          <p class="mt-3.5 text-h5/6.75 text-grey-700">
            {gettext(
              "You write what you need, and the AI assistant prepares an invoice or a correction, or finds a document. Before anything reaches KSeF, you see a preview and confirm it yourself."
            )}
          </p>

          <ul class="mt-4 grid gap-3.5 text-base/6 text-grey-700 [&_li]:flex [&_li]:items-baseline [&_li]:gap-2.5">
            <li>
              <span
                class="h-3.25 w-3 shrink-0 bg-teal-700 mask-[url('/images/landing/icons/check.svg')] mask-contain mask-center mask-no-repeat"
                aria-hidden="true"
              ></span>{gettext("Issuing invoices with a preview and KSeF submission")}
            </li>
            <li>
              <span
                class="h-3.25 w-3 shrink-0 bg-teal-700 mask-[url('/images/landing/icons/check.svg')] mask-contain mask-center mask-no-repeat"
                aria-hidden="true"
              ></span>{gettext("Corrections, e.g. “give a 10% discount on invoice BC/01/10/2026”")}
            </li>
            <li>
              <span
                class="h-3.25 w-3 shrink-0 bg-teal-700 mask-[url('/images/landing/icons/check.svg')] mask-contain mask-center mask-no-repeat"
                aria-hidden="true"
              ></span>{gettext("Reading sales and cost invoices")}
            </li>
          </ul>
          <a
            href={~p"/funkcje/claude-chatgpt-mcp"}
            class="mt-6 inline-block text-sm font-semibold text-teal-700 underline underline-offset-4"
          >
            {Guides.feature_link_label()} →
          </a>

          <div class="mt-10 flex items-center gap-2 max-lg:mt-16 max-lg:justify-center lg:mt-14 lg:pl-4 max-lg:[&>div]:hidden [&>img]:h-12.5 [&>img]:w-8.5 [&>img]:shrink-0 [&>img]:object-contain max-lg:[&>img]:hidden">
            <img
              src={~p"/images/landing/character-head.png"}
              alt=""
              width="70"
              height="103"
              loading="lazy"
            />
            <div aria-hidden="true" class="relative h-45 min-w-0 flex-1 lg:w-60 lg:flex-none">
              <img
                src={~p"/images/landing/decorations/assistant-top.svg"}
                alt=""
                width="249"
                height="62"
                class="absolute right-0 bottom-[calc(50%+8px)] h-15.5 w-full object-fill"
              />
              <img
                src={~p"/images/landing/decorations/assistant-middle.svg"}
                alt=""
                width="251"
                height="1"
                class="absolute top-1/2 h-px w-full object-fill"
              />
              <img
                src={~p"/images/landing/decorations/assistant-bottom.svg"}
                alt=""
                width="248"
                height="63"
                class="absolute top-[calc(50%+8px)] right-0 h-15.75 w-full object-fill"
              />
            </div>
            <ul class="grid shrink-0 grow-0 basis-48 gap-7.5 text-sm/5 text-grey-700 max-lg:basis-60 max-lg:gap-12 lg:ml-3 [&_img]:size-10 [&_img]:shrink-0 max-lg:[&_img]:size-20 [&_li]:flex [&_li]:items-center [&_li]:gap-4 max-lg:[&_li]:justify-center max-lg:[&_li]:gap-8 max-lg:[&_li:nth-child(odd)]:flex-row-reverse max-lg:[&_li>span:first-child]:size-20 max-lg:[&_li>span:first-child]:shrink-0 [&_small]:block [&_small]:text-sm/5 [&_strong]:font-medium [&_strong]:text-grey-900">
              <li>
                <img src={~p"/images/landing/chatgpt.svg"} width="38" height="38" alt="" /><span><strong>ChatGPT</strong><small>{gettext(
                  "app"
                )}</small></span>
              </li>
              <li>
                <span
                  class="size-10 shrink-0 bg-[#d97757] mask-[url('/images/landing/claude.svg')] mask-contain mask-center mask-no-repeat"
                  aria-hidden="true"
                ></span><span><strong>Claude</strong><small>{gettext("connector")}</small></span>
              </li>
              <li>
                <img src={~p"/images/landing/mcp.svg"} width="38" height="38" alt="" /><span>{gettext(
                  "Any MCP-compatible tool"
                )}</span>
              </li>
            </ul>
          </div>
        </div>

        <div
          class="@container self-center rounded-[1.25rem] border border-teal-300 bg-white p-5.5 font-sans text-sm/snug text-grey-900 shadow-[0_1.125rem_2.75rem_rgb(47_67_67/10%)] max-lg:p-3.5 max-lg:[&_h3]:text-base max-lg:[&>div>p]:text-left max-lg:[&>div>p]:text-xs max-lg:[&>div>span]:text-sm max-lg:[&>p]:text-sm max-lg:[&>p:first-child]:w-[88%] max-lg:[&>p:first-child]:text-left max-lg:[&>p:nth-child(2)]:mt-5 max-lg:[&>p:nth-child(2)]:text-xs"
          role="img"
          aria-label={gettext("Example conversation and invoice confirmation preview")}
        >
          <p class="ml-auto w-[64%] rounded-2xl bg-grey-100 px-[3cqw] py-[2.2cqw] text-right text-[3.1cqw]">
            {gettext("Issue an invoice for Północny Kod: 120 h at PLN 180 net.")}
          </p>
          <p class="mt-[3.4cqw] flex items-center gap-[1.4cqw] text-[2.5cqw] text-grey-500">
            <img
              src={~p"/images/landing/character-head.png"}
              alt=""
              width="70"
              height="103"
              class="h-[3.5cqw] w-[2.5cqw] object-contain"
            />
            {gettext("Using the Firmowid app")}
          </p>
          <p class="mt-[2cqw] text-[3.1cqw]">
            {gettext(
              "I prepared the invoice for Północny Kod sp. z o.o. for PLN 26,568.00 gross. Check the preview and confirm. Only then does it reach KSeF."
            )}
          </p>

          <div class="mt-[1.8cqw] rounded-[3cqw] border border-grey-200 bg-grey-100 p-[3cqw]">
            <h3 class="mb-[2.5cqw] text-[3.5cqw] font-medium">{gettext("Confirm invoice")}</h3>
            <div class="bg-grey-200 p-[3cqw]">
              <div class="relative mx-auto aspect-210/297 w-[73%] bg-white px-[5cqw] py-[4.5cqw] text-[0.95cqw] leading-[1.6] shadow-[0_0.0625rem_0.25rem_#ccc]">
                <p class="text-[1.55cqw] font-semibold uppercase">
                  {gettext("VAT invoice %{number}", number: "01/10/2026")}
                </p>
                <p class="text-[0.85cqw]">{gettext("Issue date:")} <strong>14.10.2026</strong></p>
                <p class="text-[0.85cqw]">{gettext("Sale date:")} <strong>14.10.2026</strong></p>
                <div class="mt-[1.8cqw] grid grid-cols-2 gap-[2.5cqw] border-y border-grey-200 py-[2cqw]">
                  <div>
                    <p class="mb-[0.8cqw] text-[0.85cqw] font-semibold text-grey-600 uppercase">
                      {gettext("Seller")}
                    </p>
                    <p class="font-semibold">Biuro Cyfrowe sp. z o.o.</p>
                    <p>ul. Marszałkowska 11/4, 00-624 Warszawa</p>
                    <p>NIP: 6161525811</p>
                  </div>
                  <div>
                    <p class="mb-[0.8cqw] text-[0.85cqw] font-semibold text-grey-600 uppercase">
                      {gettext("Buyer")}
                    </p>
                    <p class="font-semibold">Północny Kod sp. z o.o.</p>
                    <p>ul. Wiertnicza 18B, 80-817 Gdańsk</p>
                    <p>NIP: 5842655890</p>
                  </div>
                </div>
                <p class="mt-[2cqw] mb-[1cqw] text-[0.85cqw] font-semibold text-grey-600 uppercase">
                  {gettext("Goods or services")}
                </p>
                <table class="w-full table-fixed text-left text-[0.95cqw] leading-[1.4]">
                  <thead class="text-[0.8cqw] text-grey-600">
                    <tr>
                      <th class="w-[43%] font-normal">{gettext("Name")}</th>
                      <th class="w-[8%] font-normal">{gettext("Quantity")}</th>
                      <th class="w-[14%] text-right font-normal">{gettext("Net price")}</th>
                      <th class="w-[7%] text-right font-normal">VAT</th>
                      <th class="w-[14%] text-right font-normal">{gettext("Net value")}</th>
                      <th class="w-[14%] text-right font-normal">{gettext("Gross value")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr>
                      <td class="pt-[0.6cqw] pr-[1cqw] align-top">
                        {gettext("Programming services")}
                      </td>
                      <td class="pt-[0.6cqw] align-top">120</td>
                      <td class="pt-[0.6cqw] text-right align-top">180,00</td>
                      <td class="pt-[0.6cqw] text-right align-top">23%</td>
                      <td class="pt-[0.6cqw] text-right align-top">21 600,00</td>
                      <td class="pt-[0.6cqw] text-right align-top">26 568,00</td>
                    </tr>
                  </tbody>
                </table>
                <div class="mt-[2cqw] ml-auto w-[45%] rounded-[0.8cqw] bg-grey-100 p-[1.5cqw] text-[0.8cqw]">
                  <p class="mb-[0.8cqw] font-semibold text-grey-600 uppercase">
                    {gettext("Summary")}
                  </p>
                  <dl class="grid gap-[0.6cqw] [&_>_div]:flex [&_>_div]:justify-between [&_>_div]:gap-[1cqw]">
                    <div>
                      <dt>{gettext("Net value")}</dt><dd>
                        {gettext("%{amount} PLN", amount: "21 600,00")}
                      </dd>
                    </div><div>
                      <dt>{gettext("VAT %{rate}%", rate: 23)}</dt><dd>
                        {gettext("%{amount} PLN", amount: "4 968,00")}
                      </dd>
                    </div><div class="font-bold">
                      <dt>{gettext("Total")}</dt><dd class="text-[1.1cqw]">
                        {gettext("%{amount} PLN", amount: "26 568,00")}
                      </dd>
                    </div>
                  </dl>
                </div>
                <p class="mt-[2cqw] border-t border-grey-200 pt-[2cqw] text-[0.85cqw] font-semibold text-grey-600 uppercase">
                  {gettext("Payment")}
                </p>
                <p>{gettext("Payment method:")} {gettext("Transfer")}</p>
                <p>{gettext("Payment due date:")} <strong>28.10.2026</strong></p>
                <p class="absolute bottom-[3.5cqw] left-[5cqw] flex items-end gap-[0.8cqw] text-[0.7cqw]">
                  <img
                    src={~p"/images/landing/character-head.png"}
                    alt=""
                    width="70"
                    height="103"
                    class="h-[2.5cqw] w-[1.5cqw] object-contain"
                  />
                  {gettext("Invoice generated with Firmowid")}
                </p>
              </div>
            </div>
            <span class="mx-auto mt-[2.8cqw] flex w-max max-w-full items-center justify-center rounded-[1.2cqw] bg-teal-700 px-[3cqw] py-[2cqw] text-center text-[3.1cqw] font-medium text-white">{gettext(
              "Confirm and send to KSeF"
            )}</span>
            <p class="mt-[3cqw] text-center text-[2.5cqw] text-grey-700">
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
    <section class="bg-white pt-23 pb-20 max-lg:py-12">
      <div class="mx-auto grid w-[calc(100%-var(--spacing)*8)] max-w-284.75 gap-10 lg:w-[calc(100%-var(--spacing)*16)] lg:grid-cols-[minmax(0,--spacing(179.5))_minmax(0,1fr)] lg:items-center lg:gap-16">
        <div>
          <blockquote class="relative max-w-full text-[22px]/7.5 font-medium tracking-[-0.01em] max-lg:pl-6.5 lg:w-179.5 lg:text-[2rem] lg:leading-[37px]">
            <p
              :for={
                sentence <-
                  String.split(
                    gettext(
                      "For two years, we patched together three different programs with Excel. Now one person does what three people used to do — and reports are ready at the end of the month, not a week later."
                    ),
                    ~r/(?<=\.)\s+(?=\p{Lu})/u
                  )
              }
              class="mt-4 first:mt-0 first:before:relative first:before:-top-1.5 first:before:text-[4rem] first:before:leading-0 first:before:text-(--landing-accent) first:before:content-['„'] last:after:relative last:after:top-6 last:after:inline-block last:after:w-0 last:after:text-[4rem] last:after:leading-0 last:after:text-(--landing-accent) last:after:content-['”'] max-lg:first:before:absolute max-lg:first:before:top-1 max-lg:first:before:left-0 lg:mt-0 lg:inline lg:first:mr-[0.25em]"
              phx-no-format
            >{sentence}</p>
          </blockquote>
          <div class="mt-8 flex items-center gap-3.5 max-lg:flex-row-reverse lg:mt-2.5 lg:gap-2.5">
            <span class="grid size-12 flex-none place-content-center rounded-full bg-[#8fa487] text-base font-bold text-white">EG</span>
            <div>
              <p class="text-[15px] font-bold lg:text-base">
                {gettext("CEO of a television production company")}
              </p>
              <p class="mt-1 text-[13px] text-grey-700 lg:text-sm">
                {gettext("beta program participant")}
              </p>
            </div>
          </div>
        </div>

        <div class="grid content-start gap-8 text-sm text-grey-700 max-lg:hidden lg:min-h-49.25 lg:bg-[url('/images/landing/decorations/testimonial-separator.svg')] lg:bg-size-[--spacing(0.5)_--spacing(49.25)] lg:bg-left lg:bg-no-repeat lg:pl-16 [&_strong]:mb-1.5 [&_strong]:block [&_strong]:text-3xl [&_strong]:leading-[1.1] [&_strong]:font-bold [&_strong]:text-(--landing-accent)">
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
        <div class="mx-auto max-w-180 text-center lg:max-w-140">
          <p class="mb-4 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
            {gettext("How Firmowid works")}
          </p>
          <h2 class="text-[38px] leading-[1.1] font-bold tracking-[-0.03em] lg:text-[48px] lg:leading-[50px] lg:tracking-[-1px]">
            {gettext("From zero to your first invoice in 15 minutes")}
          </h2>
        </div>

        <div class="relative mt-16 grid gap-10 lg:mt-20 lg:grid-cols-3 lg:gap-12 [&_article]:relative [&_article]:grid [&_article]:grid-cols-[--spacing(8)_minmax(0,1fr)] [&_article]:gap-x-5 [&_article]:gap-y-1 lg:[&_article]:block lg:[&_article]:text-center [&_article_>_p]:col-2 lg:[&_article_>_p]:col-auto [&_article_>_span]:row-[1/3] [&_article_>_span]:grid [&_article_>_span]:size-8 [&_article_>_span]:place-content-center [&_article_>_span]:rounded-full [&_article_>_span]:border-2 [&_article_>_span]:border-grey-700 [&_article_>_span]:bg-white [&_article_>_span]:text-sm [&_article_>_span]:font-bold lg:[&_article_>_span]:mx-auto lg:[&_article_>_span]:mb-6 lg:[&_article_>_span]:size-14 lg:[&_article_>_span]:text-xl [&_article:not(:last-child)::after]:absolute [&_article:not(:last-child)::after]:top-11 [&_article:not(:last-child)::after]:-bottom-10 [&_article:not(:last-child)::after]:left-3.75 [&_article:not(:last-child)::after]:border-l-2 [&_article:not(:last-child)::after]:border-dashed [&_article:not(:last-child)::after]:border-grey-200 [&_article:not(:last-child)::after]:content-[''] lg:[&_article:not(:last-child)::after]:top-6.75 lg:[&_article:not(:last-child)::after]:bottom-auto lg:[&_article:not(:last-child)::after]:left-1/2 lg:[&_article:not(:last-child)::after]:w-[calc(100%+var(--spacing)*12)] lg:[&_article:not(:last-child)::after]:border-t-2 lg:[&_article:not(:last-child)::after]:border-l-0 [&_article:nth-child(2)_>_span]:border-(--landing-accent) [&_article:nth-child(2)_>_span]:bg-(--landing-accent) [&_article:nth-child(2)_>_span]:text-white [&_h3]:mb-2 [&_h3]:text-lg/[1.3] [&_h3]:font-semibold [&_h3]:tracking-[-0.01em] lg:[&_h3]:text-xl [&_p]:text-[15px] [&_p]:leading-[1.4] [&_p]:text-grey-700">
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
  attr :standalone?, :boolean, default: false

  def open_source_section(assigns) do
    assigns = assign(assigns, :repository, @repository)

    ~H"""
    <section
      id="kod-zrodlowy"
      data-landing-dark-surface
      class="bg-[#0f0f0f] py-18 text-white lg:py-25 [&_article_p]:text-grey-300"
    >
      <div class="mx-auto grid w-[calc(100%-var(--spacing)*8)] max-w-284.75 gap-10 lg:w-[calc(100%-var(--spacing)*16)] lg:grid-cols-[minmax(0,1fr)_--spacing(110)] lg:gap-20 [&_article_:is(h2,h3)]:mb-5 [&_article_:is(h2,h3)]:text-xl/[1.3] [&_article_:is(h2,h3)]:font-semibold [&_article_:is(h2,h3)]:tracking-[-0.01em] lg:[&_article_:is(h2,h3)]:text-h5 [&_article_p]:text-base/[1.4] lg:[&_article_p]:text-[15px]/5.5">
        <div class="max-w-180 max-lg:relative lg:max-w-284.75 lg:self-center">
          <p class="mb-4 text-xs font-bold tracking-[0.08em] text-rust-500 uppercase lg:mb-4.5">
            {gettext("Open source")}
          </p>
          <.dynamic_tag
            tag_name={if @standalone?, do: "h1", else: "h2"}
            class="text-[32px] leading-[1.1] font-bold tracking-[-0.03em] max-lg:mt-10 lg:text-[48px] lg:leading-[54px] lg:tracking-normal"
          >
            <span class="whitespace-pre-line">{gettext("Your data on your server.")}</span>
          </.dynamic_tag>
          <p class="mt-6 text-h5/6.75 text-grey-300 lg:mt-5">
            {gettext("Firmowid is open source. Host it yourself, without limits or fees.")}
          </p>
          <div class="mt-10 flex flex-wrap items-center gap-5 max-lg:mt-5 lg:mt-5">
            <.landing_button
              external={@repository}
              variant={:rust}
              class="max-lg:w-full lg:min-h-14.25 lg:text-lg"
            >
              {gettext("View on GitHub")}
              <img src={~p"/images/github-mark.svg"} alt="" width="24" height="24" />
            </.landing_button>
            <a
              class="inline-flex min-h-7.75 min-w-36.5 items-center justify-center bg-[url('/images/landing/frames/license.svg')] bg-size-[100%_100%] bg-center bg-no-repeat px-3.5 py-1.25 text-sm font-bold max-lg:absolute max-lg:top-0 max-lg:right-0 max-lg:font-medium"
              href={@repository}
            >
              {gettext("AGPL-3.0 license")}
            </a>
          </div>
        </div>

        <div class="rounded-2xl border border-grey-800 bg-grey-900 px-7 py-2 lg:self-center lg:py-3 lg:pr-11.5 [&_:is(h2,h3)]:flex [&_:is(h2,h3)]:items-center [&_:is(h2,h3)]:gap-2.5 [&_:is(h2,h3)]:text-[#f5f1ea] [&_:is(h2,h3)::before]:h-3.25 [&_:is(h2,h3)::before]:w-3 [&_:is(h2,h3)::before]:flex-none [&_:is(h2,h3)::before]:bg-rust-500 [&_:is(h2,h3)::before]:mask-[url('/images/landing/icons/check.svg')] [&_:is(h2,h3)::before]:mask-contain [&_:is(h2,h3)::before]:mask-center [&_:is(h2,h3)::before]:mask-no-repeat [&_:is(h2,h3)::before]:content-[''] [&_article]:py-6 lg:[&_article]:py-4.5 [&_article_:is(h2,h3)]:mb-2.5 lg:[&_article_:is(h2,h3)]:mb-2 [&_article+article]:border-t [&_article+article]:border-grey-800">
          <article :for={{title, description} <- open_source_benefits()}>
            <.dynamic_tag tag_name={if @standalone?, do: "h2", else: "h3"}>
              {title}
            </.dynamic_tag>
            <p>{description}</p>
          </article>
        </div>
      </div>
    </section>
    """
  end

  defp open_source_benefits do
    [
      {gettext("No limits"), gettext("Invoices, bank accounts and users without plan limits.")},
      {gettext("No fees"), gettext("Install on your own server and pay no subscription.")},
      {gettext("Full control"), gettext("The code is public, your data stays with you. AGPL-3.0 license.")}
    ]
  end

  @doc """
  Renders the founders using the existing portraits and biography text.
  """
  @spec team_section(map()) :: Rendered.t()
  def team_section(assigns) do
    assigns = assign(assigns, :team, localize(@team, [:role, :bio]))

    ~H"""
    <section id="zespol" class="py-18 lg:py-26">
      <div class="mx-auto grid w-[calc(100%-var(--spacing)*8)] max-w-284.75 gap-10 lg:w-[calc(100%-var(--spacing)*16)] lg:grid-cols-[minmax(0,1fr)_--spacing(143)] lg:items-center lg:gap-7 [&_h3]:mt-6 [&_h3]:mb-1.5 [&_h3]:text-lg [&_h3]:font-bold">
        <div class="max-w-180 lg:max-w-284.75">
          <p class="mb-4 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase">
            {gettext("Who is behind it")}
          </p>
          <h2 class="text-[38px] leading-[1.1] font-bold tracking-[-0.03em] lg:text-[48px] lg:leading-[50px] lg:tracking-[-1px]">
            {gettext("Two people. One office in Krakow.")}
          </h2>
          <p class="mt-6 text-h5/6.75 text-grey-700">
            {gettext(
              "Firmowid is not a product made by a hundred managers for a hundred processes. It is a tool made by people who run a company themselves and know what working with KSeF, payroll, and month-end closing really looks like."
            )}
          </p>
        </div>

        <div class="grid gap-5 md:grid-cols-2 lg:gap-4 [&_article]:rounded-2xl [&_article]:bg-white [&_article]:p-5 lg:[&_article]:p-6">
          <article
            :for={{person, index} <- Enum.with_index(@team)}
            class="max-lg:grid max-lg:grid-cols-[88px_minmax(0,1fr)] max-lg:gap-x-4 max-lg:rounded-2xl max-lg:border max-lg:border-[#e3b79b] lg:relative lg:h-[557px] lg:w-[276px] lg:overflow-visible lg:after:pointer-events-none lg:after:absolute lg:after:top-1/2 lg:after:left-1/2 lg:after:z-10 lg:after:h-[559px] lg:after:w-[278px] lg:after:-translate-1/2 lg:after:bg-[url('/images/landing/frames/team-card.svg')] lg:after:bg-auto lg:after:bg-center lg:after:bg-no-repeat lg:after:content-[''] max-lg:[&>h3]:mt-0 max-lg:[&>h3]:self-end"
          >
            <div class={[
              "relative aspect-square overflow-hidden rounded-lg max-lg:row-span-2",
              if(index == 1, do: "bg-teal-600", else: "bg-rust-500")
            ]}>
              <img
                src={person.image}
                alt={gettext("Portrait of %{name}", name: person.name)}
                width="832"
                height="1248"
                loading="lazy"
                decoding="async"
                class={[
                  "absolute h-auto max-w-none",
                  if(index == 1,
                    do: "top-[-12%] left-[-26%] w-[153%]",
                    else: "top-[-22.4%] left-[-6%] w-[113%]"
                  )
                ]}
              />
            </div>
            <h3>{person.name}</h3>
            <p class="mb-5 text-xs font-bold tracking-[0.08em] text-(--landing-accent) uppercase max-lg:mb-0 max-lg:self-start">
              {person.role}
            </p>
            <div class="text-sm/[1.55] text-grey-700 max-lg:col-span-full max-lg:mt-5 lg:leading-[140%]">
              <p
                :for={paragraph <- String.split(person.bio, ~r/(?<=\.)\s+(?=\p{Lu})/u)}
                class="mt-2 first:mt-0"
              >
                {paragraph}
              </p>
            </div>
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

  # A feature links to its own page, or to the landing page that covers it.
  defp feature_href(%{path: path}), do: path
  defp feature_href(%{page: page}), do: ~p"/funkcje/#{page}"

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
