---
title: "Wystawianie faktur: VAT, korekty i faktury w walutach"
description: "Faktury VAT, korekty i faktury dwujęzyczne w walutach, wysyłane do KSeF. Jak wystawiamy je w Firmowidzie, co program obsługuje i czego nie."
published: 2026-11-18
updated: 2026-11-18
landing:
  kicker: "Funkcje · Faktury i KSeF"
  note: "faktura prosto do KSeF"
  facts:
    - label: "Rodzaje faktur"
      value: "VAT, bez VAT, zaliczkowa, korekta"
    - label: "Waluty"
      value: "złoty i 32 waluty z tabeli NBP"
    - label: "Kontrahent"
      value: "biała lista VAT i VIES"
---

Wystawianie faktur jest u nas bardzo intuicyjne. Dużo korzystamy z szybkiego wystawiania: kopiujemy fakturę z poprzedniego miesiąca, datę sprzedaży ustawiamy przyciskiem na ostatni dzień ubiegłego miesiąca, a numer faktury pojawia się automatycznie. Teraz działa to naprawdę dobrze. Pomaga nam też asystent w aplikacji, bo można go poprosić, żeby przygotował szkic faktury.

![Faktura sprzedażowa z numerem KSeF i podglądem dokumentu](/images/guides/funkcje/faktura-sprzedazowa.webp)

## Połączenie z KSeF

Połączyliśmy się tokenem. Było całkiem szybko, z dobrą instrukcją, jak ten token wygenerować i gdzie go znaleźć. Myślę, że trwało to około 3 minut.

Token działa w KSeF tylko do 1 stycznia 2027 r., dlatego Firmowid pozwala połączyć się także Profilem Zaufanym albo certyfikatem KSeF. Przy Profilu Zaufanym certyfikat powstaje sam. Krok po kroku: [Jak połączyć Firmowid z KSeF](/pomoc/polaczenie-z-ksef).

## Korekty

Pamiętam korektę faktury, która była problematyczna, ale udało się ją naprawić. Faktury z numerem KSeF nie da się edytować, wystawia się korektę. Firmowid pokazuje ją pod fakturą pierwotną, z tabelami przed i po korekcie.

## Klienci z zagranicy

Wystawiamy faktury w kilku walutach, z odwrotnym obciążeniem, od razu jako dwujęzyczne: po polsku i obok po angielsku. To wygodne dla klientów i dla naszego biura księgowego. Klienci chwalą ładny wygląd faktur i czytelność.

## Jak faktura trafia do klienta

Klient za granicą dostaje e-mail i link, z którego wygodnie pobierze PDF. W Polsce faktura trafia oczywiście jeszcze do KSeF. Gdy zaznaczysz wysyłkę e-mailem, Firmowid co tydzień przypomni klientowi o fakturze po terminie, dopóki nie przyjdzie przelew.

## Najważniejsze dane

| | |
|---|---|
| Rodzaje faktur | VAT, bez VAT przy zwolnieniu, zaliczkowa, korekta |
| Stawki VAT | 23%, 8%, 5%, zw, odwrotne obciążenie, np |
| Waluty | złoty i 32 waluty z tabeli NBP, kurs NBP |
| Faktura dwujęzyczna | tak, dla nabywcy spoza Polski |
| Sprawdzanie kontrahenta | biała lista VAT, VIES dla firm z UE |
| Pobieranie faktur z KSeF | co 2 godziny, na start 30 dni wstecz |
| Jednostki | szt., godz. |
| Pro forma, faktury cykliczne, faktura końcowa | nie |
| UPO, tryb offline | nie |

Plany i limity: [cennik](/cennik).

Zobacz też: [Pobieranie faktur z KSeF](/pomoc/pobieranie-faktur-z-ksef) · [Pierwsza faktura w KSeF krok po kroku](/poradnik/pierwsza-faktura-ksef) · [Faktura dla firmy z UE w KSeF](/poradnik/faktura-dla-firmy-z-ue-ksef) · [Tryb offline w KSeF](/poradnik/tryb-offline-ksef)

## Najczęstsze pytania

### Czy fakturę wysłaną do KSeF można poprawić?
Nie. Wystawiasz korektę.

### Co, jeśli KSeF nie odpowiada?
Faktura czeka w statusie wysyłania, a Firmowid ponawia próbę. Trybu offline nie obsługuje.

### Czy wystawię fakturę dla osoby prywatnej?
Tak, w aplikacji. Przez Claude i ChatGPT tylko dla firm.
