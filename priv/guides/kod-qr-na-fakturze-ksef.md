---
title: "Kod QR na fakturze KSeF: kiedy jest wymagany i co zawiera"
description: "Kod QR jest wymagany, gdy fakturę z KSeF przekazujesz albo pokazujesz poza systemem. Faktura online ma jeden kod z numerem KSeF, faktura offline dwa."
published: 2026-11-25
updated: 2026-11-25
category: ksef-w-praktyce
---

Kod QR nie jest częścią faktury w KSeF. Pojawia się dopiero na wydruku albo w pliku PDF. Podręcznik Ministerstwa Finansów ujmuje to tak: „Posługiwanie się fakturą ustrukturyzowaną poza KSeF wymaga również opatrzenia jej kodem QR (z oznaczeniem numeru KSeF faktury)”.

| Faktura | Kody QR | Napis pod kodem |
|---|---|---|
| Online, z numerem KSeF | jeden | numer KSeF |
| Offline, jeszcze nieprzesłana do KSeF | dwa | „OFFLINE” i „CERTYFIKAT” |
| Offline, już z numerem KSeF | jeden | numer KSeF |
| Plik XML pobrany z KSeF przez nabywcę | brak | nie dotyczy |

## Czy każda faktura w KSeF musi mieć kod QR?

Nie. Sama faktura ustrukturyzowana to plik XML i kodu w nim nie ma. Obowiązek dotyczy faktury wydanej albo użytej poza systemem. Podręcznik mówi: „Oznaczenie faktury kodem weryfikującym powinno następować każdorazowo podczas użycia jej poza KSeF lub udostępnienia nabywcy poza systemem”.

Krajowego nabywcy z NIP zwykle to nie dotyczy. W podręczniku czytamy: „Zasadą jest, że faktura jest otrzymywana przez nabywcę krajowego, posiadającego identyfikator podatkowy NIP, w transakcjach B2B, przy użyciu systemu”. Kod staje się potrzebny, gdy sprzedawca mimo to wysyła mu PDF, oraz zawsze wtedy, gdy nabywcą jest podmiot zagraniczny, konsument albo ktoś bez NIP.

## Dlaczego na fakturze KSeF nie ma kodu QR?

Bo kodu nie nadaje KSeF, tylko program, w którym powstaje wydruk. Podręcznik wyjaśnia: „Generowanie kodów odbywa się lokalnie na poziomie danego narzędzia do wystawiania faktur, w oparciu o dane zawarte w wystawionej fakturze”.

Z forum jednego z programów do faktur, luty 2026 r.: „Generuje się numer KSeF i ten numer od razu drukuje się na Fakturze. Brakuje tylko kodu QR na fakturze”. Z innego wątku: „Nie wiem czy trzeba to gdzieś włączyć czy powinno się pojawić samo”. I pytanie o własny szablon: „Ale ja chciałbym, żeby na moim wzorcu własnym wyświetlały się kody qr i ksef”.

Bezpłatne narzędzia ministerstwa też dodają kod. Według podręcznika jest to możliwe „przy użyciu komercyjnych programów do e-fakturowania lub za pomocą bezpłatnych aplikacji udostępnianych przez MF”.

## Co zawiera kod QR na fakturze?

Kod jest zapisem linku. MF nazywa go KOD I i wymienia jego składniki.

| Składnik | Skąd pochodzi |
|---|---|
| Adres usługi weryfikacji | specyfikacja KSeF |
| Data wystawienia faktury | pole P_1 |
| NIP sprzedawcy | dane wystawcy |
| Wyróżnik faktury | wyliczany z pliku faktury |

Kwot ani danych nabywcy w kodzie nie ma. Drugi kod, z napisem „CERTYFIKAT”, potwierdza wystawcę faktury offline. Podręcznik zastrzega: „Do wygenerowania tego kodu niezbędne jest posiadanie certyfikatu KSeF (typu 2)”. Różnice między certyfikatami opisuje tekst [certyfikat KSeF typu 1 i 2](/poradnik/certyfikat-ksef-typ-1-i-2).

