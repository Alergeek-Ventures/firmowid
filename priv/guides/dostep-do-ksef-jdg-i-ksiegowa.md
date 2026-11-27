---
title: "Uprawnienia w KSeF: dostęp dla biura księgowego i pracownika"
description: "Właściciel JDG ma uprawnienia w KSeF automatycznie i sam nadaje je biuru księgowemu lub pracownikowi. Spółka bez pieczęci zaczyna od zawiadomienia ZAW-FA."
published: 2026-11-12
updated: 2026-11-23
category: ksef-w-praktyce
---

Z dostępem do KSeF w jednoosobowej działalności wiąże się mniej formalności, niż zakłada wielu przedsiębiorców, bo osoba fizyczna z NIP otrzymuje w systemie uprawnienia właścicielskie automatycznie i nie składa w tej sprawie żadnego zgłoszenia. Według Ministerstwa Finansów loguje się ona Podpisem Zaufanym albo kwalifikowanym podpisem elektronicznym, przy czym podpis, który nie zawiera ani NIP, ani PESEL, trzeba najpierw powiązać z podatnikiem na formularzu ZAW-FA. Spółka bez pieczęci kwalifikowanej z NIP również składa ZAW-FA i wskazuje w nim osobę, która będzie obsługiwać KSeF.

| Kto | Skąd ma uprawnienia | Jak nadaje je innym |
|---|---|---|
| Jednoosobowa działalność | automatycznie, do NIP | elektronicznie, po zalogowaniu Profilem Zaufanym lub podpisem |
| Spółka z pieczęcią kwalifikowaną z NIP | automatycznie, do NIP | elektronicznie, po zalogowaniu pieczęcią |
| Spółka bez pieczęci | ZAW-FA, jedna wskazana osoba | wskazana osoba nadaje kolejne elektronicznie |

## Kto może nadawać uprawnienia w KSeF?

Podatnik i każdy, komu przekazał on uprawnienie do zarządzania uprawnieniami. O jednoosobowych firmach MF pisze: „W przypadku osób fizycznych prowadzących działalność gospodarczą, które są podatnikami VAT, system KSeF automatycznie przypisuje im tzw. uprawnienia właścicielskie”. Podręcznik KSeF 2.0 dodaje jedno zdanie, które porządkuje resztę: „Uprawnień właściciela nie można odebrać”.

Zgłoszenie podpisu bez NIP i PESEL to jedyny przypadek, w którym osoba fizyczna składa ZAW-FA. Biuru księgowemu i pracownikom właściciel nadaje uprawnienia elektronicznie.

## Co oznaczają poszczególne uprawnienia w KSeF?

| Uprawnienie | Na co pozwala |
|---|---|
| Zarządzanie uprawnieniami | nadawanie i odbieranie uprawnień innym, razem z ich przeglądaniem |
| Wystawianie faktur | faktury online i w trybach offline |
| Dostęp do faktur | lista faktur podatnika i ich pobieranie |
| Przeglądanie uprawnień | podgląd, kto co może w firmie |
| Przeglądanie historii sesji | m.in. pobieranie UPO |

Dwa zastrzeżenia z podręcznika. Pierwsze: „Uprawnienie do wystawiania faktur oraz uprawnienie do dostępu do faktur w KSeF to dwa odrębne uprawnienia od strony systemowej”, więc można nadać jedno bez drugiego. Drugie dotyczy zakresu: „Uprawnienie do dostępu do faktur w KSeF obejmuje dostęp do wszystkich faktur danego podatnika, w tym jego faktur sprzedażowych jak i faktur zakupowych”. Nie da się pokazać komuś samej sprzedaży.

Uprawnienia do akceptowania faktur w KSeF nie ma. MF odpowiada krótko: „W KSeF nie jest wymagana akceptacja faktur przez odbiorcę”.

## Jaki rodzaj uprawnień wybrać w KSeF dla biura rachunkowego?

