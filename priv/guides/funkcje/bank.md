---
title: "Program do faktur z integracją bankową i dopasowaniem przelewów"
description: "Firmowid pobiera przelewy z banku i sam przypina je do faktur. Jak to wygląda u nas na co dzień, co obsługuje i czego nie robi."
published: 2026-11-18
updated: 2026-11-19
landing:
  kicker: "Funkcje · Bank"
  note: "przelew sam trafia do faktury"
  author: franek
  facts:
    - label: "Cena"
      value: "0 zł z jednym bankiem"
    - label: "Banki"
      value: "29 banków i fintechów"
    - label: "Dopasowanie"
      value: "samo, bez wgrywania plików"
  match:
    - payer: "Północny Kod"
      date: "14.11"
      amount: "14 892,00 zł"
      invoice: "FV 7/11/2026"
      status: "opłacona"
    - payer: "Aurora Retail"
      date: "13.11"
      amount: "6 150,00 zł"
      invoice: "FV 5/11/2026"
      status: "opłacona"
    - payer: "Serwerownia Kopernik"
      date: "5.11"
      amount: "-2 400,00 zł"
      invoice: "SK/11/2026"
      status: "opłacona"
    - payer: "Studio Lino"
      date: "16.11"
      amount: "-300,00 zł"
      invoice: "Usługi graficzne"
      status: "propozycja, zatwierdź"
      suggested: true
---

Wcześniej braliśmy wyciąg z banku i długopisem skreślaliśmy każdy przelew, mając fakturę w ręce albo na komputerze. Było to bardzo czasochłonne. Nie kontrolowaliśmy, czy kontrahent już przelał pieniądze i ile dni zostało mu do terminu. Teraz przelewy same przypinają się do faktur, a gdy Firmowid czegoś nie przypnie, proszę asystenta o pomoc.

## Jak to działa

Bank podłączasz raz i trwa to kilkanaście sekund. Wybierasz go z listy, logujesz się na stronie banku i tam dajesz zgodę. Od tej chwili Firmowid sam pobiera przelewy i szuka do nich faktur.

| Krok | Gdzie | Co | Ekran |
|---|---|---|---|
| Wybierz bank | Konta bankowe | kafel banku, logowanie i zgoda na stronie banku | ![Strona „Dodaj konto bankowe” z kaflami banków](/images/guides/pomoc/bank-2-wybor-banku.webp) |
| Przelewy przychodzą same | w tle | historia do 90 dni wstecz, potem nowe przelewy co drugi dzień | ![Przelew z proponowaną fakturą i przyciskiem „Zatwierdź”](/images/guides/pomoc/transakcja-sugestie.webp) |
| Zatwierdź albo pomiń | strona faktury | pewne pary łączą się same, przy pozostałych klikasz „Zatwierdź” | ![Faktura kosztowa z proponowanym przelewem i przyciskiem „Zatwierdź”](/images/guides/funkcje/kosztowa-sugestie.webp) |

Krok po kroku: [Jak podłączyć konto bankowe](/pomoc/podlaczenie-konta-bankowego).

## Banki i waluty

![PKO Bank Polski](/images/landing/banks/pkobp.png) ![mBank](/images/landing/banks/mbank.png) ![Pekao](/images/landing/banks/pekao.png) ![ING](/images/landing/banks/ing.png) ![Revolut](/images/landing/banks/revolut.png) ![Wise](/images/landing/banks/wise.png)

- PKO Bank Polski
- Pekao
- mBank
- ING
- Alior Bank
- Bank Millennium
- BNP Paribas
- Nest Bank
- Erste Bank Polska
- Inteligo
- Revolut
- Wise
- Stripe
- PayPal
- Paysera
- N26
- Airwallex
- Finom

Możesz podłączyć kilka banków, także rachunki walutowe. Przelewy między własnymi rachunkami nie trafiają do analizy.

Konto w banku spoza listy dodasz ręcznie po numerze IBAN. Wybierzesz je na fakturze, ale przelewów z niego program nie pobierze.

## Na co dzień

Na liście faktur widać, co masz zapłacić i kto ma zapłacić Tobie. O nowej fakturze w KSeF Firmowid powiadamia mailem. Przy każdej fakturze jest informacja, czy przelew już do niej trafił, czy czeka propozycja, czy pary jeszcze brakuje.

**Kiedy coś nie pasuje.** Przelew bez pary dostaje listę możliwych faktur. Zatwierdzasz jedną z nich, pomijasz przelew albo prosisz asystenta o pomoc, na przykład przy wpłacie za kilka faktur. Więcej: [Jak działa dopasowanie przelewów](/pomoc/dopasowanie-przelewow).

**Biuro księgowe.** Opisane faktury pobierasz w jednej paczce ZIP i wysyłasz do biura. Jak ją przygotować: [Paczka dokumentów dla biura księgowego](/pomoc/paczka-dla-biura-ksiegowego).

## Ile to kosztuje

