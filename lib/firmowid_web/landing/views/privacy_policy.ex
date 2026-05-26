defmodule FirmowidWeb.Landing.Views.PrivacyPolicy do
  @moduledoc """
  Privacy Policy (Polityka Prywatności) page for Firmowid.

  Public page accessible at `/polityka-prywatnosci`. Contains the full
  RODO-compliant privacy policy in Polish, covering data collection,
  processing purposes, third-party processors, user rights, and cookies.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.Landing.Components.LegalPage, only: [legal_page: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Polityka Prywatności",
       meta_description:
         "Polityka prywatności Firmowida opisuje zasady przetwarzania danych, cookies i prawa użytkowników usługi.",
       public_marketing?: true
     ), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.legal_page>
      <h1 class="text-4xl font-bold">Polityka Prywatności</h1>
      <p class="text-sm text-neutral-500">
        Ostatnia aktualizacja: 31 marca 2026 r.
      </p>

      <h2>§1. Administrator danych</h2>
      <p>
        Administratorem danych osobowych jest <strong>Alergeek Ventures sp. z o.o.</strong>
        z siedzibą w Krakowie,
        ul. Jana Kantego Federowicza 5/96, 30-392 Kraków, wpisana do Rejestru
        Przedsiębiorców prowadzonego przez XI Wydział Gospodarczy Krajowego Rejestru
        Sądowego Sądu Rejonowego dla Krakowa-Śródmieścia w Krakowie pod numerem
        KRS: 0000874932, NIP: 6793209719, REGON: 387738728
        (dalej: „Administrator" lub „Alergeek Ventures").
      </p>
      <p>
        Kontakt w sprawach ochrony danych osobowych:
        <FirmowidWeb.DesignSystem.Components.Link.link
          kind="unstyled"
          mailto="contact@alergeek.ventures"
          class="text-orange-700 hover:underline"
        >
          contact@alergeek.ventures
        </FirmowidWeb.DesignSystem.Components.Link.link>
      </p>

      <h2>§2. Jakie dane zbieramy</h2>
      <p>
        W ramach korzystania z usługi Firmowid przetwarzamy następujące kategorie danych osobowych:
      </p>
      <ul>
        <li>
          <strong>Dane konta</strong> — imię, nazwisko, adres e-mail, dane uwierzytelniania
          (w tym za pośrednictwem Google OAuth).
        </li>
        <li>
          <strong>Dane organizacji</strong> — nazwa firmy, NIP, adres siedziby, dane kontaktowe.
        </li>
        <li>
          <strong>Dane fakturowe</strong>
          — treść faktur sprzedażowych i kosztowych, dane kontrahentów.
        </li>
        <li>
          <strong>Dane rachunków bankowych</strong> — informacje o rachunkach i transakcjach
          synchronizowane za pośrednictwem GoCardless (Open Banking).
        </li>
        <li>
          <strong>Ewidencja czasu pracy</strong>
          — wpisy dotyczące czasu pracy, przypisania do projektów.
        </li>
        <li>
          <strong>Dane techniczne</strong> — adres IP, informacje o przeglądarce, dane sesji.
        </li>
      </ul>

      <h2>§3. Cel i podstawa prawna przetwarzania</h2>
      <p>
        Dane osobowe przetwarzamy w następujących celach i na następujących podstawach prawnych:
      </p>
      <ul>
        <li>
          <strong>Wykonanie umowy</strong> (art. 6 ust. 1 lit. b RODO) — przetwarzanie jest niezbędne
          do świadczenia usługi Firmowid, w tym prowadzenia konta użytkownika, wystawiania faktur,
          synchronizacji rachunków bankowych, ewidencji czasu pracy i zarządzania organizacją.
        </li>
        <li>
          <strong>Prawnie uzasadniony interes Administratora</strong> (art. 6 ust. 1 lit. f RODO) —
          analityka i poprawa jakości usługi, zapewnienie bezpieczeństwa, wykrywanie nadużyć,
          obsługa zgłoszeń.
        </li>
        <li>
          <strong>Zgoda</strong> (art. 6 ust. 1 lit. a RODO) — opcjonalne komunikaty marketingowe,
          analityczne pliki cookies. Zgodę można wycofać w dowolnym momencie.
        </li>
      </ul>

      <h2>§4. Podmioty przetwarzające</h2>
      <p>
        W celu świadczenia usługi korzystamy z następujących podmiotów przetwarzających
        dane w naszym imieniu:
      </p>
      <ul>
        <li>
          <strong>OVH SAS</strong> — hosting serwerów oraz przechowywanie plików
          (Object Storage / S3). Dane przechowywane na terenie UE.
        </li>
        <li>
          <strong>PostHog Inc.</strong> — analityka produktowa (instancja EU).
          W przypadku braku zgody na cookies analityczne, dane są anonimizowane.
        </li>
        <li>
          <strong>Sentry</strong> — monitoring błędów aplikacji i, po uzyskaniu
          zgody, nagrania sesji diagnostycznych (Replay).
        </li>
        <li>
          <strong>Plus Five Five, Inc.</strong> (Resend) — wysyłka i odbiór wiadomości
          e-mail (powiadomienia transakcyjne oraz przetwarzanie faktur przychodzących).
        </li>
        <li>
          <strong>Google Ireland Limited</strong> (Gordon House, Barrow Street, Dublin 4, Irlandia) —
          uwierzytelnianie użytkowników (Google OAuth).
        </li>
        <li>
          <strong>GoCardless SAS</strong> — synchronizacja rachunków bankowych
          (Open Banking / Bank Account Data). Spółka zarejestrowana we Francji,
          regulowana przez ACPR.
        </li>
      </ul>

      <h2>§5. Przechowywanie danych</h2>
      <p>
        Dane osobowe przechowywane są przez okres korzystania z usługi Firmowid.
      </p>
      <p>
        Po usunięciu konta przez użytkownika dane są niezwłocznie usuwane z bazy danych
        oraz pamięci masowej (Object Storage). Resztki danych mogą pozostać w logach
        zewnętrznych usług (PostHog, Resend) przez ich standardowe okresy retencji,
        nad którymi Administrator nie ma bezpośredniej kontroli.
      </p>

      <h2>§6. Prawa użytkownika</h2>
      <p>Na podstawie RODO przysługują Ci następujące prawa:</p>
      <ul>
        <li>Prawo dostępu do danych (art. 15 RODO)</li>
        <li>Prawo do sprostowania danych (art. 16 RODO)</li>
        <li>Prawo do usunięcia danych — „prawo do bycia zapomnianym" (art. 17 RODO)</li>
        <li>Prawo do ograniczenia przetwarzania (art. 18 RODO)</li>
        <li>Prawo do przenoszenia danych (art. 20 RODO)</li>
        <li>Prawo do sprzeciwu wobec przetwarzania (art. 21 RODO)</li>
        <li>
          Prawo do wniesienia skargi do organu nadzorczego — Prezesa Urzędu Ochrony
          Danych Osobowych (ul. Stawki 2, 00-193 Warszawa)
        </li>
      </ul>
      <p>
        W celu skorzystania z powyższych praw prosimy o kontakt:
        <FirmowidWeb.DesignSystem.Components.Link.link
          kind="unstyled"
          mailto="contact@alergeek.ventures"
          class="text-orange-700 hover:underline"
        >
          contact@alergeek.ventures
        </FirmowidWeb.DesignSystem.Components.Link.link>
      </p>

      <h2>§7. Pliki cookies</h2>
      <p>Firmowid wykorzystuje następujące pliki cookies:</p>
      <ul>
        <li>
          <strong>Cookies niezbędne (sesyjne)</strong> — wymagane do prawidłowego działania
          aplikacji, utrzymania sesji użytkownika i ochrony przed atakami CSRF.
          Nie wymagają zgody.
        </li>
        <li>
          <strong>Cookies analityczne (PostHog)</strong> — wykorzystywane do analizy
          korzystania z usługi w celu jej ulepszania. Wymagają zgody użytkownika,
          zanim zapiszemy trwałe identyfikatory analityczne w przeglądarce.
          Do momentu podjęcia decyzji analityka działa wyłącznie w trybie
          anonimowym i pamięciowym (bez identyfikacji użytkownika i bez
          utrwalania identyfikatorów PostHog w przeglądarce). Po odmowie dalsza
          analityka przestaje działać.
        </li>
        <li>
          <strong>Monitoring błędów (Sentry)</strong> — działa stale w celu
          zapewnienia bezpieczeństwa i niezawodności usługi. Po wyrażeniu zgody
          możemy dodatkowo uruchomić nagrywanie sesji diagnostycznych (Replay),
          które pomaga odtworzyć kroki prowadzące do błędu.
        </li>
        <li>
          <strong>Cookie preferencji (cookie_consent)</strong> — przechowuje informację
          o wyrażeniu lub odmowie zgody na cookies analityczne. Ważność: 1 rok.
        </li>
      </ul>

      <h2>§8. Zmiany Polityki Prywatności</h2>
      <p>
        Administrator zastrzega sobie prawo do zmiany niniejszej Polityki Prywatności.
        O wszelkich zmianach użytkownicy zostaną poinformowani poprzez publikację
        zaktualizowanej wersji na stronie
        <FirmowidWeb.DesignSystem.Components.Link.link
          kind="unstyled"
          navigate={~p"/polityka-prywatnosci"}
          class="text-orange-700 hover:underline"
        >
          firmowid.pl/polityka-prywatnosci
        </FirmowidWeb.DesignSystem.Components.Link.link>
        wraz z datą ostatniej aktualizacji.
      </p>
    </.legal_page>
    """
  end
end