Do wystawiania faktur i dostępu do nich, nadane biuru jako podmiotowi, z prawem dalszego przekazywania. Na pytanie, czy każdemu pracownikowi biura trzeba nadawać uprawnienia osobno, ministerstwo odpowiada: „Nie musisz. Możesz nadać uprawnienie całemu podmiotowi (biuru)”, i dalej: „Wtedy to biuro wskaże osoby, które w praktyce będą wystawiać Twoje faktury”.

| Sposób | Kto wskazuje osoby | Co się dzieje, gdy w biurze zmieni się pracownik |
|---|---|---|
| Uprawnienie dla konkretnej osoby z biura | przedsiębiorca | przedsiębiorca odbiera uprawnienie i nadaje nowe |
| Uprawnienie dla biura z prawem dalszego przekazywania | biuro | biuro zmienia to u siebie, przedsiębiorca nic nie robi |

W podręczniku ten drugi sposób nazywa się uprawnieniami nadawanymi w sposób pośredni. MF opisuje go tak: „Pośrednik (np. biuro rachunkowe), który będzie nadawał uprawnienia, nie będzie uwierzytelniał się w tym celu w imieniu podatnika, lecz w swoim imieniu (w swoim kontekście)”. Osoba wskazana przez biuro może wyłącznie wystawiać faktury i mieć do nich dostęp, a dalej uprawnień nie przekaże.

Certyfikatu KSeF ani tokenu biuru księgowemu się nie przekazuje. Różnice między nimi opisuje tekst [certyfikat KSeF typu 1 i 2](/poradnik/certyfikat-ksef-typ-1-i-2).

## Jak upoważnić pracownika do KSeF?

Pracownik dostaje uprawnienie na swój PESEL albo NIP i loguje się własnym Profilem Zaufanym. Ministerstwo zaznacza, że „każda osoba uprawniona (zarówno zgłoszona na ZAW-FA jak i kolejna osoba) posługuje się osobistym narzędziem autoryzacji”.

| Zadanie pracownika | Uprawnienie |
|---|---|
| Wystawia faktury | wystawianie faktur |
| Pobiera faktury kosztowe | dostęp do faktur |
| Ma dodawać kolejne osoby | zarządzanie uprawnieniami |

Uprawnienie do zarządzania jest niepodzielne. Według podręcznika „Nie jest możliwe nadanie uprawnienia wyłącznie do nadawania uprawnień lub wyłącznie do odbierania uprawnień do korzystania z KSeF”.

## Gdzie nadać uprawnienia do KSeF?

W Aplikacji Podatnika KSeF 2.0 albo w programie, który obsługuje nadawanie uprawnień przez API KSeF 2.0. Na stronie aplikacji MF udostępnia instrukcje wideo, między innymi „Nadanie uprawnień osobie fizycznej do pracy w KSeF” oraz „Nadanie uprawnień do wystawiania i przeglądania faktur”. Uprawnienia nadane pracownikom w KSeF 1.0 nie przeszły do KSeF 2.0, poza nadanymi przez ZAW-FA i właścicielskimi.

## Jak zgłosić administratora do KSeF w spółce?

Spółka z pieczęcią kwalifikowaną zawierającą NIP niczego nie zgłasza. Bez pieczęci składa ZAW-FA do naczelnika urzędu skarbowego: na papierze, przez formularz w e-Urzędzie Skarbowym albo przez e-Doręczenia. Podręcznik ostrzega: „Od 1 stycznia 2026 r. zawiadomienie ZAW-FA składane przez ePUAP do urzędów skarbowych nie jest uznawane za skutecznie doręczone”.

Osoba z ZAW-FA dostaje zarządzanie uprawnieniami, wystawianie faktur i dostęp do nich. Nie musi to być członek zarządu. Na pytanie, czy ma to być dyrektor, MF odpowiada: „Może to być dowolna osoba. Wskazanie tej osoby leży wyłącznie w gestii podmiotu zgłaszającego”.

## Ile może być administratorów w KSeF?

Przez ZAW-FA jeden, w systemie dowolnie wielu. Odpowiedź ministerstwa: „W ZAW-FA zgłaszasz tylko pierwszą osobę o najszerszych uprawnieniach”, a kolejne osoby z pełnymi uprawnieniami dodaje ona elektronicznie.

