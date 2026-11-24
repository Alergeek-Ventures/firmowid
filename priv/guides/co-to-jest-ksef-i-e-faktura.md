---
title: "Co to jest KSeF i czym e-faktura różni się od PDF-a"
description: "KSeF w skrócie: czym e-faktura różni się od PDF-a, kogo i od kiedy obejmuje KSeF, co zmienia się 1 stycznia 2027 r. i czym wystawić pierwszą fakturę."
published: 2026-10-29
updated: 2026-11-24
category: ksef-w-praktyce
---

Krajowy System e-Faktur działał jako rozwiązanie dobrowolne od 2022 r., a obowiązkowy stał się 1 lutego 2026 r., kiedy faktury zaczęli w nim wystawiać najwięksi podatnicy, ze sprzedażą powyżej 200 mln zł brutto w 2024 r., a odbierać wszystkie firmy. Pozostałe przedsiębiorstwa dołączyły 1 kwietnia 2026 r., a najmniejsze, których faktury objęte obowiązkiem nie przekraczają [10 000 zł brutto miesięcznie](/poradnik/limit-10000-ksef), korzystają z wyjątku do końca 2026 r., chyba że limit przekroczą, bo wtedy od faktury, która go przekroczyła, wystawiają już wszystkie w systemie. Przyjmuje on faktury ustrukturyzowane, czyli pliki XML zgodne ze wzorem Ministerstwa Finansów, a fakturę przyjętą przez system uważa się za wystawioną w dniu jej przesłania, w trybie offline w dniu z pola P_1. O przyjęciu świadczy jednak dopiero numer KSeF, więc sam komunikat o wysłaniu jeszcze o niczym nie przesądza.

![Terminy KSeF: od 2022 r. system dobrowolny. 1 lutego 2026 r. faktury w KSeF wystawiają najwięksi podatnicy ze sprzedażą powyżej 200 mln zł brutto w 2024 r., a odbierają wszystkie firmy. 1 kwietnia 2026 r. dołączają pozostałe firmy, z wyjątkiem do końca 2026 r. dla faktur do 10 000 zł brutto miesięcznie. 1 stycznia 2027 r. wyjątek wygasa, a w przelewach między czynnymi podatnikami VAT podaje się numer KSeF. Faktura jest przyjęta dopiero z numerem KSeF, PDF to tylko jej czytelna wersja.](/images/guides/ksef-terminy-2022-2027.webp)

## Co to jest KSeF i do czego służy?

Definicja Ministerstwa Finansów: „Krajowy System e-Faktur (KSeF) to system służący do wystawiania, przesyłania, odbierania i przechowywania faktur ustrukturyzowanych”. O celu MF pisze krótko: system „Pozwala także unikać błędów przy ich wystawianiu”.

## Co to jest e-faktura?

Według MF: „To zgodny z wzorem plik XML, przesłany do systemu KSeF, któremu został nadany unikalny numer”. Dalej ministerstwo dodaje: „W KSeF znajdzie ją odbiorca (podatnik posiadający NIP) i tu jest archiwizowana przez 10 lat”.

## Kogo obowiązuje KSeF?

Ministerstwo: „Co do zasady każdy podatnik (czynny i zwolniony), który ma obowiązek wystawienia faktury, będzie wystawiał ją w KSeF”. Osoba prywatna nie musi mieć dostępu do systemu, o czym jest tekst [faktura dla osoby prywatnej a KSeF](/poradnik/faktura-dla-osoby-prywatnej-ksef).

## Co daje KSeF firmie?

| Korzyść | Jak opisuje ją MF |
|---|---|
| Szybszy obieg | „faktury trafiają do odbiorcy niemal w czasie rzeczywistym” |
| Archiwum | „Stały dostęp do faktur przez 10 lat” |
| Zwrot VAT | „w 40 dni zamiast 60” |

## Czy KSeF sprawdza kontrahenta?

Nie. Na pytanie, czy system sprawdza status kontrahenta w Wykazie Podatników VAT, MF odpowiada: „Aktualnie nie jest planowane wprowadzenie takiej funkcjonalności”. Fakturę z pomylonym NIP nabywcy poprawia [korekta do zera](/poradnik/korekta-faktury-ksef) i nowa faktura.

## E-faktura a PDF

Plik PDF pełni przy e-fakturze funkcję wizualizacji, czyli czytelnej wersji danych, na której umieszcza się kod QR z numerem KSeF, ale fakturą ustrukturyzowaną nie jest.

Odbiorca nie musi faktury akceptować. MF: „W KSeF nie jest wymagana akceptacja faktur przez odbiorcę. Faktura jest uznana za otrzymaną w momencie, gdy system nada jej numer”.

## Co zmienia się 1 stycznia 2027 r.

Z początkiem 2027 r. [wygasa wyjątek dla sprzedaży do 10 000 zł brutto miesięcznie](/poradnik/ksef-od-1-stycznia-2027-male-firmy), a do płatności między czynnymi podatnikami VAT stosuje się art. 108g ustawy o VAT, który wymaga podania w tytule przelewu [numeru KSeF opłacanej faktury](/poradnik/numer-ksef-w-przelewie-2027).

Dla sprzedaży konsumenckiej nic się nie zmienia. MF: „Wystawianie w KSeF faktur na rzecz konsumentów nie jest obowiązkowe”. O firmach zwolnionych z VAT jest osobny tekst: [zwolnienie z VAT a KSeF](/poradnik/zwolnienie-z-vat-a-ksef-2027).

## Czym wystawić fakturę w KSeF

MF wymienia dwie drogi: „programów finansowo-księgowych, o ile są zintegrowane z KSeF (integracja przez API)” oraz „bezpłatnych narzędzi Ministerstwa Finansów”. [Zakup programu](/poradnik/ksef-w-banku-aplikacja-mf-czy-program) nie jest więc warunkiem. Nasz [Firmowid](/ksef) łączy się z KSeF przez API i dopasowuje przelewy z konta firmowego do wystawionych faktur. Próbną fakturę bez skutków prawnych opisuje tekst [pierwsza faktura w KSeF](/poradnik/pierwsza-faktura-ksef).

## Źródła

- [MF: Zakres obowiązkowego KSeF](https://ksef.podatki.gov.pl/informacje-ogolne-ksef-20/zakres-obowiazkowego-ksef/), dostęp 11.11.2026.
- [MF: Etapy wdrożenia KSeF 2.0](https://ksef.podatki.gov.pl/etapy-wdrozenia-ksef/), dostęp 11.11.2026.
- [MF: Aplikacja Podatnika KSeF 2.0](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-20/), dostęp 11.11.2026.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/), dostęp 11.11.2026 i 24.11.2026.

*To informacja ogólna, nie porada podatkowa.*
