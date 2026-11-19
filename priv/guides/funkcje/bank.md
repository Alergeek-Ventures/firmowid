---
title: "Program do faktur z integracją bankową i dopasowaniem przelewów"
description: "Firmowid pobiera przelewy z banku przez GoCardless i sam przypina je do faktur. Jak to wygląda u nas na co dzień, co obsługuje i czego nie robi."
published: 2026-11-18
updated: 2026-11-18
landing:
  kicker: "Funkcje · Bank"
  note: "przelewy same przypinają się do faktur"
  facts:
    - label: "Połączenie"
      value: "przez GoCardless"
    - label: "Nowe przelewy"
      value: "co drugi dzień"
    - label: "Zgoda w banku"
      value: "90 dni, potem odnowienie"
---

Wcześniej braliśmy wyciąg z banku i długopisem skreślaliśmy każdy przelew, mając fakturę w ręce albo na komputerze. Było to bardzo czasochłonne. Nie kontrolowaliśmy, czy kontrahent już przelał pieniądze i ile dni zostało mu do terminu. Teraz przelewy same przypinają się do faktur, a gdy Firmowid czegoś nie przypnie, proszę asystenta o pomoc.

![Lista faktur ze statusem płatności](/images/guides/funkcje/faktury-lista.webp)

## Podłączenie banku

Wszystko trwało kilkanaście sekund i było bardzo proste. Wybierasz bank z listy, logujesz się na jego stronie i tam dajesz zgodę. Połączenie idzie przez GoCardless, dla nas to gwarancja bezpieczeństwa.

GoCardless SAS ma zezwolenie francuskiego nadzoru ACPR i w Unii działa jako dostawca usługi dostępu do informacji o rachunku (AISP) z dyrektywy PSD2. Historię rachunku pobiera przez API banku, a nie przez logowanie na Twoje hasło. Od 2016 r. ma certyfikat ISO 27001.

Krok po kroku: [Jak podłączyć konto bankowe](/pomoc/podlaczenie-konta-bankowego).

## Na co dzień

Widzę, co mam zapłacić i kto ma zapłacić mnie. Dostaję maile z nową fakturą w KSeF, widzę, co się przyporządkowało i gdzie brakuje faktury. Faktur zwykle nie opłacam w Firmowidzie. Następnego dnia albo po kilku dniach patrzę, co się przyporządkowało, i to mi nie przeszkadza.

![Faktura kosztowa z proponowanym przelewem i przyciskiem „Zatwierdź”](/images/guides/funkcje/kosztowa-sugestie.webp)

## Kiedy coś nie pasuje

Długo mieliśmy problem z wieloma przelewami od jednego kontrahenta, który wystawiał łączną fakturę na wszystkie. Trochę czasu zajęło, zanim Firmowid nauczył się je grupować i przyporządkowywać.

Więcej: [Jak działa dopasowanie przelewów](/pomoc/dopasowanie-przelewow).

## Kilka banków i waluty

Mamy konta w dwóch bankach, w tym walutowe. Firmowid dobrze radzi sobie z przelewami między naszymi kontami i nie bierze ich pod uwagę w analizie.

## Biuro księgowe

Dostaje od nas opisane faktury w paczce ZIP. Jak ją przygotować: [Paczka dokumentów dla biura księgowego](/pomoc/paczka-dla-biura-ksiegowego).

## Najważniejsze dane

| | |
|---|---|
| Zgoda w banku | 90 dni, potem „Odnów zgodę” |
| Historia przy pierwszym połączeniu | do 90 dni |
| Nowe przelewy | co drugi dzień |
| Import wyciągu MT940 lub CSV | nie |
| Zlecanie przelewów z Firmowida | nie |
| Polskie banki | PKO Bank Polski, Pekao, mBank, ING, Alior Bank, Bank Millennium, BNP Paribas, Nest Bank, Erste Bank Polska, Inteligo |
| Fintechy | Revolut, Wise, Stripe, PayPal, Paysera, N26, Airwallex, Finom |

Plany i limity: [cennik](/cennik).

Zobacz też: [Revolut i Wise w programie do faktur z KSeF](/poradnik/revolut-wise-program-do-faktur) · [Program do faktur z dopasowaniem przelewów](/poradnik/dopasowanie-przelewow-do-faktur)

## Najczęstsze pytania

### Czy Firmowid widzi hasło do banku?
Nie. Logujesz się na stronie banku.

### Co się dzieje po 90 dniach?
W Skrzynce pojawia się „synchronizacja wstrzymana” z przyciskiem „Odnów zgodę”. Historia i dopasowania zostają.

### Czy dopasowanie da się cofnąć?
Tak, na stronie faktury albo przelewu.

### Jedna wpłata za kilka faktur?
Na stronie faktury łączysz jeden przelew. Wpłatę za kilka faktur albo raty rozpisuje asystent.
