---
title: "Faktura dla klienta z UE w KSeF: jaka stawka VAT i adnotacja"
description: "Usługa dla firmy z UE z numerem VAT-UE: w KSeF stawka np II i adnotacja „odwrotne obciążenie”, bez polskiego VAT. Wcześniej rejestracja VAT-UE i VIES."
published: 2026-11-12
updated: 2026-11-27
category: ksef-w-praktyce
---

Na pytanie, czy fakturę dla kontrahenta z Niemiec też trzeba wystawić w KSeF, Ministerstwo Finansów odpowiada, że tak, jeśli sprzedawca ma siedzibę w Polsce, a nabywcy, który do systemu nie ma dostępu, przekazuje się ją w uzgodniony sposób, z kodem QR.

| Klient | Stawka | Adnotacja |
|---|---|---|
| Firma z UE z numerem VAT-UE | np II | odwrotne obciążenie |
| Osoba prywatna z UE | polska stawka VAT | brak |
| Firma spoza UE | np I | zależy od usługi |
| Krajowe odwrotne obciążenie | oo | odwrotne obciążenie |

Stawka np II dotyczy usług z art. 28b ustawy o VAT. Remont nieruchomości w Polsce to art. 28e i polski VAT. Serwis Biznes.gov.pl podaje przykład usług dla spółki z Belgii: „Usługi nie podlegają opodatkowaniu VAT w Polsce, lecz w Belgii”.

## VAT-UE i informacja podsumowująca

Biznes.gov.pl: „Zanim zaczniesz świadczyć usługi dla kontrahentów z państw Unii Europejskiej lub nabywać od nich usługi, musisz zarejestrować się do VAT-UE. Obowiązek dotyczy zarówno podatników VAT czynnych, jak i zwolnionych”. Służy do tego formularz VAT-R. Wyjątek z art. 97 ust. 3 ustawy: usługa, która w kraju nabywcy jest zwolniona albo ma stawkę 0%.

O informacji podsumowującej ten sam serwis pisze: „Termin złożenia to 25. dzień miesiąca następującego po miesiącu, w którym powstał obowiązek podatkowy”. Składa się ją co miesiąc i tylko elektronicznie. Informacji zerowych się nie składa.

O numerze nabywcy: „Zawsze sprawdź status kontrahenta z zagranicy. Jeżeli nie jest podatnikiem VAT-UE, usługa będzie opodatkowana w Polsce. Do weryfikacji służy system VIES”.

## Faktura w euro

Fakturę można wystawić w euro. O kursie Biznes.gov.pl: „Jeśli kwoty stosowane do określenia podstawy opodatkowania są wyrażone w walucie obcej, przeliczasz je na złote według średniego kursu NBP z ostatniego dnia roboczego poprzedzającego dzień powstania obowiązku podatkowego”. Gdy faktura powstała wcześniej, liczy się dzień przed jej wystawieniem (art. 31a ust. 2 ustawy).

## Czy freelancer wystawia fakturę dla klienta z UE w KSeF?

Tak. Ministerstwo pisze o jednoosobowych działalnościach: „Forma prawna nie ma znaczenia”. Sam system jest według MF „przeznaczony do wystawiania faktur w rozumieniu polskich przepisów (w tym na rzecz zagranicznych kontrahentów)”. Do końca 2026 r. najmniejsze firmy korzystają jeszcze z progu opisanego w tekście [limit 10 000 zł w KSeF](/poradnik/limit-10000-ksef).

## Jak wystawić fakturę w KSeF dla firmy niemieckiej?

| Co | Pole w FA(3) | Wartość |
|---|---|---|
| Kraj nabywcy | KodUE | DE |
| Numer VAT-UE nabywcy | NrVatUE | sam numer, bez DE |
| Prefiks sprzedawcy | PrefiksPodatnika | PL |
| Stawka na pozycji | P_12 | np II |
| Suma usług | P_13_9 | wartość netto |
| Adnotacja | P_18 | 1, czyli „odwrotne obciążenie” |

Podręcznik KSeF 2.0 o danych nabywcy: „kod kraju kontrahenta należy wskazać w polu KodUE (element Podmiot2/DaneIdentyfikacyjne), a numer identyfikacyjny kontrahenta nadany na cele podatku od wartości dodanej - w polu NrVatUE”.

Stawki oo nie używa się przy usłudze dla firmy z innego kraju. Pole P_13_10, do którego trafia jej suma, schemat opisuje jako sprzedaż w odwrotnym obciążeniu „występujących w obrocie krajowym”.