## Co widzi nabywca po zeskanowaniu kodu?

Podręcznik opisuje to krok po kroku: „Po zeskanowaniu kodu QR/kliknięciu w link następuje odczyt informacji zawartych w kodzie i są wyświetlone podstawowe dane identyfikujące tę fakturę wraz z informacją czy dokument znajduje się w KSeF”. Logowanie nie jest potrzebne. Do pobrania całej faktury system prosi o trzy dane.

| Dana dostępowa | Pole faktury |
|---|---|
| Numer faktury nadany przez sprzedawcę | P_2 |
| NIP albo inny identyfikator nabywcy, albo informacja o jego braku | Podmiot2 |
| Kwota należności ogółem | P_15 |

Ministerstwo nazywa to dostępem dwuetapowym. Jest on czymś innym niż dostęp anonimowy bez kodu, opisany w tekście [kontrahent nie widzi faktury w KSeF](/poradnik/kontrahent-nie-widzi-faktury-ksef).

## Kod QR na fakturze dla klienta zagranicznego

O fakturze dla klienta spoza UE ministerstwo pisze: „Taka faktura ma kod QR z numerem KSeF, dzięki któremu łatwo ją zweryfikować”. W podręczniku jest przykład sprzedawcy, który wydał zagranicznemu nabywcy fakturę na papierze: „Nabywca może zeskanować kod QR i sprawdzić czy sprzedawca faktycznie przesłał fakturę do KSeF”.

Dwa kody mają jeszcze potwierdzenia transakcji, wydawane klientowi, zanim faktura dostanie numer KSeF. MF zaznacza: „Potwierdzenie transakcji to propozycja biznesowa”. Nad pierwszym kodem jest napis „sprawdź fakturę w KSeF”, nad drugim „zweryfikuj wystawcę faktury”.

## Gdy kodu nie da się umieścić na fakturze

Firmy, które wymieniają faktury jako pliki danych, mogą przesłać kod albo link osobno. Podręcznik tłumaczy, skąd ten wyjątek: „Rozwiązanie to stanowi efekt wsłuchania się w głos rynku”. Obowiązek zostaje, zmienia się miejsce: do pliku trzeba dołączyć kod lub link ze stosownym napisem, „a niekoniecznie bezpośrednie opatrzenie tym kodem lub linkiem samej faktury”.

## Kod QR w Firmowidzie

[Firmowid](/ksef), nasz program, drukuje kod na każdej fakturze z numerem KSeF. Niczego się nie włącza.

Pod kodem jest podpis „Sprawdź w KSeF”, na fakturach zagranicznych także „View in KSeF”. Klient, który dostał link do faktury, ma na jej stronie przycisk „Zobacz w KSeF”.

![Faktura online z numerem KSeF ma jeden kod QR z numerem KSeF pod kodem. Faktura offline, jeszcze nieprzesłana do KSeF, ma dwa kody z napisami OFFLINE i CERTYFIKAT, a po nadaniu numeru KSeF jeden. Plik XML pobrany z KSeF przez nabywcę kodu nie ma. Kod dodaje program do faktur, a do drugiego kodu potrzebny jest certyfikat KSeF typu 2.](/images/guides/kod-qr-faktura-ksef-ile-kodow.webp)

## Źródła

- [MF: Podręcznik KSeF 2.0, cz. II, rozdziały 1.6 i 5.3 do 5.5](https://ksef.podatki.gov.pl/media/rronoxyt/podrecznik-ksef-20-cz-ii-wystawianie-i-otrzymywanie-faktur-w-ksef-06082026.pdf) (wersja z sierpnia 2026 r.), dostęp 23.11.2026.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/) (wersja z 10.11.2026), dostęp 23.11.2026.

*To informacja ogólna, nie porada podatkowa.*
