---
title: "Co to jest KSeF i czym e-faktura różni się od PDF-a"
description: "Krajowy System e-Faktur w skrócie: czym e-faktura różni się od PDF-a, kogo i od kiedy obejmuje KSeF, co zmienia się 1 stycznia 2027 r. i czym wystawić pierwszą fakturę."
published: 2026-10-29
updated: 2026-11-11
category: ksef-w-praktyce
---

Krajowy System e-Faktur działał jako rozwiązanie dobrowolne od 2022 r., a obowiązkowy stał się 1 lutego 2026 r., kiedy faktury zaczęli w nim wystawiać najwięksi podatnicy, ze sprzedażą powyżej 200 mln zł brutto w 2024 r., a odbierać wszystkie firmy. Pozostałe przedsiębiorstwa dołączyły 1 kwietnia 2026 r., a najmniejsze, których faktury objęte obowiązkiem nie przekraczają [10 000 zł brutto miesięcznie](/poradnik/limit-10000-ksef), korzystają z wyjątku do końca 2026 r., chyba że limit przekroczą, bo wtedy od faktury, która go przekroczyła, wystawiają już wszystkie w systemie. Przyjmuje on faktury ustrukturyzowane, czyli pliki XML zgodne ze wzorem Ministerstwa Finansów, a fakturę przyjętą przez system uważa się za wystawioną w dniu jej przesłania, w trybie offline w dniu z pola P_1. O przyjęciu świadczy jednak dopiero numer KSeF, więc sam komunikat o wysłaniu jeszcze o niczym nie przesądza.

![Terminy KSeF: od 2022 r. system dobrowolny. 1 lutego 2026 r. faktury w KSeF wystawiają najwięksi podatnicy ze sprzedażą powyżej 200 mln zł brutto w 2024 r., a odbierają wszystkie firmy. 1 kwietnia 2026 r. dołączają pozostałe firmy, z wyjątkiem do końca 2026 r. dla faktur do 10 000 zł brutto miesięcznie. 1 stycznia 2027 r. wyjątek wygasa, a w przelewach między czynnymi podatnikami VAT podaje się numer KSeF. Faktura jest przyjęta dopiero z numerem KSeF, PDF to tylko jej czytelna wersja.](/images/guides/ksef-terminy-2022-2027.webp)

## E-faktura a PDF

Plik PDF pełni przy e-fakturze funkcję wizualizacji, czyli czytelnej wersji danych, na której umieszcza się kod QR z numerem KSeF, ale fakturą ustrukturyzowaną nie jest. Odbiorca, który ma dostęp do KSeF, widzi dokument od chwili nadania numeru i nie musi go akceptować, a ministerstwo przechowuje faktury w systemie przez 10 lat. Danych kontrahenta system nie weryfikuje, dlatego faktura z pomylonym NIP nabywcy zostaje przyjęta, a poprawia się ją [korektą do zera](/poradnik/korekta-faktury-ksef) i nową fakturą z właściwym NIP.

## Co zmienia się 1 stycznia 2027 r.

Z początkiem 2027 r. wygasa wyjątek dla sprzedaży do 10 000 zł brutto miesięcznie, a do płatności między czynnymi podatnikami VAT stosuje się art. 108g ustawy o VAT, który wymaga podania w tytule przelewu [numeru KSeF opłacanej faktury](/poradnik/numer-ksef-w-przelewie-2027). Faktury dla konsumentów mogą nadal powstawać poza systemem, natomiast jednoosobowa działalność gospodarcza, także [zwolniona z VAT](/poradnik/zwolnienie-z-vat-a-ksef-2027), wystawia faktury dla firm już tylko w KSeF.

## Czym wystawić fakturę w KSeF

Bezpłatna Aplikacja Podatnika KSeF pozwala wystawiać i odbierać faktury, nadawać uprawnienia pracownikom albo biuru rachunkowemu i pobierać Urzędowe Poświadczenie Odbioru, więc [zakup programu](/poradnik/czy-trzeba-kupowac-program-do-ksef) nie jest warunkiem korzystania z systemu. Programy do faktur łączą się z KSeF przez API i rozszerzają go o funkcje spoza zakresu ministerialnej aplikacji, w przypadku naszego Firmowida między innymi o dopasowanie przelewów z konta firmowego do wystawionych faktur. Ministerstwo udostępnia też środowisko testowe, w którym próbna faktura nie wywołuje skutków prawnych, w odróżnieniu od dokumentu wysłanego na produkcję, a cały proces opisuje poradnik o [pierwszej fakturze w KSeF](/poradnik/pierwsza-faktura-ksef).

## Źródła

- [MF: Zakres obowiązkowego KSeF](https://ksef.podatki.gov.pl/informacje-ogolne-ksef-20/zakres-obowiazkowego-ksef/), dostęp 11.11.2026.
- [MF: Etapy wdrożenia KSeF 2.0](https://ksef.podatki.gov.pl/etapy-wdrozenia-ksef/), dostęp 11.11.2026.
- [MF: Aplikacja Podatnika KSeF 2.0](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-20/), dostęp 11.11.2026.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/), dostęp 11.11.2026.

*To informacja ogólna, nie porada podatkowa.*
