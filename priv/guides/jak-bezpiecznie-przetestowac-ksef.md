---
title: "Jak przetestować KSeF przed pierwszą prawdziwą fakturą"
description: "KSeF ma środowisko testowe, Demo i produkcyjne. W testowym wszystko jest fikcyjne, w Demo logujesz się prawdziwymi danymi. Jak przejść próbę bez skutków."
published: 2026-10-28
updated: 2026-11-23
category: ksef-w-praktyce
---

KSeF ma trzy środowiska: testowe, przedprodukcyjne Demo i produkcyjne. Do nauki używaj dwóch pierwszych.

W środowisku testowym wszystko może być fikcyjne, łącznie z danymi logowania. W Demo logujesz się prawdziwymi danymi i masz swoje rzeczywiste uprawnienia, ale dane na fakturze nadal wpisujesz fikcyjne. Działania w środowisku testowym nie mają skutków prawnych, a faktury z Demo nie mają skutków podatkowych. Dane z obu środowisk są co jakiś czas usuwane.

## Które środowisko do czego

- **Testowe:** żeby poznać formularz i przejść cały proces bez logowania się jako firma.
- **Demo:** żeby przed pierwszą fakturą sprawdzić, czy działa twoje logowanie i nadane uprawnienia.
- **Produkcyjne:** tylko do prawdziwych faktur. Nie wysyłaj tam niczego na próbę.

![Trzy środowiska KSeF. Testowe: wszystko fikcyjne, także dane logowania, bez skutków prawnych. Demo: prawdziwe logowanie i uprawnienia, ale fikcyjne dane na fakturze, bez skutków podatkowych. Produkcyjne: tylko prawdziwe faktury, ze skutkami prawnymi i podatkowymi. Dane z testowego i Demo są co jakiś czas usuwane.](/images/guides/srodowiska-ksef-testowe-demo-produkcyjne.webp)

## Ile środowisk jest dostępnych w KSeF 2.0?

| Środowisko | Dane logowania | Dane na fakturze | Skutki |
|---|---|---|---|
| Testowe | fikcyjne | fikcyjne | brak skutków prawnych |
| Demo | prawdziwe | fikcyjne | brak skutków podatkowych |
| Produkcyjne | prawdziwe | prawdziwe | prawne i podatkowe |

O środowisku testowym ministerstwo pisze: „W środowisku testowym użytkownik może posługiwać się dowolnymi, fikcyjnymi danymi. Żadna z czynności nie niesie za sobą skutków prawnych”. O Demo: „Wystawianie faktur na środowisku przedprodukcyjnym nie niesie ze sobą skutków podatkowych”.

## Od kiedy można testować KSeF 2.0?

| Data | Co ruszyło |
|---|---|
| 30 września 2025 r. | środowisko testowe API |
| 15 października 2025 r. | środowisko Demo API |
| 3 listopada 2025 r. | testowa Aplikacja Podatnika |
| 15 listopada 2025 r. | Aplikacja Podatnika w wersji Demo |
| 1 lutego 2026 r. | środowisko produkcyjne |

Obie wersje próbne działają dalej obok produkcyjnej. Strona Aplikacji Podatnika KSeF 2.0 ma do nich osobne wejścia, opisane jako wersja testowa i wersja przedprodukcyjna (Demo).

## Jak zalogować się do KSeF demo?

Prawdziwymi danymi. Ministerstwo wyjaśnia: „Do środowiska przedprodukcyjnego, (w odróżnieniu do środowiska testowego) zalogujesz się za pomocą prawdziwych danych uwierzytelniających (np. NIP) zgodnych z rejestrem informacji o właścicielach firm”. Na stronie wersji testowej MF udostępnia osobny plik „Instrukcja uwierzytelnienia w Aplikacji Podatnika KSeF 2.0 wersja testowa”.

## Co da się sprawdzić w wersji testowej?

| Funkcja | W wersji testowej i Demo |
|---|---|
| Faktury i korekty w strukturze FA(3) | tak |
| Pobranie faktury jako XML, HTML albo PDF | tak |
| UPO dla jednej albo wielu faktur | tak |
| Kody QR i dostęp anonimowy do faktury | tak |
| Tokeny, uprawnienia, wnioski o certyfikat | tak |
| Faktury wystawione w trybie offline | dostęp |

