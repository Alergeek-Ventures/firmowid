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
    <section id="dla-kogo" data-landing-dark-surface class="landing-dark landing-section">
      <div class="landing-container">
        <div class="landing-section__intro">
          <p class="landing-eyebrow">{gettext("Who it is for")}</p>
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

        <div class="landing-problems">
          <article :for={{problem, index} <- Enum.with_index(@problems, 1)}>
            <p class="landing-eyebrow">0{index}</p>
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
    <section id="funkcje" class="landing-section">
      <div class="landing-container">
        <div class="landing-section__intro">
          <p class="landing-eyebrow">{gettext("What Firmowid can do")}</p>
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

        <article :for={feature <- @features} class="landing-feature">
          <div>
            <p class="landing-feature__tags">
              <span :for={tag <- feature.tags}>{tag}</span>
            </p>
            <h3>{feature.title}</h3>
            <p class="landing-feature__description">{feature.description}</p>
            <ul>
              <li :for={bullet <- feature.bullets}>
                <span aria-hidden="true">→</span>{bullet}
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
        "landing-preview",
        @visual == :invoices && "landing-preview--invoices",
        @visual == :banking && "landing-preview--banking",
        @visual == :time && "landing-preview--time",
        @visual == :team && "landing-preview--team"
      ]}
      role="img"
      aria-label={gettext("Illustrative product preview")}
    >
      <%= case @visual do %>
        <% :invoices -> %>
          <div class="landing-preview__head">
            <span>{gettext("Counterparty")}</span>
            <span>{gettext("Status")}</span>
          </div>
          <div :for={row <- contractor_invoices()} class="landing-preview__row">
            <span class="landing-preview__contractor"><img
              src={~p"/images/ksef.png"}
              alt=""
              width="24"
              height="24"
            /><strong>{row.name}</strong> <small>{row.note}</small></span>
            <span class={["landing-preview__status", row.paid && "landing-preview__status--paid"]}>
              {row.status}
            </span>
            <span class={[
              "landing-preview__amount",
              row.tone == :teal && "landing-preview__amount--teal"
            ]}>
              {gettext("%{amount} PLN", amount: row.amount)}
            </span>
          </div>
        <% :banking -> %>
          <div class="landing-preview__bank-columns">
            <div>
              <div class="landing-preview__head">
                <span>{gettext("Transactions to match")}</span>
                <span>6</span>
              </div>
              <div :for={row <- unmatched_transactions()} class="landing-preview__row">
                <span>{row.name}</span>
                <strong class={[
                  "landing-preview__bank-amount",
                  String.starts_with?(row.amount, "+") && "landing-preview__bank-amount--credit"
                ]}>{pgettext("landing bank amount", "%{amount} PLN", amount: row.amount)}</strong>
                <small>{row.date}</small>
                <img
                  src={~p"/images/invoicing_badges/mbk_wa_1.svg"}
                  alt="mBank"
                  width="22"
                  height="12"
                />
              </div>
              <p class="landing-preview__caption">{gettext("See all")}</p>
            </div>
            <div>
              <div class="landing-preview__head landing-preview__head--matched">
                <span>{gettext("Matched")}</span>
                <span>36</span>
              </div>
              <div :for={row <- matched_transactions()} class="landing-preview__row">
                <span>{row.name} <small>{row.reference}</small></span>
                <strong>{pgettext("landing bank amount", "%{amount} PLN", amount: row.amount)}</strong>
                <span class="landing-preview__match">
                  {row.confidence}%
                  <progress value={row.confidence} max="100">{row.confidence}%</progress>
                </span>
              </div>
              <p class="landing-preview__caption">
                {gettext("See all")}
              </p>
            </div>
          </div>
        <% :time -> %>
          <div class="landing-preview__head">
            <span>{gettext("Today's sessions")}</span>
            <span>00:51</span>
          </div>
          <div :for={row <- sessions()} class="landing-preview__row">
            <span>{row.name}</span>
            <span class="ml-auto">{row.project}</span>
            <span>{row.duration}</span>
          </div>
          <p class="landing-preview__caption">
            {gettext("Tuesday")} · {gettext("Wednesday")}
          </p>
          <div class="landing-preview__overlay">
            <span class="landing-preview__timer-title">{gettext("Equipment testing")}</span>
            <span class="landing-preview__timer-project">Qubiq <span aria-hidden="true">⌄</span></span>
            <span class="landing-preview__timer-remote">◯ {gettext("Working from home")}</span>
            <strong>{gettext("16 hours 23 min")}</strong>
            <small>{gettext("in October")}</small>
            <span class="landing-preview__timer-start">{gettext("Start")}</span>
          </div>
        <% :team -> %>
          <div class="landing-preview__head">
            <span>{gettext("Leave requests to approve")}</span>
          </div>
          <div class="landing-preview__pending landing-preview__row">
            <span>☼ {gettext("Annual leave")}</span><small>02–06.11.2026</small><span>{gettext(
              "Pending"
            )}</span>
          </div>
          <p class="landing-preview__caption">
            {gettext("Used this year:")} 11 · {gettext("Available:")} 15
          </p>
          <div :for={row <- leave_requests()} class="landing-preview__row">
            <span>{row.name}</span>
            <span class="ml-auto">{row.date}</span>
            <span class={["landing-preview__status", row.approved && "landing-preview__status--paid"]}>
              {row.status}
            </span>
          </div>
          <div class="landing-preview__overlay">
            <span class="landing-preview__avatar">KK</span>
            <span class="landing-preview__contact">
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
    <section id="asystent" class="landing-section bg-turquoise-200">
      <div class="landing-assistants landing-container">
        <div class="landing-section__intro">
          <p class="landing-eyebrow landing-eyebrow--pill">
            {gettext("Firmowid in ChatGPT and Claude")}
            <span class="landing-pill">{gettext("Early access")}</span>
          </p>
          <h2>{gettext("An assistant to help you with your business")}</h2>
          <p>
            {gettext(
              "Write what you need - Firmowid will issue an invoice, create a correction or find any document. Before anything reaches KSeF, you will see a preview and confirm it yourself."
            )}
          </p>

          <ul class="landing-assistants__benefits">
            <li>
              <span aria-hidden="true">✓</span>{gettext(
                "Issuing invoices - with a preview and KSeF submission"
              )}
            </li>
            <li>
              <span aria-hidden="true">✓</span>{gettext(
                "Corrections, e.g. “give a 10% discount on invoice BC/01/10/2026”"
              )}
            </li>
            <li><span aria-hidden="true">✓</span>{gettext("Reading sales and cost invoices")}</li>
          </ul>
          <p class="landing-assistants__soon">
            ◷ {gettext(
              "Coming soon: financial analysis - invoices and real bank transactions in one place"
            )}
          </p>

          <div class="landing-assistants__diagram">
            <img
              src={~p"/images/landing/character-head.png"}
              alt=""
              width="70"
              height="103"
              loading="lazy"
            />
            <svg viewBox="0 0 250 160" aria-hidden="true" class="landing-assistants__connections">
              <path
                d="M0 80C90 80 130 10 250 10M0 80H250M0 80C90 80 130 150 250 150"
                fill="none"
                stroke="currentColor"
              />
            </svg>
            <ul class="landing-assistants__branches">
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

          <p class="landing-assistants__footnote">
            {gettext(
              "*Already used by early adopters among our users. Gradually rolling out to everyone. Available in the Entrepreneur and Company plans."
            )}
          </p>
        </div>

        <div
          class="landing-conversation"
          role="img"
          aria-label={gettext("Example conversation and invoice confirmation preview")}
        >
          <p class="landing-conversation__user">
            {gettext("Issue an invoice for Północny Kod: 120 h at PLN 180 net.")}
          </p>
          <p class="landing-conversation__author">{gettext("Using the Firmowid app")}</p>
          <p class="mt-2">
            {gettext(
              "I prepared the invoice for Północny Kod sp. z o.o. for PLN 26,568.00 gross. Check the preview and confirm - only then does it reach KSeF."
            )}
          </p>

          <div class="landing-conversation__invoice">
            <h3>{gettext("Confirm invoice")}</h3>
            <div class="landing-conversation__document">
              <div class="landing-conversation__paper">
                <strong>{gettext("VAT invoice %{number}", number: "01/10/2026")}</strong>
                <p>14.10.2026</p>
                <div class="landing-conversation__parties">
                  <p>{gettext("Seller")}<br /><strong>Bytecraft Collective sp. z o.o.</strong></p><p>
                    {gettext("Buyer")}<br /><strong>Północny Kod sp. z o.o.</strong>
                  </p>
                </div>
                <div class="landing-conversation__line-item">
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
                <p class="landing-conversation__payment">{gettext("Payment")}<br />14.11.2026</p>
                <p class="landing-conversation__paper-footer">Firmowid.pl</p>
              </div>
            </div>
            <span class="landing-button landing-button--black">{gettext("Confirm and send to KSeF")}</span>
            <p class="landing-conversation__hint">
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
    <section class="landing-section bg-white">
      <div class="landing-container landing-proof">
        <div>
          <blockquote>
            {gettext(
              "For two years, we patched together three different programs with Excel. Now one person does what three people used to do — and reports are ready at the end of the month, not a week later."
            )}
          </blockquote>
          <div class="landing-proof__author">
            <span class="landing-proof__avatar">EG</span>
            <div>
              <p class="landing-proof__author-name">
                {gettext("CEO of a television production company")}
              </p>
              <p class="landing-proof__author-role">{gettext("beta program participant")}</p>
            </div>
          </div>
        </div>

        <div class="landing-proof__figures">
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
    <section id="jak-dziala" class="landing-section bg-grey-100">
      <div class="landing-container">
        <div class="landing-section__intro mx-auto text-center">
          <p class="landing-eyebrow">{gettext("How Firmowid works")}</p>
          <h2>{gettext("From zero to your first invoice in 15 minutes")}</h2>
        </div>

        <div class="landing-steps">
          <article :for={{step, index} <- Enum.with_index(@steps, 1)}>
            <span>{index}</span>
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
    <section id="kod-zrodlowy" data-landing-dark-surface class="landing-dark landing-section">
      <div class="landing-container landing-open-source">
        <div class="landing-section__intro">
          <p class="landing-eyebrow">{gettext("Open source")}</p>
          <h2>{gettext("Your data on your server.")}</h2>
          <p>
            {gettext("Firmowid is open source. Host it yourself, without limits or fees.")}
          </p>
          <div class="landing-open-source__actions">
            <.landing_button external={@repository} variant={:orange}>
              {gettext("View on GitHub")}
              <img src={~p"/images/github-mark.svg"} alt="" width="24" height="24" />
            </.landing_button>
            <a class="landing-pill" href={@repository}>
              {gettext("AGPL-3.0 license")}
            </a>
          </div>
        </div>

        <div class="landing-open-source__benefits">
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
    <section id="zespol" class="landing-section">
      <div class="landing-container landing-team">
        <div class="landing-section__intro">
          <p class="landing-eyebrow">{gettext("Who is behind it")}</p>
          <h2>{gettext("Two people. One office in Krakow.")}</h2>
          <p>
            {gettext(
              "Firmowid is not a product made by a hundred managers for a hundred processes. It is a tool made by people who run a company themselves and know what working with KSeF, payroll, and month-end closing really looks like."
            )}
          </p>
        </div>

        <div class="landing-team__cards">
          <article :for={person <- @team}>
            <div class="landing-team__portrait">
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
            <p class="landing-team__role">{person.role}</p>
            <p class="landing-team__bio">{person.bio}</p>
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
