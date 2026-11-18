---
title: "Jak działa dopasowanie przelewów do faktur w Firmowidzie"
description: "Kiedy Firmowid sam łączy przelew z fakturą, co bierze pod uwagę, skąd biorą się propozycje i jak zatwierdzić, cofnąć albo pominąć dopasowanie."
published: 2026-11-18
updated: 2026-11-18
category: bank-i-platnosci
---

Firmowid porównuje każdą nieopłaconą fakturę z przelewami pobranymi z banku i wylicza, na ile do siebie pasują. Przy bardzo wysokiej pewności łączy je sam, przy niższej pokazuje propozycję do zatwierdzenia. Fakturę z powiązanym przelewem traktuje jako opłaconą.

## Co trzeba mieć

- Podłączone konto bankowe z synchronizacją. Jak to zrobić, opisuje instrukcja [Jak podłączyć konto bankowe](/pomoc/podlaczenie-konta-bankowego).
- Rolę „księgowość” albo administratora, żeby zatwierdzać, cofać i pomijać. Rola „fakturowanie” widzi dopasowania bez możliwości zmiany.

## Kiedy program szuka pary

Dopasowanie uruchamia się bez Twojego udziału w trzech sytuacjach:

- gdy pojawia się nowa faktura kosztowa, z KSeF albo z pliku,
- po każdej udanej synchronizacji konta bankowego,
- raz na godzinę dla wszystkich nieopłaconych faktur, sprzedażowych i kosztowych.

## Które przelewy są brane pod uwagę

Program najpierw zawęża listę. Dla danej faktury sprawdza tylko przelewy, które:

| Warunek | Wartość |
|---|---|
| Kierunek | wydatek dla faktury kosztowej, wpływ dla sprzedażowej |
| Data księgowania | od 30 dni przed wystawieniem faktury do 60 dni po terminie płatności |
| Kwota | od 90 do 110% kwoty faktury, po przeliczeniu na złote |
| Stan | przelew nie jest jeszcze z niczym powiązany ani pominięty |

Faktura bez daty wystawienia albo bez terminu płatności nie dostanie żadnej propozycji.

## Co decyduje o ocenie

Każda para faktura i przelew dostaje ocenę od 0 do 100%. Składają się na nią:

- numer faktury w tytule przelewu, to najsilniejsza wskazówka,
- podobieństwo nazwy nadawcy lub odbiorcy do nazwy kontrahenta z faktury,
- różnica kwot,
- odstęp między przelewem a terminem płatności (faktura kosztowa) albo datą wystawienia (faktura sprzedażowa),
- kwota wpisana w tytule przelewu,
- zgodność waluty i numeru rachunku.

W aplikacji ocena ma etykietę „Ocena AI: X% pewności”. Liczy ją model statystyczny o stałych wagach, a nie model językowy, dlatego ta sama para zawsze dostanie ten sam wynik. Przy fakturze w euro opłaconej z rachunku złotowego obie kwoty są przeliczane po kursie z dnia.

## Automat i propozycje

Automat łączy fakturę z przelewem tylko wtedy, gdy ocena przekracza bardzo wysoki próg pewności. Łączy zawsze jeden przelew z jedną fakturą.

Pozostałe pary widzisz jako propozycje. Otwórz fakturę i spójrz na listę „Potencjalne transakcje dla dokumentu”. Przy każdej pozycji jest wskaźnik z kreskami: trzy zielone oznaczają najlepszego kandydata, dwie albo jedna słabsze dopasowanie. Kliknij „Zatwierdź” przy właściwym przelewie.

![„Potencjalne transakcje dla dokumentu” przy fakturze kosztowej](/images/guides/pomoc/kosztowa-sugestie.webp)

To samo zrobisz od strony przelewu. Na stronie transakcji lista nazywa się „Potencjalne faktury dla tej transakcji”.

![Przelew z listą „Potencjalne faktury dla tej transakcji”](/images/guides/pomoc/transakcja-sugestie.webp)

## Gdy propozycji nie ma

Komunikat „Brak rekomendacji” oznacza, że żaden przelew nie zmieścił się w warunkach z tabeli. Najczęstsze powody:

- przelew jeszcze nie dotarł, bo synchronizacja z bankiem odbywa się co drugi dzień,
- klient zapłacił kwotę różną o ponad 10%, na przykład ratę albo kilka faktur naraz,
- płatność przyszła gotówką, kartą albo na rachunek, którego nie podłączyłeś.

W pierwszym przypadku wystarczy poczekać. W drugim kliknij „Poproś Firmowida o pomoc”: otworzy się rozmowa z asystentem, który potrafi powiązać jeden przelew z kilkoma fakturami. W trzecim użyj przycisku „Pomiń”.

## Pomijanie i przywracanie

„Pomiń” oznacza fakturę albo przelew jako rozliczone poza systemem. Tak zamykasz opłaty bankowe, przelewy między własnymi rachunkami, podatki i faktury zapłacone gotówką. Pominięty przelew przestaje pojawiać się w propozycjach. Decyzję cofasz przyciskiem „Przywróć”.

## Cofanie dopasowania

Na stronie faktury ze stanem „Komplet” jest przycisk cofnięcia. Odłącza on wszystkie przelewy powiązane z fakturą. Cofnięcie na stronie przelewu odłącza go od wszystkich faktur. Po odłączeniu obie strony wracają na listy niedopasowanych i znów mogą dostać propozycje. Program nie pamięta odłączonej pary, więc jeśli była bardzo pewna, automat może ją połączyć ponownie przy następnym przeglądzie. Żeby temu zapobiec, od razu połącz fakturę z właściwym przelewem albo oznacz jedną ze stron przyciskiem „Pomiń”. Pominięta faktura albo przelew wypada wtedy ze wszystkich automatycznych dopasowań, nie tylko z tej pary.

## Czego Firmowid tu nie robi

- Nie liczy salda „pozostało do zapłaty”. Faktura z powiązanym przelewem jest opłacona bez względu na kwotę przelewu.
- W interfejsie nie dołączysz drugiego przelewu do opłaconej faktury. Służy do tego asystent, wywoływany przyciskiem „Zapytaj”.
- Nie wskażesz ręcznie przelewu spoza listy propozycji.
- Nie rozpoznaje sam opłat bankowych ani przelewów własnych. Zamykasz je przyciskiem „Pomiń”.

## Jak zwiększyć liczbę automatycznych dopasowań

Z naszego doświadczenia najwięcej daje jedna rzecz: poproś klientów, żeby w tytule przelewu wpisywali pełny numer faktury. Druga to terminy płatności zgodne z tym, jak klienci faktycznie płacą. O numerze KSeF w tytule przelewu od 2027 r. piszemy w [osobnym poradniku](/poradnik/numer-ksef-w-przelewie-2027).

## Powiązane

- [Bank i dopasowanie przelewów do faktur](/funkcje/bank)
- [Jak podłączyć konto bankowe](/pomoc/podlaczenie-konta-bankowego)
- [Program do faktur z dopasowaniem przelewów: import to nie Open Banking](/poradnik/dopasowanie-przelewow-do-faktur)