| Plan | Banki z pobieraniem przelewów | Cena |
|---|---|---|
| Darmowy | 1 | 0 zł |
| Przedsiębiorca | 3 | 29 zł netto miesięcznie |
| Firma | bez limitu | 149 zł netto miesięcznie |

Limit liczy banki, a nie rachunki. Konta dodane ręcznie się do niego nie wliczają.

## Porównanie z innymi programami

W cennikach, które sprawdziliśmy, plan za 0 zł daje zwykle wgranie pliku z wyciągiem albo obsługę jednego banku. W Firmowidzie w planie za 0 zł jest stałe połączenie z jednym z 29 banków i fintechów.

| Program | Skąd biorą się przelewy | Dopasowanie do faktur | Bank w planie za 0 zł | Najtańszy plan z bankiem |
|---|---|---|---|---|
| Firmowid | połączenie z bankiem | automatyczne, reszta jako propozycje | tak, 1 bank | 0 zł, 3 banki za 29 zł netto |
| Fakturownia | połączenie z bankiem albo plik | automatyczne | nie | Standard, 28,46 zł netto |
| Mobilna Faktura | połączenie z bankiem albo plik | automatyczne | nie | Max, 23,74 zł |
| iFirma | połączenie z bankiem, przelewy pobierasz ręcznie | propozycje | nie | Księgowość Internetowa, 49 zł netto |
| wFirma | połączenie z bankiem albo plik | automatyczne przy pełnej zgodności | nie | Księgowość, 60 zł netto |
| Fakturoza | plik MT940 | automatyczne, reszta jako propozycje | 1 wyciąg miesięcznie | 0 zł, bez limitu 31,99 zł netto |
| ING Księgowość | tylko konta w ING | propozycje | tak, dla klientów ING | 0 zł |
| mBank mOrganizer finansów | tylko konto firmowe mBanku | automatyczne | nie | Optymalny, 45 zł netto |

Stan na 19.11.2026, według stron producentów, ceny za miesiąc przy płatności rocznej, jeśli producent ją podaje: [Fakturownia](https://fakturownia.pl/cennik), [Mobilna Faktura](https://mobilna-faktura.pl/cennik/), [iFirma](https://pomoc.ifirma.pl/pomoc-artykul/jak-polaczyc-konto-bankowe-z-serwisem-ifirma/), [wFirma](https://wfirma.pl/cennik), [Fakturoza](https://fakturoza.pl/funkcje/dopasowanie-wplat-mt940), [ING Księgowość](https://www.ingksiegowosc.pl/fakturowanie/integracja-z-bankowoscia), [mBank](https://www.mbank.pl/firmy/ksiegowosc/morganizer-finansow/).

## Bezpieczeństwo

| | |
|---|---|
| Tylko odczyt | Firmowid widzi salda i historię rachunku. Przelewu nie zleci. |
| Hasło zostaje w banku | Logujesz się na stronie banku i tam dajesz zgodę. |
| Dostawca z zezwoleniem | GoCardless SAS, zezwolenie francuskiego nadzoru ACPR, usługa dostępu do rachunku (AISP) z dyrektywy PSD2, certyfikat ISO 27001 od 2016 r. |
| Zgoda na 90 dni | Potem klikasz „Odnów zgodę”. Historia i dopasowania zostają. |

## Najważniejsze dane

| | |
|---|---|
| Historia przy pierwszym połączeniu | do 90 dni |
| Nowe przelewy | co drugi dzień |
| Przelewy między własnymi kontami | pomijane w analizie |
| Import wyciągu MT940 lub CSV | nie |
| Zlecanie przelewów z Firmowida | nie |

Zobacz też: [Revolut i Wise w programie do faktur z KSeF](/poradnik/revolut-wise-program-do-faktur) · [Program do faktur z dopasowaniem przelewów](/poradnik/dopasowanie-przelewow-do-faktur) · [Numer KSeF w tytule przelewu od 2027 r.](/poradnik/numer-ksef-w-przelewie-2027)

## Najczęstsze pytania

### Czy Firmowid widzi hasło do banku?
Nie. Logujesz się na stronie banku.

### Co się dzieje po 90 dniach?
W Skrzynce pojawia się „synchronizacja wstrzymana” z przyciskiem „Odnów zgodę”. Historia i dopasowania zostają.

### Ile kosztuje połączenie z bankiem?
Jeden bank jest w planie za 0 zł. Trzy banki obejmuje plan Przedsiębiorca za 29 zł netto miesięcznie, a plan Firma za 149 zł netto nie ma limitu.

### Czy obsługujecie mój bank?
Firmowid łączy się z 29 bankami i fintechami, w tym z PKO Bankiem Polskim, Pekao, mBankiem, ING, Revolutem i Wise. Listę znajdziesz w sekcji [Banki i waluty](#banki-i-waluty).

### Czy dopasowanie da się cofnąć?
Tak, na stronie faktury albo przelewu.

### Co z jedną wpłatą za kilka faktur?
Na stronie faktury łączysz jeden przelew. Wpłatę za kilka faktur albo raty rozpisuje asystent.
