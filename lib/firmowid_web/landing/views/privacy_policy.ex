defmodule FirmowidWeb.Landing.Views.PrivacyPolicy do
  @moduledoc """
  Privacy Policy (Polityka Prywatności) page for Firmowid.

  Public page accessible at `/polityka-prywatnosci`. Contains the full
  RODO-compliant privacy policy in Polish, covering data collection,
  processing purposes, third-party processors, user rights, and cookies.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.Landing.Components.LegalPage, only: [legal_page: 1]

  @legal_entity Application.compile_env!(:firmowid, :legal_entity)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Polityka Prywatności",
       meta_description:
         "Polityka prywatności Firmowida opisuje zasady przetwarzania danych, cookies i prawa użytkowników usługi.",
       public_marketing?: true,
       legal_entity: @legal_entity
     ), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.legal_page>
      <h1 class="text-4xl font-bold">Polityka Prywatności</h1>
      <p class="text-sm text-neutral-500">
        Ostatnia aktualizacja: 30 września 2026 r.
      </p>

      <h2>§1. Administrator danych</h2>
      <p>
        Administratorem danych osobowych jest <strong>{@legal_entity.name}</strong>
        z siedzibą w {@legal_entity.headquarters_location}, {@legal_entity.address}, wpisana do Rejestru
        Przedsiębiorców prowadzonego przez XI Wydział Gospodarczy Krajowego Rejestru
        Sądowego Sądu Rejonowego dla Krakowa-Śródmieścia w Krakowie pod numerem
        KRS: {@legal_entity.krs}, NIP: {@legal_entity.nip}, REGON: {@legal_entity.regon} (dalej: „Administrator" lub „Alergeek Ventures").
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
          <strong>Dane z analizy dokumentów</strong> — pliki dokumentów przesyłane
          przez użytkownika oraz dane z nich wyodrębnione, w szczególności dane
          faktur, sprzedawców i pozycji faktur.
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
          analityczne pliki cookies i nagrywanie sesji. Zgodę można wycofać
          w dowolnym momencie.
        </li>
      </ul>
      <p>
        Informacje o założeniu konta i korzystaniu z wybranych funkcji pomagają nam
        lepiej rozumieć potrzeby użytkowników i rozwijać Firmowid. W tym celu
        korzystamy z PostHog. Informacje te są powiązane z kontem użytkownika,
        a w przypadku korzystania z funkcji organizacji także z organizacją.
        Analiza nie obejmuje treści faktur ani danych kontrahentów. Ten zakres
        analizy nie korzysta z cookies analitycznych i jest niezależny od ustawień
        dotyczących tych cookies.
      </p>

      <h2>§4. Podmioty przetwarzające</h2>
      <p>
        W działaniu Firmowida wspierają nas wymienieni poniżej dostawcy. W ramach
        świadczonych usług przetwarzają informacje potrzebne do realizacji
        opisanych celów:
      </p>
      <ul>
        <li>
          <strong>OVH SAS</strong> (2 rue Kellermann, 59100 Roubaix, Francja) —
          hosting infrastruktury aplikacji i przechowywanie plików w Object Storage.
          Dane przechowywane są na terenie Unii Europejskiej.
        </li>
        <li>
          <strong>PostHog Inc.</strong> (2261 Market Street, #4008, San Francisco,
          CA 94114, USA) — analiza korzystania z Usługi, w tym czynności opisanych
          w §3. Korzystamy z usług PostHog świadczonych w Unii Europejskiej.
        </li>
        <li>
          <strong>Functional Software, Inc. (Sentry)</strong> (45 Fremont Street,
          8th Floor, San Francisco, CA 94105, USA) — monitorowanie błędów, awarii
          i wydajności Usługi. Raporty mogą zawierać dane techniczne oraz kontekst
          niezbędny do zdiagnozowania błędu. Po wyrażeniu zgody mogą obejmować także
          nagrania sesji pomagające ustalić przyczynę błędu.
        </li>
        <li>
          <strong>Plus Five Five, Inc. (Resend)</strong> (2261 Market Street #5039,
          San Francisco, CA 94114, USA) — obsługa poczty e-mail: wysyłanie wiadomości
          transakcyjnych, odbiór wiadomości kierowanych do Usługi oraz obsługa
          załączników, w tym dokumentów przesyłanych do przetworzenia.
        </li>
        <li>
          <strong>Google Ireland Limited</strong> (Gordon House, Barrow Street, Dublin 4, Irlandia) —
          uwierzytelnianie użytkowników przez Google OAuth. W tym celu otrzymujemy
          dane profilu udostępnione podczas logowania, w szczególności adres e-mail,
          imię i nazwisko oraz identyfikator konta Google.
        </li>
        <li>
          <strong>GoCardless Limited</strong> (Sutton Yard, 65 Goswell Road, London,
          EC1V 7EN, Wielka Brytania) — usługi Open Banking, tj. uwierzytelnienie
          połączenia z rachunkiem bankowym oraz pobieranie informacji o rachunkach
          i transakcjach. GoCardless działa jako niezależny administrator w zakresie
          wymaganym do świadczenia regulowanych usług bankowych.
        </li>
        <li>
          <strong>Reducto, Inc.</strong>
          (77 Geary Street, San Francisco, CA 94108, USA) — analiza plików dokumentów przesłanych
          przez użytkownika, w tym dokumentów fakturowych i umów, oraz OCR i
          wyodrębnianie z nich danych potrzebnych do działania funkcji Usługi.
          W ramach tej usługi Reducto przetwarza treść dokumentu lub adres
          umożliwiający jego pobranie.
        </li>
        <li>
          <strong>OpenAI Ireland Limited</strong>
          (1st Floor, The Liffey Trust Centre, 117-126 Sheriff Street Upper, Dublin 1,
          D01 YC43, Irlandia) — automatyczne tworzenie opisów faktur kosztowych,
          ujednolicanie nazw sprzedawców oraz wspomaganie funkcji asystenta i
          dopasowywania faktur do transakcji. W ramach tych funkcji OpenAI przetwarza
          dane wyodrębnione z faktur, w szczególności dane sprzedawcy, pozycje i
          wartości faktury, a także informacje podane przez użytkownika.
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
          <strong>Cookies analityczne (PostHog)</strong> — pomagają analizować
          korzystanie z Usługi w przeglądarce. Są opcjonalne i zapisujemy je po
          wyrażeniu zgody. Przed dokonaniem wyboru analiza nie zapisuje trwale
          danych w przeglądarce ani nie jest powiązana z kontem. Wybór „Odrzuć”
          wyłącza tę formę analizy. Ustawienia cookies dotyczą analizy w
          przeglądarce; zakres analizy związanej z kontem opisujemy w §3.
        </li>
        <li>
          <strong>Monitoring błędów (Sentry)</strong> — działa stale w celu
          zapewnienia bezpieczeństwa i niezawodności usługi. Po wyrażeniu zgody
          możemy dodatkowo uruchomić nagrywanie sesji w przeglądarce,
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