## Jak zagraniczny kontrahent otrzyma fakturę z KSeF?

Odpowiedź MF: „Faktura zostaje wystawiona w KSeF, ale zagraniczny odbiorca, który z założenia nie posiada polskiego NIP, nie będzie mógł zalogować się do systemu i jej pobrać”. Sprzedawca przekazuje mu więc dokument sam, na przykład jako PDF w e-mailu. Według ministerstwa faktura „powinna być opatrzona kodem QR, który pozwoli zweryfikować kontrahentowi, że dokument faktycznie istnieje w KSeF”.

## Czy KSeF obowiązuje w Unii Europejskiej?

Nie, KSeF jest polskim systemem. O unijnym pakiecie VIDA ministerstwo pisze: „Rozwiązania krajowe będą przedmiotem odrębnej ustawy”.

## Program do faktur dla freelancera z klientami z UE

[Firmowid](/ksef), nasz program, przy nabywcy z numerem VAT-UE ustawia walutę EUR i włącza przełącznik „Reverse charge”. Podpowiedź przy nim brzmi: „Reverse charge (odwrotne obciążenie) to mechanizm, w którym obowiązek rozliczenia podatku VAT spoczywa na nabywcy usługi”. Włączony przełącznik wpisuje na pozycjach stawkę oo. Stawka „np II (usługi B2B dla UE)” pojawia się po jego wyłączeniu. Przed wysyłką trzeba więc sprawdzić stawkę na podglądzie. Numer VAT-UE kontrahenta program sprawdza w VIES, a dokument jest dwujęzyczny.

![Usługa z art. 28b dla firmy z UE z numerem VAT-UE: stawka np II i adnotacja odwrotne obciążenie. Osoba prywatna z UE: polska stawka VAT. Firma spoza UE: np I. Krajowe odwrotne obciążenie: oo. Przed pierwszą usługą dla firmy z UE trzeba zarejestrować się jako podatnik VAT-UE.](/images/guides/faktura-ue-ksef-stawka-np-ii.webp)

## Porównanie programów do faktur dla klientów z UE

| Program | Waluty | Odwrotne obciążenie i VIES | Plan | Stan na |
|---|---|---|---|---|
| Firmowid | „Faktury w 33 walutach” | „Odwrotne obciążenie dla klientów z UE (automatycznie)” | Darmowy, 0 zł | 25.11.2026 |
| Fakturownia | „Dowolna waluta na fakturze” | „faktury z odwrotnym obciążeniem”, VIES przy fakturze OSS | Micro, 0 zł, 3 faktury | 27.11.2026 |
| wFirma | „Transakcje zagraniczne”, „Różnice kursowe” | „Integracja z VIES i białą listą” | Księgowość, 60 zł | 27.11.2026 |
| iFirma | brak informacji w cenniku | brak informacji w cenniku | | 27.11.2026 |

Cudzysłowy to zapisy z cenników. Ceny netto za miesiąc.

## Źródła

- Cenniki: [Firmowid](https://firmowid.pl/cennik), dostęp 25.11.2026; [Fakturownia](https://fakturownia.pl/cennik), [wFirma](https://wfirma.pl/cennik) i [iFirma](https://www.ifirma.pl/cennik/), dostęp 27.11.2026.
- Art. 19a, art. 28b, art. 28e, art. 31a, art. 100, art. 97 ust. 3 i art. 106e ust. 1 pkt 18 ustawy z 11 marca 2004 r. o podatku od towarów i usług.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/), dostęp 11.11.2026 i 24.11.2026.
- [MF: Podręcznik KSeF 2.0, cz. II, rozdział 2.1.3](https://ksef.podatki.gov.pl/media/rronoxyt/podrecznik-ksef-20-cz-ii-wystawianie-i-otrzymywanie-faktur-w-ksef-06082026.pdf) (wersja z sierpnia 2026 r.), dostęp 23.11.2026.
- [Biznes.gov.pl: VAT w handlu międzynarodowym, świadczenie i nabycie usług](https://www.biznes.gov.pl/pl/portal/00272) (aktualizacja 04.12.2025), dostęp 24.11.2026.
- [Komisja Europejska: VIES](https://ec.europa.eu/taxation_customs/vies/), dostęp 11.11.2026.
- Struktura logiczna FA(3), oznaczenia „np I”, „np II” i „oo” oraz opisy pól P_13_9, P_13_10 i P_18 (schemat MF).

*To informacja ogólna, nie porada podatkowa.*
