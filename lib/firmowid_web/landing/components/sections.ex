defmodule FirmowidWeb.Landing.Components.Sections do
  @moduledoc """
  Main content sections for the public landing page.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Billing.PlanCatalog
  alias FirmowidWeb.Infrastructure.Utilities.PolishQuantity
  alias Phoenix.LiveView.Rendered

  @problems [
    %{
      number: "01",
      title: "Rozproszone narzędzia",
      description:
        "Inny program do faktur, inny do czasu pracy, jeszcze inny do rozliczeń z bankiem. Dane się nie zgadzają, raporty robi się ręcznie."
    },
    %{
      number: "02",
      title: "Niepewność wokół KSeF",
      description:
        "Przepisy się zmieniają, terminy przesuwają. Twój obecny system może nie nadążyć za aktualizacjami, a kary za błędy są realne."
    },
    %{
      number: "03",
      title: "Budżet, który dezaktualizuje się w dniu utworzenia",
      description:
        "Kto dokładnie ile przepracował? Co się zmieściło w budżecie projektu? Zanim zrobisz zestawienie, tydzień się skończy."
    }
  ]

  @features [
    %{
      tags: [{"fakturowanie", :default}, {"KSeF", :default}, {"nowość", :accent}],
      title: "Faktury, które trafiają do KSeF same",
      description:
        "Wystaw, wyślij, odbierz. Firmowid łączy się z Krajowym Systemem e-Faktur i pilnuje każdej zmiany w przepisach za Ciebie.",
      bullets: [
        "Automatyczna walidacja zgodności z KSeF",
        "Ponowienie wysyłki przy obciążeniu systemu rządowego",
        "Eksport faktur (w formacie PDF i XML)"
      ],
      variant: :invoice,
      reverse: false
    },
    %{
      tags: [{"fakturowanie", :default}, {"rachunki bankowe", :default}],
      title: "Transakcje dopasowane do faktur",
      description:
        "Każda transakcja trafia do właściwej faktury automatycznie. Koniec z ręcznym kojarzeniem przelewów na koniec miesiąca.",
      bullets: [
        "Automatyczne dopasowanie transakcji do faktur",
        "Integracja z polskimi i zagranicznymi bankami",
        "Eksport dla księgowości w jednym kliknięciu",
        "Informacje przy nieopłaconych fakturach",
        "Flagowanie transakcji bez dokumentów"
      ],
      variant: :banking,
      reverse: true
    },
    %{
      tags: [{"ewidencja", :default}, {"czas pracy", :default}],
      title: "Godziny, które same się liczą",
      description:
        "Twoi pracownicy liczą swój czas godzinowo, a Ty w sumie dalej nie wiesz, ile naprawdę kosztuje praca zespołu? Firmowid ma wszystko pod kontrolą.",
      bullets: [
        "Monitorowanie czasu pracy w czasie rzeczywistym",
        "Ewidencja godzin per projekt i per pracownik",
        "Koszty pracy od razu widoczne w raportach",
        "Eksport ewidencji w jednym kliknięciu"
      ],
      variant: :time,
      reverse: false
    },
    %{
      tags: [{"płace", :default}, {"rozliczenia", :default}],
      title: "Płace, które nie gubią się w excelu",
      description:
        "Z godzin pracy, stawek i umów Firmowid sam policzy, kto ile zarobił. Paski wypłat, przelewy, rozliczenia - wszystko z jednego miejsca.",
      bullets: [
        "Automatyczne obliczenia na podstawie ewidencji godzin",
        "Obsługa umów zlecenia, UoP, B2B",
        "Generowanie pasków i deklaracji",
        "Przelewy zbiorcze do banku"
      ],
      variant: :payroll,
      reverse: true
    }
  ]

  @how_it_works [
    %{
      number: 1,
      title: "Załóż konto",
      description: "E-mail, hasło, nazwa firmy. Zero karty kredytowej. 30 dni za darmo."
    },
    %{
      number: 2,
      title: "Zintegruj dane",
      description: "Połączymy konto bankowe i KSeF. Zaimportujemy kontrahentów z pliku lub poprzedniego systemu."
    },
    %{
      number: 3,
      title: "Wystaw pierwszą fakturę",
      description: "Wybierz kontrahenta, kliknij „wystaw”. Firmowid zajmie się resztą - włącznie z wysyłką do KSeF."
    }
  ]

  @plan_marketing %{
    start: %{
      key: "start",
      name: "Start",
      audience: "Polecany dla: wszystkich osób korzystających z KSeF",
      features: [
        "Integracja z KSeF",
        "Przejrzysty kreator faktur",
        "Baza kontrahentów"
      ],
      highlighted: false
    },
    przedsiebiorca: %{
      key: "przedsiebiorca",
      name: "Przedsiębiorca",
      audience: "Polecany dla: jednoosobowych działalności i freelancerów",
      features: [
        "Integracja z KSeF",
        "Przejrzysty kreator faktur",
        "Baza kontrahentów",
        "Powiadomienia e-mail"
      ],
      highlighted: true
    },
    firma: %{
      key: "firma",
      name: "Firma",
      audience: "Polecany dla: zespołów, firm powyżej 15 osób",
      features: [
        "Integracja z KSeF",
        "Przejrzysty kreator faktur",
        "Baza kontrahentów",
        "Powiadomienia e-mail",
        "Czasośledzenie",
        "Zarządzanie pracownikami i projektami"
      ],
      highlighted: false
    }
  }

  @team [
    %{
      name: "Franek Madej",
      role: "CEO · Alergeek Ventures",
      portrait_alt: "Portret Franka Madeja",
      portrait_id: "team-portrait-franek",
      portrait_width: "832",
      portrait_height: "1248",
      bio:
        "Od dekady doradza firmom w tworzeniu oprogramowania, pracując m.in. ze startupami z ekosystemu Y Combinator. Ma obsesję na punkcie produktów dopracowanych w każdym szczególe i przekładania złożonych procesów na proste narzędzia."
    },
    %{
      name: "Stanisław Madej",
      role: "COO · Alergeek Ventures",
      portrait_alt: "Portret Stanisława Madeja",
      portrait_id: "team-portrait-stanislaw",
      portrait_width: "2731",
      portrait_height: "4096",
      bio:
        "W firmie Alergeek Ventures dba o logistykę firmy, zarządzanie 20-osobowym zespołem. Szczęśliwy użytkownik Firmowida, którego wykorzystuje do codziennych zadań; dzięki czemu więcej czasu na zarządzanie a coraz mniej czasu poświęca na faktury oraz rozliczenia."
    }
  ]

  @faqs [
    %{
      id: "faq-ksef",
      question: "Czy Firmowid jest zgodny z KSeF?",
      answer:
        "Tak. Pełna zgodność z KSeF i automatyczne śledzenie zmian w przepisach - nasi programiści wdrażają je od razu po komunikacji od Ministerstwa Finansów."
    },
    %{
      id: "faq-migration",
      question: "Jak wygląda migracja z innego programu?",
      answer:
        "Zaczynasz od połączenia KSeF i banku - importujemy dane z ostatnich 3 miesięcy. Momentalnie możesz zacząć dopasowywać transakcje do faktur i zacząć analizować przepływy finansowe."
    },
    %{
      id: "faq-security",
      question: "Czy moje dane są bezpieczne?",
      answer:
        "Tak. Firmowid akcentuje bezpieczne przechowywanie danych, a cały przepływ jest projektowany pod obsługę firmowych danych finansowych."
    },
    %{
      id: "faq-cancel",
      question: "Czy mogę anulować w każdej chwili?",
      answer: "Tak. Możesz zrezygnować w dowolnym momencie, a konto usunąć bez długoterminowych zobowiązań."
    },
    %{
      id: "faq-overage",
      question: "Jak działają dodatkowe opłaty za faktury spoza KSeF i konta bankowe?",
      answer:
        "W pakiecie Start nie ma w cenie faktur spoza KSeF, a każde dodatkowe konto bankowe kosztuje 10 zł netto + VAT miesięcznie. W pakiecie Przedsiębiorca masz w cenie 20 faktur spoza KSeF, 3 konta bankowe i 5 pracowników miesięcznie, a w pakiecie Firma 100 faktur, 10 kont bankowych i 20 pracowników. Po wykorzystaniu limitu naliczamy opłaty zgodnie z cennikiem pakietu."
    },
    %{
      id: "faq-banks",
      question: "Jakie banki obsługujecie?",
      answer:
        "Obsługiwane są banki, w których polscy przedsiębiorcy mogą mieć konto. Między innymi: PKO BP, Pekao, Santander, mBank, ING, Alior Bank, Millennium, Revolut."
    }
  ]

  @doc """
  Renders the audience/problem section.
  """
  @spec audience_section(map()) :: Rendered.t()
  def audience_section(assigns) do
    assigns = assign(assigns, :problems, @problems)

    ~H"""
    <section
      id="dla-kogo"
      data-landing-dark-surface
      class="border-b border-[#363636] bg-[#0f0f0f] px-4 py-20 text-white sm:px-6 lg:px-10"
    >
      <div class="mx-auto max-w-[1419px] lg:px-[140px]">
        <div class="max-w-[680px]">
          <.section_eyebrow dark>Dla kogo</.section_eyebrow>
          <h2 class="mt-2 text-[38px] leading-[1.08] font-bold tracking-[-0.03em] text-[#fafafa] lg:text-[48px] lg:leading-[50px]">
            Prowadzisz firmę. <br class="hidden lg:block" />
            Nie chcesz prowadzić arkuszy kalkulacyjnych.
          </h2>
          <p class="mt-4 text-[18px] leading-[27px] text-[#dddddd] lg:mt-4">
            Firmowid powstał dla polskich MŚP, które mają już dość przeskakiwania z programu do
            programu i zapisywaniu wszystkiego w excelu.
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
    assigns = assign(assigns, :features, @features)

    ~H"""
    <section id="funkcje" class="px-4 py-16 sm:px-6 lg:px-10 lg:py-20">
      <div class="mx-auto max-w-[1419px] lg:px-[140px]">
        <div class="max-w-[680px]">
          <.section_eyebrow>Co potrafi Firmowid</.section_eyebrow>
          <h2 class="mt-2 text-[38px] leading-[1.08] font-bold tracking-[-0.03em] text-[#0f0f0f] lg:text-[48px] lg:leading-[50px]">
            Cztery rzeczy, których Twoja firma potrzebuje. <br class="hidden lg:block" />
            W jednym miejscu.
          </h2>
          <p class="mt-4 text-[18px] leading-[27px] text-[#4e4e4e] lg:hidden">
            Firmowid powstał dla polskich MŚP, które mają już dość przeskakiwania z programu do
            programu i zapisywaniu wszystkiego w excelu.
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
    assigns = assign(assigns, :steps, @how_it_works)

    ~H"""
    <section id="jak-dziala" class="bg-white">
      <div class="px-4 py-10 sm:px-6 lg:px-10 lg:py-20">
        <div class="mx-auto max-w-[1419px] lg:px-[140px]">
          <div class="flex flex-col gap-8 lg:flex-row lg:items-center lg:justify-between">
            <div class="max-w-[718px]">
              <blockquote class="relative ml-4 text-[23px]/8 font-medium tracking-[-0.01em] text-[#1a1a1a] lg:ml-0 lg:text-[32px] lg:leading-[1.15] lg:tracking-[-0.01em]">
                <span class="absolute top-0 -left-7 text-[56px] leading-[0.66] text-[#8b3f13] lg:-left-8 lg:text-[64px]">„</span>Przez dwa lata kleiliśmy trzy różne programy z Excelem. Teraz jedna osoba robi to,
                co wcześniej robiło troje - a raporty są gotowe na koniec miesiąca, nie po tygodniu<span class="align-bottom text-[56px] leading-[0.66] text-[#8b3f13] lg:text-[64px]">”</span>
              </blockquote>

              <div class="mt-8 flex items-center gap-3">
                <div class="flex size-12 items-center justify-center rounded-full bg-[linear-gradient(135deg,#7a9471,#9ab892)] text-base font-bold text-white">
                  EG
                </div>
                <div>
                  <p class="text-[15px] font-semibold text-[#1a1a1a]">
                    Prezes spółki produkcji telewizyjnej
                  </p>
                  <p class="mt-1 text-[13px] text-[#4e4e4e]">
                    uczestnik programu beta
                  </p>
                </div>
              </div>
            </div>

            <div class="hidden lg:flex lg:w-[360px] lg:items-center lg:justify-between lg:gap-8">
              <div class="h-[197px] w-px bg-[#dedede]" />
              <div class="space-y-6">
                <div>
                  <p class="text-[42px] font-bold text-[#8b3f13]">−12h</p>
                  <p class="text-[13px] text-[#4e4e4e]">mniej pracy administracyjnej tygodniowo</p>
                </div>
                <div>
                  <p class="text-[42px] font-bold text-[#8b3f13]">0</p>
                  <p class="text-[13px] text-[#4e4e4e]">błędów w KSeF od wdrożenia</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-[#f5f5f5] px-4 py-16 sm:px-6 lg:px-10 lg:py-[104px]">
        <div class="mx-auto max-w-[1419px] lg:px-[100px]">
          <div class="mx-auto max-w-[680px] text-center">
            <.section_eyebrow>Jak działa Firmowid</.section_eyebrow>
            <h2 class="mt-2 text-[38px] leading-[1.08] font-bold tracking-[-0.03em] text-[#0f0f0f] lg:text-[48px] lg:leading-[50px]">
              Od zera do pierwszej faktury w 15 minut
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
    assigns = assign(assigns, :plans, pricing_plans())

    ~H"""
    <section id="cennik" class="bg-white px-4 py-16 sm:px-6 lg:px-10 lg:py-[100px]">
      <div class="mx-auto max-w-[1419px] lg:px-8 xl:px-[140px]">
        <div class="mx-auto max-w-[588px] text-center">
          <.section_eyebrow>Cennik</.section_eyebrow>
          <h2 class="mt-2 text-[38px] leading-[1.08] font-bold tracking-[-0.03em] text-[#0f0f0f] lg:text-[48px] lg:leading-[50px]">
            Uczciwy cennik.<br /> <span class="underline">Bez gwiazdek.</span>
          </h2>
          <p class="mt-4 text-[18px] leading-[27px] text-[#4e4e4e]">
            Płacisz za to, z czego rzeczywiście korzystasz. Wybierz pakiet i rodzaj rozliczenia,
            które najlepiej do Ciebie pasują.
          </p>
          <p class="mt-2 text-sm font-medium text-[#8b3f13]">Wszystkie ceny netto + VAT.</p>
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
              Miesięcznie
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
              Rocznie
              <span class={[
                "rounded-2xl px-2 py-1 text-xs font-medium",
                @billing_period == "yearly" && "bg-[#dea785] text-[#4e2005]",
                @billing_period != "yearly" && "bg-[#8b3f13] text-white"
              ]}>
                Taniej
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
    assigns = assign(assigns, :team, @team)

    ~H"""
    <section
      id="zespol"
      class="border-t border-[#e9c3ac] px-4 py-16 sm:px-6 lg:border-t-0 lg:px-10 lg:py-[140px]"
    >
      <div class="mx-auto max-w-[1419px] lg:grid lg:grid-cols-[minmax(0,1fr)_572px] lg:items-center lg:gap-12 lg:px-[140px]">
        <div class="max-w-[543px] lg:max-w-none">
          <.section_eyebrow>Kto za tym stoi</.section_eyebrow>
          <h2 class="mt-2 text-[38px] leading-[1.08] font-bold tracking-[-0.03em] text-[#0f0f0f] lg:text-[48px] lg:leading-[50px]">
            Dwie osoby. Jedno biuro w Krakowie.
          </h2>
          <p class="mt-4 text-[18px] leading-[27px] text-[#4e4e4e]">
            Firmowid nie jest produktem stu menedżerów od stu procesów. To narzędzie zrobione przez
            ludzi, którzy sami prowadzą firmę i wiedzą, jak wygląda praca z KSeF, rozliczaniem
            pracowników i zamykaniem miesiąca.
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
    assigns = assign(assigns, :faqs, @faqs)

    ~H"""
    <section id="faq" class="border-t border-[#e6d7ce] px-4 py-16 sm:px-6 lg:px-10 lg:py-[140px]">
      <div class="mx-auto max-w-[1419px] lg:flex lg:items-start lg:gap-12 lg:px-[140px]">
        <div class="max-w-[460px] lg:flex-1">
          <.section_eyebrow>Pytania i odpowiedzi</.section_eyebrow>
          <h2 class="mt-2 text-[38px] leading-[1.08] font-bold tracking-[-0.03em] text-[#0f0f0f] lg:text-[48px] lg:leading-[50px]">
            Zanim zapytasz <br />- może już odpowiedzieliśmy.
          </h2>
          <p class="mt-4 text-[18px] leading-[27px] text-[#4e4e4e]">
            Nie znalazłeś swojego pytania?
            <.link
              kind="unstyled"
              mailto="contact@alergeek.ventures"
              class="font-bold text-[#4e4e4e] underline underline-offset-4 hover:text-[#8b3f13]"
            >
              Napisz do nas.
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
          <p>Faktura FV 10/2026</p>
          <p>01.10.2026</p>
        </div>
      </div>
      <div class={[
        "text-[#1a1a1a]",
        @compact && "pt-2 text-[7.5px] leading-[11px]",
        !@compact && "pt-3 text-[11px] leading-[16.5px]"
      ]}>
        <div class="flex items-start justify-between border-b border-dashed border-[#e5ddd0] py-[6px]">
          <span>Usługi doradcze (40h)</span><span>16 000,00</span>
        </div>
        <div class="flex items-start justify-between border-b border-dashed border-[#e5ddd0] py-[6px]">
          <span>Licencja oprogramowania</span><span>1 788,00</span>
        </div>
        <div class="flex items-start justify-between border-b border-dashed border-[#e5ddd0] py-[6px]">
          <span>VAT 23%</span><span>1 620,00</span>
        </div>
        <div class="flex items-start justify-between pt-[10px] font-bold">
          <span>Razem brutto</span><span>19 408,00 zł</span>
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
            <p class="text-sm font-bold text-[#1a1a1a]">Powiązane płatności</p>
            <p class="mt-1 text-[10px] text-[#4e4e4e]">
              Automatyczne dopasowanie faktur do przelewów
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
              <p class="text-[11px] text-[#4e4e4e]">Przelew dopasowany automatycznie</p>
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
            <p class="text-sm font-bold text-[#1a1a1a]">Ewidencja czasu</p>
            <p class="mt-1 text-[10px] text-[#4e4e4e]">Koszty i godziny w czasie rzeczywistym</p>
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
            <span>Koszt pracy w tym tygodniu</span>
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
            <p class="text-sm font-bold text-[#1a1a1a]">Rozliczenia płac</p>
            <p class="mt-1 text-[10px] text-[#4e4e4e]">Od ewidencji do wypłaty z jednego miejsca</p>
          </div>
          <span class="rounded-full bg-[#e8efe5] px-3 py-1 text-[10px] font-bold text-[#475e45]">
            Gotowe
          </span>
        </div>
        <div class="mt-4 space-y-3">
          <div class="flex items-center justify-between rounded-lg bg-white p-3 shadow-[0_4px_16px_rgba(80,50,30,0.08)]">
            <div>
              <p class="text-xs font-semibold text-[#1a1a1a]">Jan Nowak</p>
              <p class="text-[11px] text-[#4e4e4e]">Umowa B2B • 160h</p>
            </div>
            <p class="text-sm font-bold text-[#1a1a1a]">12 800 zł</p>
          </div>
          <div class="flex items-center justify-between rounded-lg border border-dashed border-[#d8c7bb] p-3 text-[11px] text-[#4e4e4e]">
            <span>Paczka przelewów przygotowana</span>
            <strong class="text-[#8b3f13]">4 osoby</strong>
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
              do: "netto + VAT / mies. przy płatności za rok",
              else: "netto + VAT / mies."}
          </p>
          <p
            :if={@billing_period == "yearly"}
            class={[
              "mt-3 text-[15px]/6 font-normal",
              @plan.highlighted && "text-[#b5b5b5]",
              !@plan.highlighted && "text-[#5f5f5f]"
            ]}
          >
            Płatność z góry za rok:<br />
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
              Limity w pakiecie
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
              Dostępne funkcje
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
              Miesięcznie
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
              Rocznie
              <span class={[
                "rounded-2xl px-2 py-1 text-[10px]",
                @plan.highlighted && @billing_period == "yearly" && "bg-[#dea785] text-[#4e2005]",
                @plan.highlighted && @billing_period != "yearly" && "bg-[#dea785] text-[#4e2005]",
                !@plan.highlighted && @billing_period == "yearly" && "bg-white/20 text-white",
                !@plan.highlighted && @billing_period != "yearly" && "bg-[#8b3f13] text-white"
              ]}>
                Taniej
              </span>
            </button>
          </div>

          <.link
            kind="unstyled"
            navigate={~p"/zarejestruj"}
            class={[
              "relative flex min-h-[56px] w-full items-center justify-center overflow-hidden rounded-[4px] px-8 py-4 text-base font-medium transition-transform duration-150 hover:-translate-y-0.5",
              @plan.highlighted &&
                "border-2 border-[#d2936d] bg-[#d2936d] text-black hover:bg-[#dea785]",
              !@plan.highlighted &&
                "text-[#1a1a1a] before:absolute before:inset-0 before:bg-[url('/images/button_login.svg')] before:bg-size-[100%_100%] before:bg-no-repeat before:content-[''] hover:bg-black/3"
            ]}
          >
            <span class="relative z-10">Zacznij za darmo</span>
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
          "faktura spoza KSeF",
          "faktury spoza KSeF",
          "faktur spoza KSeF"
        ),
        included_usage_line(
          rules.synced_bank_accounts,
          "konto bankowe",
          "konta bankowe",
          "kont bankowych"
        ),
        included_usage_line(
          rules.active_non_owner_users,
          "pracownik",
          "pracowników",
          "pracowników"
        )
      ],
      &is_nil/1
    )
  end

  defp included_usage_line(%{included_units: 0}, _singular, _paucal, _plural), do: nil

  defp included_usage_line(%{included_units: included_units}, singular, paucal, plural) do
    "#{PolishQuantity.quantity(included_units, singular, paucal, plural)} / mies."
  end

  defp money_with_currency(nil), do: nil

  defp money_with_currency(value) do
    "#{Decimal.to_string(value, :normal)} zł"
  end
end