Gdy firma rozstaje się z osobą z ZAW-FA i nikt inny nie ma pełnych uprawnień, MF radzi: „Składasz nowe ZAW-FA, wskazując kolejną osobę w miejsce dotychczasowej. To przywróci możliwość zarządzania uprawnieniami”. Zmiana tej osoby nie odbiera uprawnień ludziom, których wcześniej uprawniła.

## Dlaczego nie widzę uprawnień w KSeF?

| Sytuacja z forów | Co wynika z materiałów MF |
|---|---|
| Prezes spółki loguje się swoim podpisem i dostaje komunikat o braku uprawnień | wpis w KRS nie daje uprawnień w KSeF; spółka bez pieczęci musi wskazać osobę w ZAW-FA |
| Wspólnik spółki jawnej nie może się zalogować | spółka jawna bez pieczęci składa ZAW-FA, działa wspólnik w nim wskazany |
| Po nowym ZAW-FA program przestał wysyłać faktury | możliwa przyczyna: cel „odebranie wszelkich nadanych uprawnień”, który czyści wszystko poza właścicielskimi |
| Uprawnienia z KSeF 1.0 nie działają | nadane pracownikom w KSeF 1.0 nie obowiązują w KSeF 2.0 |
| ZAW-FA wysłane przez ePUAP | od 1 stycznia 2026 r. nieskuteczne |

O opcji odebrania wszelkich uprawnień podręcznik pisze: „Po tej operacji konieczne więc będzie zbudowanie uprawnień w KSeF w danej firmie od początku”.

## Ile trwa nadanie uprawnień do KSeF?

Elektronicznie zwykle od razu po przetworzeniu. Przy ZAW-FA uprawnienia działają dopiero wtedy, gdy pracownik urzędu skarbowego wprowadzi zawiadomienie do systemu, a firma i osoba uprawniona dostają o tym e-mail. Wysyłka pocztą wydłuża to o czas doręczenia.

## Uprawnienia w KSeF a role w Firmowidzie

Firmowid, nasz [program do KSeF](/ksef), łączy się z KSeF raz, w ustawieniach firmy, i robi to administrator ([jak połączyć Firmowid z KSeF](/pomoc/polaczenie-z-ksef)). Uprawnień w KSeF w Firmowidzie się nie nadaje, do tego służy Aplikacja Podatnika. Gdy [zarejestrujesz](/zarejestruj) firmę, przez pierwsze 60 dni każdy plan, także ten z kontami dla biura księgowego, działa bez opłat.

Kto co widzi w samym programie, ustawia się osobno, rolami. Biuro księgowe może dostać własne konto z [rolą Księgowość](/funkcje/zespol), której opis w aplikacji brzmi: „Pełny dostęp do fakturowania (przeglądanie, dodawanie i edycja), z wyjątkiem dodawania faktur spoza KSeF”. Rola Fakturowanie daje sam podgląd.

![Właściciel JDG ma uprawnienia w KSeF automatycznie i loguje się Podpisem Zaufanym albo kwalifikowanym. Program do faktur łączy się tokenem albo certyfikatem z Aplikacji Podatnika KSeF. Biuru księgowemu właściciel nadaje uprawnienia, nie przekazuje certyfikatu.](/images/guides/dostep-do-ksef-wlasciciel-program-ksiegowa.webp)

## Źródła

- [MF: Podręcznik KSeF 2.0, cz. I, rozdział 3](https://ksef.podatki.gov.pl/media/dmrfdixs/podrecznik-ksef-20-cz-i-rozpoczecie-korzystania-z-ksef-06082026.pdf) (wersja z sierpnia 2026 r.), dostęp 23.11.2026.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/) (wersja z 10.11.2026), dostęp 23.11.2026.
- [MF: Aplikacja Podatnika KSeF 2.0](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-20/), dostęp 23.11.2026.
- [MF: Krok po kroku, JDG i MŚP](https://ksef.podatki.gov.pl/krok-po-kroku-jdg-i-msp/), dostęp 10.11.2026.

*To informacja ogólna, nie porada podatkowa.*
