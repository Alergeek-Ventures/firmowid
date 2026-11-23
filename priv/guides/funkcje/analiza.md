---
title: "Program do analizy przychodów i kosztów małej firmy"
description: "Analiza Firmowida pokazuje, ile zostaje z każdych 100 zł przychodu, dzieli koszty na 12 kategorii i liczy wynik miesiąca. Cena, porównanie i ograniczenia."
published: 2026-11-18
updated: 2026-11-20
landing:
  kicker: "Funkcje · Analiza"
  note: "ile zostaje ze 100 zł"
  facts:
    - label: "Cena"
      value: "w każdym planie, także za 0 zł"
    - label: "Kategorie kosztów"
      value: "12, podpowiada AI"
    - label: "Dane"
      value: "opłacone faktury i przelewy"
  split:
    period: "Styczeń do października 2026"
    left: 23
    costs:
      - name: "Wynagrodzenia i ZUS"
        share: 38
      - name: "Podwykonawcy"
        share: 19
      - name: "Lokal i media"
        share: 11
      - name: "Pozostałe koszty"
        share: 9
---

Analiza daje nam szybki przegląd sytuacji. Zerkamy i od razu wiemy, co mówią ostatnie miesiące. Poza tym daje nam przede wszystkim możliwość korzystania z Claude i robienia analiz bardziej dostosowanych do bieżącego problemu. Firmowid opisuje dane i synchronizuje je z kilku źródeł, więc Claude ma wszystko jak na tacy i może przygotować taką analizę, jaką chcemy.

Ten ekran jest dosyć mocny. Faktycznie można zobaczyć na własne oczy, ile koniec końców zostaje z każdych 100 zł przychodu. Spodziewałem się, że ta kwota będzie trochę wyższa.

Większość kategorii zaznacza nam już AI. Z każdym miesiącem się uczy, więc po paru miesiącach trzeba naprawdę niewiele. Ma się wtedy w Firmowidzie prawie że dyrektora finansowego albo szefa analityki finansowej, bo od razu potrafi wyciągnąć bardzo dużo rzeczy i przygotować pytania oraz analizy indywidualnie pod firmę.

## Jak to działa

Do Analizy niczego nie wpisujesz. Liczy się ona z tego, co już jest w Firmowidzie: z faktur pobranych z KSeF i z przelewów z banku.

| Krok | Gdzie | Co | Ekran |
|---|---|---|---|
| Faktury i przelewy | KSeF i bank | do wyniku wchodzą faktury opłacone przelewem | ![Przelew z proponowaną fakturą i przyciskiem „Zatwierdź”](/images/guides/pomoc/transakcja-sugestie.webp) |
| Kategorie | Podsumowanie | AI proponuje kategorię kontrahenta, a Ty ją zatwierdzasz | ![Analiza, „Podsumowanie”: zdanie o 100 zł, pasek kosztów i pytania do asystenta AI](/images/guides/funkcje/analiza-podsumowanie.webp) |
| Wynik miesiąc po miesiącu | Trendy | jeden słupek na każdy domknięty miesiąc | ![Analiza, „Trendy”: wynik miesiąc po miesiącu](/images/guides/funkcje/analiza-trendy.webp) |

Krok po kroku: [Analiza: jak czytać Podsumowanie i Trendy](/pomoc/analiza-podsumowanie-i-trendy).

## Ile zostaje ze 100 zł

Widok „Podsumowanie” zaczyna się od jednego zdania: „Z każdych 100 zł przychodu zostało…”. Pod nim jest pasek, na którym kolorowe odcinki to największe kategorie kosztów, a zielony to część, która zostaje w firmie.

**Porównania.** Pod głównym paskiem są węższe: poprzedni miesiąc, ten sam okres rok wcześniej albo ostatnie 3 miesiące. Przy jednym miesiącu każda kategoria ma dopisek, ile wynosi zwykle.

**Szczegóły.** Kliknięcie nazwy kategorii pokazuje kontrahentów, którzy się na nią składają, z kwotami.

**Nieopłacone faktury.** Są pokazane osobno, poza sumą, więc nie zawyżają wyniku.

## Kategorie kosztów

Koszty dzielą się na 12 kategorii:

- Wynagrodzenia i ZUS
- Podwykonawcy
- Lokal i media
- Oprogramowanie i IT
- Marketing
- Usługi zewnętrzne
- Opłaty i prowizje
- Transport i paliwo
- Wyposażenie i materiały biurowe
- Towary i surowce
- Podatki
- Pozostałe koszty

Kategorię proponuje AI na podstawie kontrahenta, pozycji faktury i jego kodu PKD z rejestru. Przelewy wynagrodzeń, składek ZUS i podatków Firmowid rozpoznaje bez pytania.

Propozycję zatwierdzasz albo zmieniasz jednym kliknięciem. Wybór obejmuje wszystkie wpisy tego kontrahenta, także przyszłe, więc z każdym miesiącem zostaje mniej do przejrzenia.

## Projekty i trendy

Widok „Trendy” pokazuje wynik każdego miesiąca jako słupek: zysk rośnie w górę, strata w dół. Kliknięcie słupka otwiera podsumowanie tego jednego miesiąca. Najdłuższy okres to 36 miesięcy.

**Jeden projekt.** Przełącznik „Pokaż” zawęża trendy do wybranego projektu. Wynik projektu to jego przychody minus koszty do niego przypisane. Kosztów wspólnych firmy Analiza na projekty nie rozkłada.

Skąd wziąć godziny i koszty projektu: [Czas pracy w projektach](/funkcje/czas-pracy) · [Rentowność projektu w małej firmie](/poradnik/rentownosc-projektu-firma-uslugowa).