## Próba krok po kroku

1. Otwórz testową wersję Aplikacji Podatnika KSeF 2.0.
2. Wpisz fikcyjne dane sprzedawcy, nabywcy i transakcji.
3. Wystaw i wyślij fakturę, sprawdź status, pobierz dokument i UPO (Urzędowe Poświadczenie Odbioru).
4. W Demo sprawdź osobno logowanie i uprawnienia, nadal bez danych prawdziwego kontrahenta.

Po udanej próbie prawdziwe faktury wyślesz z Aplikacji Podatnika KSeF albo z [programu do KSeF](/ksef), na przykład z naszego Firmowida. Gdy się [zarejestrujesz](/zarejestruj), dowolny plan Firmowida działa za darmo przez 60 dni, więc płatne funkcje sprawdzisz, zanim zdecydujesz o abonamencie.

## Czy testy zmieniają coś w prawdziwym KSeF?

Na stronie wersji Demo ministerstwo pisze, że zarządzanie uprawnieniami i wnioski o certyfikaty „ma wyłącznie charakter testowy”, a dalej: „Dane w wersji przedprodukcyjnej (Demo) Aplikacji Podatnika będą okresowo usuwane”.

## Gdy testowa aplikacja nie działa

Na forum gofin.pl ktoś pytał: „czy próbował, ktoś z Państwa otworzyć aplikację testową KSeF z MF? Próbowałam otworzyć u siebie i niestety, się nie da”. Inna osoba pisała o Demo: „Nie mogę się zalogować do KSEF 2.0 wersja przedprodukcyjna (demo), co najdziwniejsze w tamtym tygodniu mogłam”.

MF zbiera takie zgłoszenia przez formularz zgłoszeniowy KSeF i infolinię: 22 330 03 30 z komórki i 801 055 055 z telefonu stacjonarnego, w dni robocze od 8:00 do 18:00.

## Testy a Firmowid

Firmowid, nasz program, wysyła faktury do produkcyjnego KSeF. Środowiska testowego na firmowid.pl nie ma. Bez wysyłki działa przycisk „Zapisz wersję roboczą”.

## XML i PDF

Podręcznik MF ujmuje to jednym zdaniem: „Fakturą ustrukturyzowaną z założenia jest plik XML”. Faktura w KSeF to plik XML według schematu FA(3). PDF jest tylko jej czytelną wersją i nie zastępuje XML-a. Więcej w poradniku [co to jest KSeF i e-faktura](/poradnik/co-to-jest-ksef-i-e-faktura), a całą drogę na produkcji opisuje [pierwsza faktura w KSeF](/poradnik/pierwsza-faktura-ksef).

## Źródła

- [MF: wersja testowa Aplikacji Podatnika KSeF 2.0](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-20/aplikacja-podatnika-ksef-20-wersja-testowa/), dostęp 23.11.2026.
- [MF: wersja przedprodukcyjna Demo](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-20/aplikacja-podatnika-ksef-20-wersja-przedprodukcyjna-demo/), dostęp 23.11.2026.
- [MF: Podręcznik KSeF 2.0, cz. I](https://ksef.podatki.gov.pl/media/dmrfdixs/podrecznik-ksef-20-cz-i-rozpoczecie-korzystania-z-ksef-06082026.pdf) (harmonogram uruchamiania środowisk), dostęp 23.11.2026.
- [MF: Podręcznik KSeF 2.0, cz. II](https://ksef.podatki.gov.pl/media/rronoxyt/podrecznik-ksef-20-cz-ii-wystawianie-i-otrzymywanie-faktur-w-ksef-06082026.pdf) (rozdział 5.3), dostęp 23.11.2026.
- [MF: faktura ustrukturyzowana i FA(3)](https://ksef.podatki.gov.pl/informacje-ogolne-ksef-20/faktura-ustrukturyzowana-i-struktura-logiczna-fa/), dostęp 9.10.2026.
