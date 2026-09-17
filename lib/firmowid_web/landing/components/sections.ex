defmodule FirmowidWeb.Landing.Components.Sections do
  @moduledoc """
  Main content sections for the public landing page.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Billing.PlanCatalog
  alias Phoenix.LiveView.Rendered

  @problems [
    %{
      number: "01",
      title: gettext_noop("Scattered tools"),
      description:
        gettext_noop(
          "One program for invoicing, another for time tracking, and yet another for bank reconciliation. Data does not match and reports are prepared manually."
        )
    },
    %{
      number: "02",
      title: gettext_noop("Uncertainty around KSeF"),
      description:
        gettext_noop(
          "Regulations change and deadlines move. Your current system may not keep up with updates, and penalties for mistakes are real."
        )
    },
    %{
      number: "03",
      title: gettext_noop("A budget that is outdated the day it is created"),
      description:
        gettext_noop(
          "Who worked how much? What fit within the project budget? By the time you prepare a summary, the week is over."
        )
    }
  ]

  @features [
    %{
      tags: [
        {gettext_noop("invoicing"), :default},
        {"KSeF", :default},
        {gettext_noop("new"), :accent}
      ],
      title: gettext_noop("Invoices that reach KSeF by themselves"),
      description:
        gettext_noop(
          "Create, send, receive. Firmowid connects to the National e-Invoice System and tracks every regulatory change for you."
        ),
      bullets: [
        gettext_noop("Automatic KSeF compliance validation"),
        gettext_noop("Retry sending when the government system is overloaded"),
        gettext_noop("Export invoices as PDF")
      ],
      variant: :invoice,
      reverse: false
    },
    %{
      tags: [{gettext_noop("invoicing"), :default}, {gettext_noop("bank accounts"), :default}],
      title: gettext_noop("Transactions matched to invoices"),
      description:
        gettext_noop(
          "Every transaction is automatically assigned to the right invoice. No more manually matching transfers at the end of the month."
        ),
      bullets: [
        gettext_noop("Automatic transaction matching to invoices"),
        gettext_noop("Integration with Polish and foreign banks"),
        gettext_noop("One-click export for accounting"),
        gettext_noop("Notifications about unpaid invoices"),
        gettext_noop("Flag transactions without documents")
      ],
      variant: :banking,
      reverse: true
    },
    %{
      tags: [
        {gettext_noop("record-keeping"), :default},
        {gettext_noop("working hours"), :default}
      ],
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
      variant: :time,
      reverse: false
    },
    %{
      tags: [{gettext_noop("payroll"), :default}, {gettext_noop("settlements"), :default}],
      title: gettext_noop("Payroll that never gets lost in Excel"),
      description:
        gettext_noop(
          "From working hours and rates, Firmowid calculates who earned what. Payroll and reports are in one place."
        ),
      bullets: [
        gettext_noop("Automatic payroll calculation based on tracked hours"),
        gettext_noop("Hourly rates and their change history"),
        gettext_noop("Information about the hours worked on an assignment"),
        gettext_noop("Payroll report in CSV format")
      ],
      variant: :payroll,
      reverse: true
    }
  ]

  @how_it_works [
    %{
      number: 1,
      title: gettext_noop("Create an account"),
      description: gettext_noop("Email, password, company name. No credit card. 30 days free.")
    },
    %{
      number: 2,
      title: gettext_noop("Integrate your data"),
      description:
        gettext_noop(
          "We will connect your bank account and KSeF. We will import contacts from a file or your previous system."
        )
    },
    %{
      number: 3,
      title: gettext_noop("Create your first invoice"),
      description:
        gettext_noop("Choose a contact, click “create”. Firmowid will handle the rest — including sending it to KSeF.")
    }
  ]

  @plan_marketing %{
    start: %{
      key: "start",
      name: "Start",
      audience: gettext_noop("Recommended for: everyone using KSeF"),
      features: [
        gettext_noop("KSeF integration"),
        gettext_noop("Clear invoice creator"),
        gettext_noop("Contacts database")
      ],
      highlighted: false
    },
    przedsiebiorca: %{
      key: "przedsiebiorca",
      name: gettext_noop("Entrepreneur"),
      audience: gettext_noop("Recommended for: sole traders and freelancers"),
      features: [
        gettext_noop("KSeF integration"),
        gettext_noop("Clear invoice creator"),
        gettext_noop("Contacts database"),
        gettext_noop("Email notifications")
      ],
      highlighted: true
    },
    firma: %{
      key: "firma",
      name: gettext_noop("Company"),
      audience: gettext_noop("Recommended for: teams and companies with more than 15 people"),
      features: [
        gettext_noop("KSeF integration"),
        gettext_noop("Clear invoice creator"),
        gettext_noop("Contacts database"),
        gettext_noop("Email notifications"),
        gettext_noop("Time recording"),
        gettext_noop("Employee and project management")
      ],
      highlighted: false
    }
  }

  @team [
    %{
      name: "Franek Madej",
      role: "CEO · Alergeek Ventures",
      portrait_alt: gettext_noop("Portrait of Franek Madej"),
      portrait_id: "team-portrait-franek",
      portrait_width: "832",
      portrait_height: "1248",
      bio:
        gettext_noop(
          "For a decade, he has advised companies on software development, including startups from the Y Combinator ecosystem. He is obsessed with polished products and turning complex processes into simple tools."
        )
    },
    %{
      name: "Stanisław Madej",
      role: "COO · Alergeek Ventures",
      portrait_alt: gettext_noop("Portrait of Stanisław Madej"),
      portrait_id: "team-portrait-stanislaw",
      portrait_width: "2731",
      portrait_height: "4096",
      bio:
        gettext_noop(
          "At Alergeek Ventures, he handles company logistics and manages a team of 20. A happy Firmowid user, he uses it for daily tasks, leaving more time for management and less for invoices and settlements."
        )
    }
  ]

  @faqs [
    %{
      id: "faq-ksef",
      question: gettext_noop("Is Firmowid compliant with KSeF?"),
      answer:
        gettext_noop(
          "Yes. Full KSeF compliance and automatic tracking of regulatory changes — our developers implement them immediately after announcements from the Ministry of Finance."
        )
    },
    %{
      id: "faq-migration",
      question: gettext_noop("How does migration from another program work?"),
      answer:
        gettext_noop(
          "Start by connecting KSeF and your bank — we import data from the last three months. You can immediately match transactions to invoices and analyze cash flow."
        )
    },
    %{
      id: "faq-security",
      question: gettext_noop("Is my data safe?"),
      answer:
        gettext_noop(
          "Yes. Firmowid emphasizes secure data storage, and the entire flow is designed for handling company financial data."
        )
    },
    %{
      id: "faq-cancel",
      question: gettext_noop("Can I cancel at any time?"),
      answer: gettext_noop("Yes. You can cancel at any time and delete your account without long-term commitments.")
    },
    %{
      id: "faq-overage",
      question: gettext_noop("How do extra charges for invoices outside KSeF and bank accounts work?"),
      answer:
        gettext_noop(
          "The Start plan does not include invoices outside KSeF, and each additional bank account costs PLN 10 net + VAT per month. Entrepreneur includes 20 invoices outside KSeF, 3 bank accounts, and 5 employees monthly; Company includes 100 invoices, 10 bank accounts, and 20 employees. After reaching the limit, charges follow the plan price list."
        )
    },
    %{
      id: "faq-banks",
      question: gettext_noop("Which banks do you support?"),
      answer:
        gettext_noop(
          "We support banks where Polish entrepreneurs can hold an account, including PKO BP, Pekao, mBank, ING, Alior Bank, Millennium, and Revolut."
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
      class="border-b border-[#363636] bg-[#0f0f0f] px-4 py-20 text-white sm:px-6 lg:px-10"
    >
      <div class="mx-auto max-w-[1419px] lg:px-[140px]">
        <div class="max-w-[680px]">
          <.section_eyebrow dark>{gettext("Who it is for")}</.section_eyebrow>
          <h2 class="mt-2 text-[38px] leading-[1.08] font-bold tracking-[-0.03em] text-[#fafafa] lg:text-[48px] lg:leading-[50px]">
            {gettext("You run a business.")} <br class="hidden lg:block" />
            {gettext("You do not want to manage spreadsheets.")}
          </h2>
          <p class="mt-4 text-[18px] leading-[27px] text-[#dddddd] lg:mt-4">
            {gettext("Firmowid was created for Polish SMEs that are tired of jumping from one program
              to another and recording everything in spreadsheets.")}
          </p>
        </div>

        <div class="mt-8 h-px w-full bg-[#3a3a3a] lg:mt-6" />

        <div class="mt-10 grid gap-8 lg:mt-8 lg:grid-cols-3 lg:gap-8">
          <article
            :for={problem <- @problems}
            class="grid max-w-[358px] grid-rows-[auto_minmax(56px,auto)_1fr] gap-y-3"
          >
            <p class="text-xs font-bold tracking-[0.08em] text-[#d2936d] uppercase">
              {problem.number}
            </p>
            <h3 class="text-[22px] leading-[1.2] font-semibold text-[#fafafa]">
              {problem.title}
            </h3>
            <p class="text-[15px] leading-[1.4] text-[#cccccc]">{problem.description}</p>
          </article>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the capabilities section.
  """
  @spec capabilities_section(map()) :: Rendered.t()
  def capabilities_section(assigns) do
    assigns = assign(assigns, :features, localize_features(@features))

    ~H"""
    <section id="funkcje" class="px-4 py-16 sm:px-6 lg:px-10 lg:py-20">
      <div class="mx-auto max-w-[1419px] lg:px-[140px]">
        <div class="max-w-[680px]">
          <.section_eyebrow>{gettext("What Firmowid can do")}</.section_eyebrow>
          <h2 class="mt-2 text-[38px] leading-[1.08] font-bold tracking-[-0.03em] text-[#0f0f0f] lg:text-[48px] lg:leading-[50px]">
            {gettext("Four things your business needs.")} <br class="hidden lg:block" />
            {gettext("In one place.")}
          </h2>
          <p class="mt-4 text-[18px] leading-[27px] text-[#4e4e4e] lg:hidden">
            {gettext("Firmowid was created for Polish SMEs that are tired of jumping from one program
              to another and recording everything in spreadsheets.")}
          </p>
        </div>

        <div class="mt-16">
          <div :for={{feature, index} <- Enum.with_index(@features)}>
            <.feature_row
              feature={feature}
              mobile_last={index == length(@features) - 1}
              desktop_last={index == length(@features) - 1}
            />
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the testimonial and how-it-works section.
  """
  @spec proof_and_how_it_works_section(map()) :: Rendered.t()
  def proof_and_how_it_works_section(assigns) do
    assigns = assign(assigns, :steps, localize(@how_it_works, [:title, :description]))

    ~H"""
    <section id="jak-dziala" class="bg-white">
      <div class="px-4 py-10 sm:px-6 lg:px-10 lg:py-20">
        <div class="mx-auto max-w-[1419px] lg:px-[140px]">
          <div class="flex flex-col gap-8 lg:flex-row lg:items-center lg:justify-between">
            <div class="max-w-[718px]">
              <blockquote class="relative ml-4 text-[23px]/8 font-medium tracking-[-0.01em] text-[#1a1a1a] lg:ml-0 lg:text-[32px] lg:leading-[1.15] lg:tracking-[-0.01em]">
                <span class="absolute top-0 -left-7 text-[56px] leading-[0.66] text-[#8b3f13] lg:-left-8 lg:text-[64px]">„</span>{gettext(
                  "For two years, we patched together three different programs with Excel. Now one person does what three people used to do — and reports are ready at the end of the month, not a week later."
                )}<span class="align-bottom text-[56px] leading-[0.66] text-[#8b3f13] lg:text-[64px]">”</span>
              </blockquote>

              <div class="mt-8 flex items-center gap-3">
                <div class="flex size-12 items-center justify-center rounded-full bg-[linear-gradient(135deg,#7a9471,#9ab892)] text-base font-bold text-white">
                  EG
                </div>
                <div>
                  <p class="text-[15px] font-semibold text-[#1a1a1a]">
                    {gettext("CEO of a television production company")}
                  </p>
                  <p class="mt-1 text-[13px] text-[#4e4e4e]">
                    {gettext("beta program participant")}
                  </p>
                </div>
              </div>
            </div>

            <div class="hidden lg:flex lg:w-[360px] lg:items-center lg:justify-between lg:gap-8">
              <div class="h-[197px] w-px bg-[#dedede]" />
              <div class="space-y-6">
                <div>
                  <p class="text-[42px] font-bold text-[#8b3f13]">−12h</p>
                  <p class="text-[13px] text-[#4e4e4e]">
                    {gettext("less administrative work per week")}
                  </p>
                </div>
                <div>
                  <p class="text-[42px] font-bold text-[#8b3f13]">0</p>
                  <p class="text-[13px] text-[#4e4e4e]">
                    {gettext("KSeF errors since implementation")}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-[#f5f5f5] px-4 py-16 sm:px-6 lg:px-10 lg:py-[104px]">
        <div class="mx-auto max-w-[1419px] lg:px-[100px]">
          <div class="mx-auto max-w-[680px] text-center">
            <.section_eyebrow>{gettext("How Firmowid works")}</.section_eyebrow>
            <h2 class="mt-2 text-[38px] leading-[1.08] font-bold tracking-[-0.03em] text-[#0f0f0f] lg:text-[48px] lg:leading-[50px]">
              {gettext("From zero to your first invoice in 15 minutes")}
            </h2>
          </div>

          <div class="relative mt-16 hidden grid-cols-3 items-start lg:grid">
            <div class="pointer-events-none absolute inset-x-[16.666667%] top-7 h-[3px] bg-[repeating-linear-gradient(to_right,#d3d3d3_0_8px,transparent_8px_16px)]" />
            <article
              :for={step <- @steps}
              class="relative z-10 mx-auto flex w-full max-w-[352px] flex-col items-center text-center"
            >
              <div class={[
                "flex size-14 items-center justify-center rounded-full border-2 text-[22px] font-bold",
                step.number == 2 && "border-[#8b3f13] bg-[#8b3f13] text-white",
                step.number != 2 && "border-[#4e4e4e] bg-white text-[#1a1a1a]"
              ]}>
                {step.number}
              </div>
              <h3 class="mt-5 text-[22px] leading-[33px] font-semibold text-[#1a1a1a]">
                {step.title}
              </h3>
              <p class="mt-3 text-[15px] leading-[1.4] text-[#4e4e4e]">{step.description}</p>
            </article>
          </div>

          <div class="relative mt-12 space-y-10 pl-7 lg:hidden">
            <div class="absolute top-4 left-[15px] h-[calc(100%-2rem)] w-px bg-[repeating-linear-gradient(to_bottom,#d3d3d3_0_8px,transparent_8px_16px)]" />
            <article :for={step <- @steps} class="relative flex gap-5">
              <div class={[
                "relative z-10 flex size-8 shrink-0 items-center justify-center rounded-full border-2 text-base font-bold",
                step.number == 2 && "border-[#8b3f13] bg-[#8b3f13] text-white",
                step.number != 2 && "border-[#4e4e4e] bg-white text-[#1a1a1a]"
              ]}>
                {step.number}
              </div>
              <div>
                <h3 class="text-[20px]/8 font-semibold text-[#1a1a1a]">{step.title}</h3>
                <p class="mt-2 text-[14px] leading-[1.4] text-[#4e4e4e]">{step.description}</p>
              </div>
            </article>
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the pricing section.
  """
  @spec pricing_section(map()) :: Rendered.t()
  attr :billing_period, :string, required: true

  def pricing_section(assigns) do
    assigns = assign(assigns, :plans, localize_plans(pricing_plans()))

    ~H"""
    <section id="cennik" class="bg-white px-4 py-16 sm:px-6 lg:px-10 lg:py-[100px]">
      <div class="mx-auto max-w-[1419px] lg:px-8 xl:px-[140px]">
        <div class="mx-auto max-w-[588px] text-center">
          <.section_eyebrow>{gettext("Pricing")}</.section_eyebrow>
          <h2 class="mt-2 text-[38px] leading-[1.08] font-bold tracking-[-0.03em] text-[#0f0f0f] lg:text-[48px] lg:leading-[50px]">
            {gettext("Fair pricing.")}<br /> <span class="underline">{gettext("No surprises.")}</span>
          </h2>
          <p class="mt-4 text-[18px] leading-[27px] text-[#4e4e4e]">
            {gettext(
              "Pay only for what you actually use. Choose the plan and billing cycle that suit you best."
            )}
          </p>
          <p class="mt-2 text-sm font-medium text-[#8b3f13]">
            {gettext("All prices are net + VAT.")}
          </p>
        </div>

        <div class="mt-10 hidden justify-center md:flex">
          <div class="inline-flex w-full max-w-[358px] rounded-2xl border-2 border-[#8b3f13] p-0">
            <button
              type="button"
              phx-click="set_billing_period"
              phx-value-period="monthly"
              class={[
                "flex flex-1 items-center justify-center rounded-l-[14px] px-6 py-3 text-sm font-medium",
                @billing_period == "monthly" && "bg-[#8b3f13] text-white",
                @billing_period != "monthly" && "bg-white text-[#1a1a1a]"
              ]}
              aria-pressed={@billing_period == "monthly"}
            >
              {pgettext("billing period", "Monthly")}
            </button>
            <button
              type="button"
              phx-click="set_billing_period"
              phx-value-period="yearly"
              class={[
                "flex flex-1 items-center justify-center gap-2 rounded-r-[14px] px-4 py-3 text-sm font-medium",
                @billing_period == "yearly" && "bg-[#8b3f13] text-white",
                @billing_period != "yearly" && "bg-white text-[#1a1a1a]"
              ]}
              aria-pressed={@billing_period == "yearly"}
            >
              {pgettext("billing period", "Yearly")}
              <span class={[
                "rounded-2xl px-2 py-1 text-xs font-medium",
                @billing_period == "yearly" && "bg-[#dea785] text-[#4e2005]",
                @billing_period != "yearly" && "bg-[#8b3f13] text-white"
              ]}>
                {pgettext("landing-billing-discount", "Save")}
              </span>
            </button>
          </div>
        </div>

        <div class="mt-8 grid gap-8 lg:mt-10 xl:grid-cols-3 xl:gap-8">
          <.pricing_card :for={plan <- @plans} plan={plan} billing_period={@billing_period} />
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders the team section.
  """
  @spec team_section(map()) :: Rendered.t()
  def team_section(assigns) do
    assigns = assign(assigns, :team, localize(@team, [:portrait_alt, :bio]))

    ~H"""
    <section
      id="zespol"
      class="border-t border-[#e9c3ac] px-4 py-16 sm:px-6 lg:border-t-0 lg:px-10 lg:py-[140px]"
    >
      <div class="mx-auto max-w-[1419px] lg:grid lg:grid-cols-[minmax(0,1fr)_572px] lg:items-center lg:gap-12 lg:px-[140px]">
        <div class="max-w-[543px] lg:max-w-none">
          <.section_eyebrow>{gettext("Who is behind it")}</.section_eyebrow>
          <h2 class="mt-2 text-[38px] leading-[1.08] font-bold tracking-[-0.03em] text-[#0f0f0f] lg:text-[48px] lg:leading-[50px]">
            {gettext("Two people. One office in Krakow.")}
          </h2>
          <p class="mt-4 text-[18px] leading-[27px] text-[#4e4e4e]">
            {gettext(
              "Firmowid is not a product made by a hundred managers for a hundred processes. It is a tool made by people who run a company themselves and know what working with KSeF, payroll, and month-end closing really looks like."
            )}
          </p>
        </div>

        <div class="mt-10 grid gap-4 lg:mt-0 lg:w-[572px] lg:grid-cols-2 lg:gap-4">
          <article
            :for={person <- @team}
            class="relative rounded-2xl bg-white p-5 after:pointer-events-none after:absolute after:inset-0 after:bg-[url('/images/founder_card_chalk_border.svg')] after:bg-size-[100%_100%] after:bg-no-repeat after:content-[''] lg:flex lg:w-[276px] lg:flex-col lg:gap-6 lg:p-6"
          >
            <div class="flex items-start gap-4 lg:block">
              <div class={[
                "relative size-[88px] shrink-0 overflow-hidden rounded-[8px] lg:size-[228px] lg:rounded-[8px]",
                person.name == "Franek Madej" && "bg-[#d2936d]",
                person.name != "Franek Madej" && "bg-[#578383]"
              ]}>
                <img
                  id={person.portrait_id}
                  src={portrait_src(person.name)}
                  alt={person.portrait_alt}
                  width={person.portrait_width}
                  height={person.portrait_height}
                  loading="lazy"
                  decoding="async"
                  data-image-reveal
                  phx-hook="ImageLoadReveal"
                  class={[
                    "pointer-events-none absolute max-w-none object-cover",
                    person.name == "Franek Madej" &&
                      "top-[-20px] left-[-3px] h-[148px] w-[99px] lg:top-[-51px] lg:left-[-14px] lg:h-[387px] lg:w-[258px]",
                    person.name != "Franek Madej" &&
                      "top-[-10px] left-[-24px] h-[202px] w-[135px] lg:top-[-27px] lg:left-[-60px] lg:h-[523px] lg:w-[349px]"
                  ]}
                />
              </div>

              <div class="min-w-0 lg:mt-6">
                <h3 class="text-[20px] font-bold text-[#1a1a1a] lg:text-[20px]">{person.name}</h3>
                <p class="mt-1 text-[13px] font-semibold tracking-[0.08em] text-[#8b3f13] uppercase">
                  {person.role}
                </p>
              </div>
            </div>

            <p class="mt-5 text-[14px] leading-[1.4] text-[#4e4e4e] lg:mt-0">{person.bio}</p>
          </article>
        </div>
      </div>
    </section>
    """
  end

  defp portrait_src("Franek Madej"), do: ~p"/images/team-franek-madej.png"

  defp portrait_src("Stanisław Madej"), do: ~p"/images/team-stanislaw-madej.png"

  @doc """
  Renders the FAQ section.
  """
  @spec faq_section(map()) :: Rendered.t()
  attr :open_faq, :string, default: nil

  def faq_section(assigns) do
    assigns = assign(assigns, :faqs, localize(@faqs, [:question, :answer]))

    ~H"""
    <section id="faq" class="border-t border-[#e6d7ce] px-4 py-16 sm:px-6 lg:px-10 lg:py-[140px]">
      <div class="mx-auto max-w-[1419px] lg:flex lg:items-start lg:gap-12 lg:px-[140px]">
        <div class="max-w-[460px] lg:flex-1">
          <.section_eyebrow>{gettext("Questions and answers")}</.section_eyebrow>
          <h2 class="mt-2 text-[38px] leading-[1.08] font-bold tracking-[-0.03em] text-[#0f0f0f] lg:text-[48px] lg:leading-[50px]">
            {gettext("Before you ask")} <br />{gettext("— we may have already answered.")}
          </h2>
          <p class="mt-4 text-[18px] leading-[27px] text-[#4e4e4e]">
            {gettext("Didn't find your question?")}
            <.link
              kind="unstyled"
              mailto="contact@alergeek.ventures"
              class="font-bold text-[#4e4e4e] underline underline-offset-4 hover:text-[#8b3f13]"
            >
              {gettext("Contact us.")}
            </.link>
          </p>
        </div>

        <div class="mt-8 w-full max-w-[571px] space-y-2 lg:mt-0">
          <div :for={faq <- @faqs} class="rounded-[8px] border-2 border-[#e6d7ce] bg-white">
            <button
              id={faq.id}
              type="button"
              phx-click="toggle_faq"
              phx-value-id={faq.id}
              class="flex w-full items-center justify-between gap-4 p-5 text-left"
              aria-expanded={@open_faq == faq.id}
              aria-controls={faq.id <> "-panel"}
            >
              <span class="text-[16px] leading-normal font-semibold text-[#1a1a1a] lg:text-[18px]">
                {faq.question}
              </span>
              <span class="text-[24px] leading-none text-[#8b3f13]">
                {if @open_faq == faq.id, do: "−", else: "+"}
              </span>
            </button>
            <div
              id={faq.id <> "-panel"}
              role="region"
              aria-labelledby={faq.id}
              hidden={@open_faq != faq.id}
              class="border-t border-[#f0dfd3] p-5 text-[15px] leading-normal text-[#4e4e4e]"
            >
              {faq.answer}
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc false
  attr :dark, :boolean, default: false
  slot :inner_block, required: true

  defp section_eyebrow(assigns) do
    ~H"""
    <p class={[
      "text-xs font-bold tracking-[0.08em] uppercase",
      @dark && "text-[#d2936d]",
      !@dark && "text-[#8b3f13]"
    ]}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc false
  attr :feature, :map, required: true
  attr :mobile_last, :boolean, default: false
  attr :desktop_last, :boolean, default: false

  defp feature_row(assigns) do
    ~H"""
    <div>
      <div class={[
        "py-4 lg:hidden",
        @mobile_last && "pb-16"
      ]}>
        <div class="rounded-[8px] border-2 border-[#dea785] bg-white p-6">
          <.feature_copy feature={@feature} compact />
          <.feature_preview variant={@feature.variant} class="mt-6" compact />
        </div>
      </div>

      <div class="hidden lg:block">
        <div class={[
          "grid grid-cols-2 items-end gap-8 py-0 xl:gap-20"
        ]}>
          <div class={["min-w-0", @feature.reverse && "order-2"]}>
            <.feature_copy feature={@feature} />
          </div>
          <div class={["min-w-0", @feature.reverse && "order-1"]}>
            <.feature_preview variant={@feature.variant} />
          </div>
        </div>
        <div :if={!@desktop_last} class="my-16 h-px w-full bg-[#ece1d8]" />
      </div>
    </div>
    """
  end

  @doc false
  attr :feature, :map, required: true
  attr :compact, :boolean, default: false

  defp feature_copy(assigns) do
    ~H"""
    <div>
      <div class="flex flex-wrap gap-2">
        <.feature_tag :for={{label, variant} <- @feature.tags} label={label} variant={variant} />
      </div>
      <h3 class={[
        "mt-4 font-bold tracking-[-0.03em] text-[#1a1a1a]",
        @compact && "text-[20px] leading-[1.1]",
        !@compact && "text-[36px] leading-[37px]"
      ]}>
        {@feature.title}
      </h3>
      <p class={[
        "mt-4 text-[#4e4e4e]",
        @compact && "text-base leading-[27px]",
        !@compact && "text-[18px] leading-[27px]"
      ]}>
        {@feature.description}
      </p>
      <ul :if={!@compact} class="mt-6 space-y-3">
        <li
          :for={bullet <- @feature.bullets}
          class="flex items-start gap-2 text-[16px] leading-normal text-[#4e4e4e]"
        >
          <span class="mt-0.5 text-[18px] leading-none font-bold text-[#699166]">✓</span>
          <span>{bullet}</span>
        </li>
      </ul>
    </div>
    """
  end

  @doc false
  attr :label, :string, required: true
  attr :variant, :atom, values: [:default, :accent], default: :default

  defp feature_tag(assigns) do
    ~H"""
    <span class={[
      "inline-flex rounded-2xl px-4 py-1 text-[14px] leading-[1.35]",
      @variant == :default && "bg-[rgba(234,170,132,0.3)] text-[#8b3f13]",
      @variant == :accent && "bg-[rgba(139,201,201,0.3)] text-[#455e5e]"
    ]}>
      {@label}
    </span>
    """
  end

  @doc false
  attr :variant, :atom, required: true
  attr :compact, :boolean, default: false
  attr :class, :string, default: nil

  defp feature_preview(assigns) do
    ~H"""
    <div class={[
      "rounded-[14px] border border-[#e5ddd0] bg-white shadow-[0_8px_32px_rgba(80,50,30,0.12)]",
      @class
    ]}>
      <%= case @variant do %>
        <% :invoice -> %>
          <.invoice_mockup compact={@compact} badge="KSeF ✓" />
        <% :banking -> %>
          <.banking_mockup compact={@compact} />
        <% :time -> %>
          <.time_mockup compact={@compact} />
        <% :payroll -> %>
          <.payroll_mockup compact={@compact} />
      <% end %>
    </div>
    """
  end

  @doc false
  attr :compact, :boolean, default: false
  attr :badge, :string, default: nil

  defp invoice_mockup(assigns) do
    ~H"""
    <div class={["relative", @compact && "p-[13px]", !@compact && "p-5"]}>
      <div
        :if={@badge}
        class={[
          "absolute rotate-[4deg] rounded-[6px] border-2 border-[#475e45] bg-[#e8efe5] font-bold tracking-[0.08em] text-[#475e45] uppercase",
          @compact && "top-3 right-3 px-2 py-1 text-[8px]",
          !@compact && "top-4 right-5 px-[10px] py-[4px] text-[10px]"
        ]}
      >
        {@badge}
      </div>
      <div class={[
        "border-b border-[#e5ddd0]",
        @compact && "pr-14 pb-[7px]",
        !@compact && "pr-20 pb-[11px]"
      ]}>
        <p class={[
          "font-bold text-[#1a1a1a]",
          @compact && "text-[9.5px] leading-[14px]",
          !@compact && "text-[14px] leading-[21px]"
        ]}>
          KOWALSKI CONSULTING
        </p>
        <div class={[
          "mt-0.5 flex items-center justify-between gap-4 text-[#4e4e4e]",
          @compact && "text-[6.8px] leading-[10px]",
          !@compact && "text-[10px] leading-[15px]"
        ]}>
          <p>{gettext("Invoice FV 10/2026")}</p>
          <p>01.10.2026</p>
        </div>
      </div>
      <div class={[
        "text-[#1a1a1a]",
        @compact && "pt-2 text-[7.5px] leading-[11px]",
        !@compact && "pt-3 text-[11px] leading-[16.5px]"
      ]}>
        <div class="flex items-start justify-between border-b border-dashed border-[#e5ddd0] py-[6px]">
          <span>{gettext("Consulting services (40h)")}</span><span>16 000,00</span>
        </div>
        <div class="flex items-start justify-between border-b border-dashed border-[#e5ddd0] py-[6px]">
          <span>{gettext("Software license")}</span><span>1 788,00</span>
        </div>
        <div class="flex items-start justify-between border-b border-dashed border-[#e5ddd0] py-[6px]">
          <span>VAT 23%</span><span>1 620,00</span>
        </div>
        <div class="flex items-start justify-between pt-[10px] font-bold">
          <span>{gettext("Total incl. tax")}</span><span>19 408,00 zł</span>
        </div>
      </div>
    </div>
    """
  end

  @doc false
  attr :compact, :boolean, default: false

  defp banking_mockup(assigns) do
    ~H"""
    <div class={[@compact && "p-[13px]", !@compact && "p-5"]}>
      <div class="rounded-[10px] border border-[#e5ddd0] bg-[#faf7f3] p-4">
        <div class="flex items-center justify-between border-b border-[#e9ddd2] pb-3">
          <div>
            <p class="text-sm font-bold text-[#1a1a1a]">{gettext("Linked payments")}</p>
            <p class="mt-1 text-[10px] text-[#4e4e4e]">
              {gettext("Automatically match invoices to transfers")}
            </p>
          </div>
          <span class="rounded-full bg-[#e8efe5] px-3 py-1 text-[10px] font-bold text-[#475e45]">
            Bank ✓
          </span>
        </div>
        <div class="mt-4 space-y-3">
          <div class="flex items-center justify-between rounded-lg bg-white p-3 shadow-[0_4px_16px_rgba(80,50,30,0.08)]">
            <div>
              <p class="text-xs font-semibold text-[#1a1a1a]">FV 10/2026</p>
              <p class="text-[11px] text-[#4e4e4e]">Kowalski Consulting</p>
            </div>
            <p class="text-sm font-bold text-[#1a1a1a]">19 408,00 zł</p>
          </div>
          <div class="flex items-center justify-between rounded-lg border border-dashed border-[#d8c7bb] p-3">
            <div>
              <p class="text-xs font-semibold text-[#1a1a1a]">mBank • 01.10.2026</p>
              <p class="text-[11px] text-[#4e4e4e]">{gettext("Transfer matched automatically")}</p>
            </div>
            <p class="text-sm font-bold text-[#699166]">✓</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc false
  attr :compact, :boolean, default: false

  defp time_mockup(assigns) do
    ~H"""
    <div class={[@compact && "p-[13px]", !@compact && "p-5"]}>
      <div class="rounded-[10px] border border-[#e5ddd0] bg-[#faf7f3] p-4">
        <div class="flex items-center justify-between border-b border-[#e9ddd2] pb-3">
          <div>
            <p class="text-sm font-bold text-[#1a1a1a]">
              {pgettext("landing-feature", "Time tracking")}
            </p>
            <p class="mt-1 text-[10px] text-[#4e4e4e]">{gettext("Costs and hours in real time")}</p>
          </div>
          <span class="rounded-full bg-[#f0eae6] px-3 py-1 text-[10px] font-bold text-[#8b3f13]">
            40h
          </span>
        </div>
        <div class="mt-4 space-y-3">
          <div class="flex items-center justify-between text-sm text-[#1a1a1a]">
            <span>Projekt A</span><strong>18h</strong>
          </div>
          <div class="h-2 rounded-full bg-[#ebe4dc]">
            <div class="h-2 w-[72%] rounded-full bg-[#8b3f13]"></div>
          </div>
          <div class="flex items-center justify-between text-sm text-[#1a1a1a]">
            <span>Projekt B</span><strong>12h</strong>
          </div>
          <div class="h-2 rounded-full bg-[#ebe4dc]">
            <div class="h-2 w-[48%] rounded-full bg-[#dea785]"></div>
          </div>
          <div class="flex items-center justify-between rounded-lg bg-white p-3 text-[11px] shadow-[0_4px_16px_rgba(80,50,30,0.08)]">
            <span>{gettext("Labor cost this week")}</span>
            <strong class="text-sm text-[#1a1a1a]">8 640 zł</strong>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc false
  attr :compact, :boolean, default: false

  defp payroll_mockup(assigns) do
    ~H"""
    <div class={[@compact && "p-[13px]", !@compact && "p-5"]}>
      <div class="rounded-[10px] border border-[#e5ddd0] bg-[#faf7f3] p-4">
        <div class="flex items-center justify-between border-b border-[#e9ddd2] pb-3">
          <div>
            <p class="text-sm font-bold text-[#1a1a1a]">{gettext("Team payroll")}</p>
            <p class="mt-1 text-[10px] text-[#4e4e4e]">
              {gettext("Hours and compensation in one place")}
            </p>
          </div>
          <span class="rounded-full bg-[#e8efe5] px-3 py-1 text-[10px] font-bold text-[#475e45]">
            {gettext("Ready")}
          </span>
        </div>
        <div class="mt-4 space-y-3">
          <div class="flex items-center justify-between rounded-lg bg-white p-3 shadow-[0_4px_16px_rgba(80,50,30,0.08)]">
            <div>
              <p class="text-xs font-semibold text-[#1a1a1a]">Jan Nowak</p>
              <p class="text-[11px] text-[#4e4e4e]">{gettext("160h • PLN 80/hour")}</p>
            </div>
            <p class="text-sm font-bold text-[#1a1a1a]">12 800 zł</p>
          </div>
          <div class="flex items-center justify-between rounded-lg border border-dashed border-[#d8c7bb] p-3 text-[11px] text-[#4e4e4e]">
            <span>{gettext("Payroll report ready")}</span>
            <strong class="text-[#8b3f13]">CSV</strong>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc false
  attr :plan, :map, required: true
  attr :billing_period, :string, required: true

  defp pricing_card(assigns) do
    price = display_price(assigns.plan, assigns.billing_period)

    assigns = assign(assigns, :price, price)

    ~H"""
    <article class={[
      "h-full min-w-0 rounded-2xl p-6 md:p-7 xl:p-8",
      @plan.highlighted && "bg-[#1a1a1a] text-white",
      !@plan.highlighted && "bg-[#f0eae6] text-[#1a1a1a]"
    ]}>
      <div class="flex h-full flex-col gap-8">
        <p class={[
          "text-xs font-bold tracking-[0.08em] uppercase",
          @plan.highlighted && "text-[#d2936d]",
          !@plan.highlighted && "text-[#8b3f13]"
        ]}>
          {@plan.name}
        </p>
        <p class={[
          "mt-2 text-[13px]",
          @plan.highlighted && "text-[#b5b5b5]",
          !@plan.highlighted && "text-[#4e4e4e]"
        ]}>
          {@plan.audience}
        </p>

        <div class="rounded-2xl">
          <p class={[
            "mt-3 text-[38px] leading-[1.1] font-bold sm:text-[44px] sm:leading-[1.15]",
            @plan.highlighted && "text-[#fafafa]",
            !@plan.highlighted && "text-[#1a1a1a]"
          ]}>
            <span
              id={"pricing-price-#{@plan.key}"}
              class="t-digit-group"
              data-value={@price}
              phx-hook="NumberPopIn"
              aria-hidden="true"
            >
              <span
                :for={{digit, index} <- Enum.with_index(price_graphemes(@price))}
                class="t-digit"
                data-stagger={index}
                style={"--digit-stagger-index: #{index};"}
              >
                {digit}
              </span>
            </span>
            <span class="sr-only">{@price}</span>
          </p>
          <p class={[
            "mt-2 text-sm/6",
            @plan.highlighted && "text-[#b5b5b5]",
            !@plan.highlighted && "text-[#5f5f5f]"
          ]}>
            {if @billing_period == "yearly",
              do: gettext("net + VAT / month when billed annually"),
              else: gettext("net + VAT / month")}
          </p>
          <p
            :if={@billing_period == "yearly"}
            class={[
              "mt-3 text-[15px]/6 font-normal",
              @plan.highlighted && "text-[#b5b5b5]",
              !@plan.highlighted && "text-[#5f5f5f]"
            ]}
          >
            {gettext("Paid upfront for one year:")}<br />
            <span class="line-through">
              {@plan.yearly_regular_price}
            </span>
            <span class={[
              "ml-1 font-bold no-underline",
              @plan.highlighted && "text-[#d2936d]",
              !@plan.highlighted && "text-[#8b3f13]"
            ]}>
              {@plan.yearly_price} netto + VAT
            </span>
          </p>
        </div>

        <div class="space-y-4">
          <div :if={@plan.included_usage != []}>
            <p class={[
              "text-[12px] font-semibold tracking-[0.08em] uppercase",
              @plan.highlighted && "text-[#d2936d]",
              !@plan.highlighted && "text-[#8b3f13]"
            ]}>
              {gettext("Included limits")}
            </p>
            <ul class="mt-3 space-y-2 text-[14px]/6">
              <li :for={usage <- @plan.included_usage} class="flex items-start gap-2">
                <span class={[
                  "mt-0.5 font-bold",
                  @plan.highlighted && "text-[#d2936d]",
                  !@plan.highlighted && "text-[#8b3f13]"
                ]}>
                  ✓
                </span>
                <span>{usage}</span>
              </li>
            </ul>
          </div>

          <div>
            <p class={[
              "text-[12px] font-semibold tracking-[0.08em] uppercase",
              @plan.highlighted && "text-[#d2936d]",
              !@plan.highlighted && "text-[#8b3f13]"
            ]}>
              {gettext("Available features")}
            </p>
            <ul class="mt-3 space-y-2 text-[14px]/6">
              <li :for={feature <- @plan.features} class="flex items-start gap-2">
                <span class={[
                  "mt-0.5 font-bold",
                  @plan.highlighted && "text-[#d2936d]",
                  !@plan.highlighted && "text-[#8b3f13]"
                ]}>
                  ✓
                </span>
                <span>{feature}</span>
              </li>
            </ul>
          </div>
        </div>

        <div class="mt-auto space-y-6 pt-2">
          <div class={[
            "inline-flex w-full rounded md:hidden",
            @plan.highlighted && "border-2 border-white",
            !@plan.highlighted && "border-2 border-[#8b3f13]"
          ]}>
            <button
              type="button"
              phx-click="set_billing_period"
              phx-value-period="monthly"
              class={[
                "flex flex-1 items-center justify-center rounded-l-[4px] px-5 py-2 text-xs font-medium",
                @plan.highlighted && @billing_period == "monthly" && "bg-white text-black",
                @plan.highlighted && @billing_period != "monthly" && "bg-transparent text-white",
                !@plan.highlighted && @billing_period == "monthly" && "bg-[#8b3f13] text-white",
                !@plan.highlighted && @billing_period != "monthly" && "bg-transparent text-[#1a1a1a]"
              ]}
              aria-pressed={@billing_period == "monthly"}
            >
              {pgettext("billing period", "Monthly")}
            </button>
            <button
              type="button"
              phx-click="set_billing_period"
              phx-value-period="yearly"
              class={[
                "flex flex-1 items-center justify-center gap-2 rounded-r-[4px] px-3 py-2 text-xs font-medium",
                @plan.highlighted && @billing_period == "yearly" && "bg-white text-black",
                @plan.highlighted && @billing_period != "yearly" && "bg-transparent text-white",
                !@plan.highlighted && @billing_period == "yearly" && "bg-[#8b3f13] text-white",
                !@plan.highlighted && @billing_period != "yearly" && "bg-transparent text-[#1a1a1a]"
              ]}
              aria-pressed={@billing_period == "yearly"}
            >
              {pgettext("billing period", "Yearly")}
              <span class={[
                "rounded-2xl px-2 py-1 text-[10px]",
                @plan.highlighted && @billing_period == "yearly" && "bg-[#dea785] text-[#4e2005]",
                @plan.highlighted && @billing_period != "yearly" && "bg-[#dea785] text-[#4e2005]",
                !@plan.highlighted && @billing_period == "yearly" && "bg-white/20 text-white",
                !@plan.highlighted && @billing_period != "yearly" && "bg-[#8b3f13] text-white"
              ]}>
                {pgettext("landing-billing-discount", "Save")}
              </span>
            </button>
          </div>

          <.link
            kind="unstyled"
            navigate={~p"/zarejestruj"}
            data-landing-cta="pricing_register"
            data-landing-plan={@plan.key}
            data-landing-billing-period={@billing_period}
            class={[
              "relative flex min-h-[56px] w-full items-center justify-center overflow-hidden rounded-[4px] px-8 py-4 text-base font-medium transition-transform duration-150 hover:-translate-y-0.5",
              @plan.highlighted &&
                "border-2 border-[#d2936d] bg-[#d2936d] text-black hover:bg-[#dea785]",
              !@plan.highlighted &&
                "text-[#1a1a1a] before:absolute before:inset-0 before:bg-[url('/images/button_login.svg')] before:bg-size-[100%_100%] before:bg-no-repeat before:content-[''] hover:bg-black/3"
            ]}
          >
            <span class="relative z-10">{gettext("Start for free")}</span>
          </.link>
        </div>
      </div>
    </article>
    """
  end

  defp display_price(plan, "yearly") do
    plan.yearly_monthly_price
  end

  defp display_price(plan, _period) do
    plan.monthly_price
  end

  defp price_graphemes(price) do
    String.graphemes(price)
  end

  defp localize(records, fields) do
    Enum.map(records, fn record ->
      Enum.reduce(fields, record, fn field, record ->
        Map.update!(record, field, fn value ->
          Gettext.gettext(FirmowidWeb.Core.Gettext, value)
        end)
      end)
    end)
  end

  defp localize_features(features) do
    Enum.map(features, fn feature ->
      feature
      |> Map.update!(:tags, fn tags ->
        Enum.map(tags, fn {label, variant} ->
          {Gettext.gettext(FirmowidWeb.Core.Gettext, label), variant}
        end)
      end)
      |> Map.update!(:title, fn value -> Gettext.gettext(FirmowidWeb.Core.Gettext, value) end)
      |> Map.update!(:description, fn value ->
        Gettext.gettext(FirmowidWeb.Core.Gettext, value)
      end)
      |> Map.update!(:bullets, fn bullets ->
        Enum.map(bullets, fn value -> Gettext.gettext(FirmowidWeb.Core.Gettext, value) end)
      end)
    end)
  end

  defp localize_plans(plans) do
    Enum.map(plans, fn plan ->
      plan
      |> Map.update!(:name, fn value -> Gettext.gettext(FirmowidWeb.Core.Gettext, value) end)
      |> Map.update!(:audience, fn value -> Gettext.gettext(FirmowidWeb.Core.Gettext, value) end)
      |> Map.update!(:features, fn features ->
        Enum.map(features, fn value -> Gettext.gettext(FirmowidWeb.Core.Gettext, value) end)
      end)
    end)
  end

  defp pricing_plans do
    Enum.map([:start, :przedsiebiorca, :firma], fn plan ->
      rules = PlanCatalog.plan!(plan)

      @plan_marketing
      |> Map.fetch!(plan)
      |> Map.merge(%{
        monthly_price: money_with_currency(rules.monthly_price_pln),
        yearly_monthly_price: yearly_monthly_price(rules.yearly_price_pln),
        yearly_regular_price: yearly_regular_price(rules.monthly_price_pln),
        yearly_price: money_with_currency(rules.yearly_price_pln),
        included_usage: included_usage(rules)
      })
    end)
  end

  defp yearly_monthly_price(nil), do: nil

  defp yearly_monthly_price(yearly_price_pln) do
    yearly_price_pln
    |> Decimal.div(Decimal.new(12))
    |> Decimal.round(2)
    |> Decimal.normalize()
    |> money_with_currency()
  end

  defp yearly_regular_price(monthly_price_pln) do
    monthly_price_pln
    |> Decimal.mult(Decimal.new(12))
    |> money_with_currency()
  end

  defp included_usage(rules) do
    Enum.reject(
      [
        included_usage_line(
          rules.manual_external_invoices,
          :external_invoice
        ),
        included_usage_line(
          rules.synced_bank_accounts,
          :bank_account
        ),
        included_usage_line(
          rules.active_non_owner_users,
          :employee
        )
      ],
      &is_nil/1
    )
  end

  defp included_usage_line(%{included_units: 0}, _kind), do: nil

  defp included_usage_line(%{included_units: included_units}, :external_invoice) do
    "#{ngettext("%{count} invoice outside KSeF", "%{count} invoices outside KSeF", included_units)} #{pgettext("landing-pricing-short", "per month")}"
  end

  defp included_usage_line(%{included_units: included_units}, :bank_account) do
    "#{ngettext("%{count} bank account", "%{count} bank accounts", included_units)} #{pgettext("landing-pricing-short", "per month")}"
  end

  defp included_usage_line(%{included_units: included_units}, :employee) do
    "#{ngettext("%{count} employee", "%{count} employees", included_units)} #{pgettext("landing-pricing-short", "per month")}"
  end

  defp money_with_currency(nil), do: nil

  defp money_with_currency(value) do
    "#{Decimal.to_string(value, :normal)} zł"
  end
end