## Pytania do asystenta AI

Pod liczbami są kafelki z gotowymi pytaniami do asystenta AI, dobranymi do tego, co widać na ekranie. Kliknięcie otwiera rozmowę, w której asystent AI zna już okres i kwoty.

- Gdzie mogę na tym zaoszczędzić?
- Dlaczego to rośnie?
- Kto mi jeszcze nie zapłacił?
- Dlaczego ten miesiąc był najsłabszy?

Te same dane są dostępne w Claude i ChatGPT. Tam zapytasz też o rzeczy, których nie ma na ekranie:

- Jaki powtarzalny koszt z ostatnich 3 miesięcy dałoby się zniwelować?
- Jakie są prognozy na kolejne miesiące?
- Co się stanie z wynikiem na koniec roku, jeśli zmienimy jeden czynnik?

Jak podłączyć Claude: [Firmowid w Claude i ChatGPT](/funkcje/claude-chatgpt-mcp).

## Ile to kosztuje

| Plan | Analiza | Banki zasilające Analizę | Claude i ChatGPT | Cena |
|---|---|---|---|---|
| Darmowy | tak | 1 | nie | 0 zł |
| Przedsiębiorca | tak | 3 | tak | 29 zł netto miesięcznie |
| Firma | tak | bez limitu | tak | 149 zł netto miesięcznie |

Analiza nie ma własnego limitu. Im więcej kont firmy jest podłączonych, tym pełniejszy obraz kosztów.

## Porównanie z innymi programami

W opisach programów, które sprawdziliśmy, analiza liczy się z wystawionych dokumentów, a kategorie kosztów nadaje się ręcznie albo wynikają z ksiąg. Firmowid liczy z tego, co faktycznie zapłacono, i kategorie proponuje automatycznie.

| Program | Z czego liczy | Kategorie kosztów | Wynik projektu | Najtańszy plan z analizą |
|---|---|---|---|---|
| Firmowid | opłacone faktury i przelewy z banku | 12, proponuje AI | tak, z kosztów przypisanych do projektu | 0 zł, plan Darmowy |
| Fakturownia | wystawione dokumenty | nadawane ręcznie | nie opisano | Start, 12,49 zł netto |
| inFakt | dokumenty, z podatkami i ZUS | księgowe, AI w planie Plus | nie opisano | Mini, 9,99 zł netto, koszty tylko z KSeF |
| wFirma | dokumenty | nie opisano | nie opisano | pakiet niepodany, cennik od 25 zł netto |
| iFirma | księga przychodów i rozchodów | 6 stałych | tak, dokumenty podpinane ręcznie | wymaga księgowości w serwisie |
| Fakturoza | pulpit z przychodami, kosztami i wynikiem | nadawane ręcznie | nie opisano | 0 zł z limitem 5 kosztów miesięcznie |

Stan na 20.11.2026, według stron producentów, ceny za miesiąc przy płatności rocznej, bez kodów rabatowych: [Fakturownia](https://pomoc.fakturownia.pl/100540679-raporty-przychody-i-wydatki), [inFakt](https://pomoc.infakt.pl/hc/pl/articles/9886759016722-Statystyki), [wFirma](https://pomoc.wfirma.pl/-analizy-ogolne-przychody-i-koszty), [iFirma](https://pomoc.ifirma.pl/pomoc-artykul/raporty/), [Fakturoza](https://fakturoza.pl/funkcje). Fakturoza nie podaje wprost, czy pulpit jest w planie za 0 zł.

## Jak liczy Analiza

| | |
|---|---|
| Przychody | faktury sprzedażowe opłacone przelewem |
| Koszty | faktury kosztowe i przelewy bez faktury, opłacone |
| Kwoty | brutto, w złotych po kursie z dnia |
| Miesiące | tylko domknięte |
| Faktura trafia do miesiąca | według daty sprzedaży |
| Przelewy między własnymi kontami | pomijane |
| Kategorie | 12 kategorii kosztów, podpowiada AI, zatwierdzasz Ty |
| Widoki | Podsumowanie, Trendy, filtr projektu |
| Podatki do zapłaty | nie są liczone |
| Eksport | nie |

Zobacz też: [Bank i dopasowanie przelewów](/funkcje/bank) · [Faktury kosztowe](/funkcje/faktury-kosztowe) · [cennik](/cennik)

## Najczęstsze pytania

### Skąd Analiza bierze dane?
Z opłaconych faktur i z przelewów na podłączonych kontach. Niczego nie wpisujesz ręcznie. Dokładne zasady są w sekcji [Jak liczy Analiza](#jak-liczy-analiza).

### Czy muszę sam przypisywać kategorie?
Nie. Kategorię proponuje AI, a Ty ją zatwierdzasz. Lista jest w sekcji [Kategorie kosztów](#kategorie-kosztow).

### Ile kosztuje Analiza?
Jest w każdym planie, także za 0 zł. Plany różnią się liczbą banków i dostępem przez Claude i ChatGPT, co pokazuje sekcja [Ile to kosztuje](#ile-to-kosztuje).

### Czy Analiza pokazuje rentowność projektu?
Pokazuje wynik projektu: jego przychody minus koszty do niego przypisane. Kosztów wspólnych firmy na projekty nie rozkłada.

### Czy Analiza zastąpi biuro księgowe?
Nie. Kwoty są brutto i bez podatków do zapłaty. To obraz do zarządzania firmą, a nie księgi.

### Kto w firmie widzi Analizę?
Osoby z rolą fakturowanie, księgowość albo admin. Pracownik nie ma do niej dostępu.

### Czy dane można wyeksportować?
Nie. Możesz za to pytać o nie asystenta AI albo Claude i ChatGPT.
