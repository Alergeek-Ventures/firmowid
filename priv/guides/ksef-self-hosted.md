---
title: "KSeF self-hosted: czy własny serwer jest bezpieczniejszy?"
description: "Porównaj KSeF self-hosted z chmurą i programem desktopowym. Sprawdź kopie, aktualizacje, dostęp użytkowników i koszty utrzymania."
published: 2026-11-07
updated: 2026-11-07
category: ai-api-i-open-source
---

O tym, jak bezpiecznie przetestować KSeF, pisaliśmy już [w osobnym poradniku](/poradnik/jak-bezpiecznie-przetestowac-ksef). Przy instalacji self-hosted do tej próby dochodzi odtworzenie bazy z kopii na innym serwerze. CISA zaleca przechowywanie kopii oddzielnie od systemu, którego dotyczą. Aktualizacje aplikacji, certyfikat TLS i konta użytkowników obsługuje wtedy administrator firmy. Dotyczy to również naszego Firmowida, którego kod na licencji AGPL-3.0 można uruchomić na własnym serwerze.

## Trzy sposoby przechowywania danych

| Model | Gdzie działa program | Kto robi aktualizacje i kopie | Typowe zastosowanie |
|---|---|---|---|
| chmura dostawcy | infrastruktura dostawcy | dostawca | firma bez własnego administratora |
| self-hosting | własny serwer albo wybrany VPS | firma lub jej administrator | firma wymagająca kontroli nad serwerem i wdrożeniem |
| program desktopowy | jeden komputer | użytkownik tego komputera | praca z jednego stanowiska |

![Chmura dostawcy, self-hosting i program desktopowy: gdzie działa program, kto robi aktualizacje i kopie zapasowe oraz dla kogo jest każdy model.](/images/guides/ksef-self-hosted-chmura-czy-wlasny-serwer.webp)
*Na własnym serwerze aktualizacje i kopie robi firma albo jej administrator.*

## Kontrola przed uruchomieniem self-hostingu

1. Włącz automatyczne aktualizacje systemu operacyjnego albo wyznacz ich stały termin.
2. Ogranicz panel administracyjny do osób, które go potrzebują.
3. Włącz uwierzytelnianie wieloskładnikowe, jeśli program je obsługuje.
4. Szyfruj połączenie certyfikatem TLS.
5. Rób kopię bazy poza serwerem produkcyjnym.
6. Odtwórz kopię na osobnym środowisku i zapisz czas odtworzenia.
7. Ustal, kto reaguje po nieudanej wysyłce do KSeF.
8. Sprawdź dziennik logowań i zmian uprawnień.

## Kiedy własny serwer ma sens

| Sytuacja | Decyzja do rozważenia |
|---|---|
| masz administratora i procedurę kopii | self-hosting daje kontrolę nad infrastrukturą |
| klient wymaga określonego miejsca przetwarzania danych | porównaj wymaganie z dokumentacją programu i hostingu |
| nie masz osoby odpowiedzialnej za aktualizacje | wybierz usługę hostowaną albo zleć utrzymanie |
| chcesz tylko wystawiać i odbierać kilka faktur | sprawdź bezpłatną Aplikację Podatnika KSeF 2.0 |
| program ma działać tylko na jednym komputerze | rozważ program desktopowy zamiast serwera |

## Koszt, którego nie ma w cenniku licencji

- serwer lub VPS;
- domenę i certyfikat;
- kopie zapasowe poza głównym serwerem;
- monitoring;
- czas aktualizacji programu i systemu;
- próbne odtworzenie bazy;
- obsługę awarii poza godzinami pracy.

## Firmowid na własnym serwerze

| Element | Stan |
|---|---|
| kod | AGPL-3.0, publiczne repozytorium |
| sposób działania | aplikacja webowa w Phoenix LiveView |
| KSeF | wystawianie, wysyłanie, ponowienie wysyłki, PDF, numer KSeF, korekty i import faktur kosztowych |
| bank | Open Banking przez GoCardless i automatyczne dopasowanie transakcji do faktur |
| czas pracy | ewidencja według projektu i pracownika |
| ograniczenia publicznego kodu | brak delegacji oraz bety analiz marży i rentowności dostępnych w aplikacji hostowanej |
| utrzymanie self-hostingu | po stronie użytkownika |

## Test przed przeniesieniem prawdziwych faktur

1. Uruchom osobne środowisko testowe.
2. Dodaj użytkownika z ograniczonymi uprawnieniami.
3. Wystaw i wyślij fakturę testową.
4. Pobierz dokument oraz numer KSeF.
5. Wykonaj korektę.
6. Zrób kopię bazy.
7. Zainstaluj aktualizację.
8. Odtwórz bazę z kopii.
9. Usuń dostęp osobie testowej.

## Dalsze czytanie

- [Polskie programy open source do faktur](https://firmowid.pl/poradnik/polskie-programy-open-source-do-faktur)
- [Jak bezpiecznie przetestować KSeF](https://firmowid.pl/poradnik/jak-bezpiecznie-przetestowac-ksef)
- [Jak wybrać program do faktur](https://firmowid.pl/poradnik/jak-wybrac-program-do-faktur)
- [Cennik Firmowida](https://firmowid.pl/cennik)

## Źródła

- Firmowid, funkcje, ograniczenia publicznego kodu i licencja; weryfikacja 22.10.2026.
- [Ministerstwo Finansów: Aplikacja Podatnika KSeF 2.0](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-20/), dostęp 27.10.2026.
- [CISA: Back Up Business Data](https://www.cisa.gov/secure-our-world/back-business-data), dostęp 6.11.2026.
- [CISA: Require Multifactor Authentication](https://www.cisa.gov/secure-our-world/require-multifactor-authentication), dostęp 6.11.2026.
