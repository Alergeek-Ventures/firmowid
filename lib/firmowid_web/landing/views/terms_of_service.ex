defmodule FirmowidWeb.Landing.Views.TermsOfService do
  @moduledoc """
  Terms of Service (Regulamin) page for Firmowid.

  Public page accessible at `/regulamin`. Contains the full Terms of Service
  in Polish, covering service scope, user accounts, liability limitations,
  pricing, data handling, and governing law.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.Landing.Components.LegalPage, only: [legal_page: 1]

  @legal_entity Application.compile_env!(:firmowid, :legal_entity)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Regulamin",
       meta_description:
         "Regulamin Firmowida określa zasady korzystania z usługi do fakturowania, obsługi KSeF, banku i ewidencji pracy.",
       public_marketing?: true,
       legal_entity: @legal_entity
     ), layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.legal_page>
      <h1 class="text-4xl font-bold">Regulamin</h1>
      <p class="text-sm text-neutral-500">
        Ostatnia aktualizacja: 7 września 2026 r.
      </p>

      <h2>§1. Postanowienia ogólne</h2>
      <p>
        Niniejszy Regulamin określa zasady korzystania z usługi internetowej Firmowid
        (dalej: „Usługa"), dostępnej pod adresem <FirmowidWeb.DesignSystem.Components.Link.link
          kind="unstyled"
          external="https://firmowid.pl"
          class="text-orange-700 hover:underline"
        >firmowid.pl</FirmowidWeb.DesignSystem.Components.Link.link>.
      </p>
      <p>
        Usługodawcą jest <strong>{@legal_entity.name}</strong>
        z siedzibą w {@legal_entity.headquarters_location}, {@legal_entity.address}, wpisana do Rejestru
        Przedsiębiorców prowadzonego przez XI Wydział Gospodarczy Krajowego Rejestru
        Sądowego Sądu Rejonowego dla Krakowa-Śródmieścia w Krakowie pod numerem
        KRS: {@legal_entity.krs}, NIP: {@legal_entity.nip}, REGON: {@legal_entity.regon} (dalej: „Usługodawca" lub „Alergeek Ventures").
      </p>
      <p>
        Usługa obejmuje w szczególności:
      </p>
      <ul>
        <li>Wystawianie, zarządzanie i przechowywanie faktur sprzedażowych i kosztowych</li>
        <li>Synchronizację i podgląd firmowych rachunków bankowych (Open Banking)</li>
        <li>Automatyczne przyporządkowywanie faktur do transakcji bankowych</li>
        <li>Ewidencję czasu pracy i zarządzanie projektami</li>
        <li>Zarządzanie pracownikami, urlopami i umowami</li>
        <li>Zarządzanie kontrahentami i danymi organizacji</li>
        <li>Inne funkcje związane z prowadzeniem działalności gospodarczej,
          wprowadzane w ramach rozwoju Usługi</li>
      </ul>

      <h2>§2. Konto użytkownika</h2>
      <p>
        Korzystanie z Usługi wymaga utworzenia konta użytkownika. Rejestracja
        jest możliwa za pomocą adresu e-mail lub konta Google (OAuth).
      </p>
      <p>
        Użytkownik zobowiązuje się do podania prawdziwych danych oraz do zachowania
        poufności danych logowania. Użytkownik ponosi odpowiedzialność za wszelkie
        działania wykonane za pośrednictwem swojego konta.
      </p>

      <h2>§3. Charakter Usługi</h2>
      <p>
        Firmowid jest narzędziem wspomagającym prowadzenie działalności gospodarczej.
      </p>
      <p>
        <strong>
          Usługa nie stanowi doradztwa podatkowego, księgowego ani prawnego.
        </strong>
        Użytkownik ponosi wyłączną odpowiedzialność za poprawność wprowadzanych danych,
        treść generowanych dokumentów oraz ich zgodność z obowiązującymi przepisami prawa.
      </p>
      <p>
        Usługodawca nie weryfikuje poprawności merytorycznej danych wprowadzanych przez
        użytkowników i nie ponosi odpowiedzialności za skutki wynikające z ich
        nieprawidłowości.
      </p>

      <h2>§4. Dostępność i ograniczenie odpowiedzialności</h2>
      <p>
        Usługa świadczona jest w modelu „tak jak jest" (<em>as is</em>).
        Usługodawca dokłada starań w celu zapewnienia ciągłości i poprawności
        działania Usługi, jednak nie gwarantuje jej nieprzerwanej dostępności
        ani braku błędów.
      </p>
      <p>
        <strong>
          W najszerszym zakresie dozwolonym przez obowiązujące prawo, Alergeek Ventures
          nie ponosi odpowiedzialności za jakiekolwiek szkody wynikające z korzystania
          z Usługi lub niemożności korzystania z niej, w tym w szczególności za szkody
          bezpośrednie, pośrednie, przypadkowe, następcze, utracone korzyści, utratę
          danych, przerwy w działalności gospodarczej ani jakiekolwiek inne straty
          finansowe lub niefinansowe.
        </strong>
      </p>
      <p>
        Usługodawca zastrzega sobie prawo do przerw technicznych w działaniu Usługi
        w celu przeprowadzenia prac konserwacyjnych, aktualizacji lub napraw.
      </p>

      <h2>§5. Cennik</h2>
      <p>
        Usługa dostępna jest w modelu freemium — obejmującym bezpłatny plan podstawowy
        oraz płatne plany subskrypcyjne z rozszerzonym zakresem funkcji.
      </p>
      <p>
        Aktualny cennik dostępny jest na stronie Usługi. Usługodawca zastrzega sobie
        prawo do zmiany cennika z co najmniej 30-dniowym wyprzedzeniem. Zmiana cennika
        nie wpływa na już opłacone okresy subskrypcyjne.
      </p>

      <h2>§6. Ochrona danych osobowych</h2>
      <p>
        Zasady przetwarzania danych osobowych określa <FirmowidWeb.DesignSystem.Components.Link.link
          kind="unstyled"
          navigate={~p"/polityka-prywatnosci"}
          class="text-orange-700 hover:underline"
        >
            Polityka Prywatności</FirmowidWeb.DesignSystem.Components.Link.link>, stanowiąca integralną część niniejszego Regulaminu.
      </p>

      <h2>§7. Usunięcie konta</h2>
      <p>
        Użytkownik może usunąć swoje konto w dowolnym momencie. Po usunięciu konta
        dane użytkownika są niezwłocznie usuwane z bazy danych oraz pamięci masowej
        Usługi.
      </p>
      <p>
        Resztki danych mogą pozostać w logach zewnętrznych usług (analityka, e-mail)
        przez ich standardowe okresy retencji, zgodnie z informacjami zawartymi
        w Polityce Prywatności.
      </p>

      <h2>§8. Rozwiązanie umowy</h2>
      <p>
        Usługodawca zastrzega sobie prawo do zawieszenia lub usunięcia konta
        użytkownika w przypadku naruszenia postanowień niniejszego Regulaminu,
        działania na szkodę Usługi lub innych użytkowników, bądź wykorzystywania
        Usługi w sposób niezgodny z prawem.
      </p>

      <h2>§9. Zmiany Regulaminu</h2>
      <p>
        Usługodawca zastrzega sobie prawo do zmiany niniejszego Regulaminu.
        O planowanych zmianach użytkownicy zostaną poinformowani z odpowiednim
        wyprzedzeniem drogą elektroniczną lub poprzez komunikat w Usłudze.
      </p>
      <p>
        Dalsze korzystanie z Usługi po wejściu w życie zmian Regulaminu oznacza
        ich akceptację. W przypadku braku akceptacji użytkownik ma prawo usunąć
        konto przed datą wejścia zmian w życie.
      </p>

      <h2>§10. Prawo właściwe i rozstrzyganie sporów</h2>
      <p>
        Niniejszy Regulamin podlega prawu polskiemu. Wszelkie spory wynikające
        z korzystania z Usługi będą rozstrzygane przez sąd właściwy dla siedziby
        Usługodawcy, tj. sąd w Krakowie.
      </p>

      <h2>§11. Kontakt</h2>
      <p>
        Wszelkie pytania dotyczące Regulaminu lub Usługi należy kierować na adres:
        <FirmowidWeb.DesignSystem.Components.Link.link
          kind="unstyled"
          mailto="contact@alergeek.ventures"
          class="text-orange-700 hover:underline"
        >
          contact@alergeek.ventures
        </FirmowidWeb.DesignSystem.Components.Link.link>
      </p>
    </.legal_page>
    """
  end
end
