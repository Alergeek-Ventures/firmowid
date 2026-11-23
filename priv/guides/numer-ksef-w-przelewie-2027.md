---
title: "Numer KSeF w tytule przelewu od 2027 r.: kto musi podać"
description: "Od 1 stycznia 2027 r. przelew za e-fakturę między czynnymi podatnikami VAT zawiera numer KSeF albo identyfikator zbiorczy. Kogo to obejmuje, a kogo nie."
published: 2026-11-12
updated: 2026-11-23
category: bank-i-platnosci
---

Z płatnościami za faktury od 1 stycznia 2027 r. wiąże się nowy art. 108g ustawy o VAT, zgodnie z którym w tytule przelewu podaje się numer KSeF opłacanej faktury albo, gdy przelew obejmuje kilka faktur jednego sprzedawcy, identyfikator zbiorczy. Przy poleceniu zapłaty ten obowiązek ma wystawca faktury. Ministerstwo Finansów wyjaśnia, że obowiązek dotyczy płatności między czynnymi podatnikami VAT, a jako główny cel zmiany podaje przeciwdziałanie zatorom płatniczym. Podatnik zwolniony z VAT podmiotowo nie musi więc podawać numeru, kiedy płaci za otrzymane e-faktury zwykłym przelewem, a jego kontrahent, czynny podatnik, nie musi tego robić, kiedy płaci jemu. Od tego samego dnia zmienia się też art. 108a ustawy, przez co numer KSeF trafia również do przelewów w mechanizmie podzielonej płatności.

## Kilka faktur w jednym przelewie

Identyfikator zbiorczy obejmuje co najmniej dwa numery KSeF, a według odpowiedzi MF jeden identyfikator może objąć do 500 faktur wystawionych przez tego samego sprzedawcę, także na rzecz różnych nabywców. Wygenerowanego identyfikatora nie można edytować ani usunąć. Sprzedawca, który otrzyma przelew z takim identyfikatorem, odczytuje z niego numery faktur w KSeF, więc nabywca nie musi przesyłać mu ich osobno.

## Przypadki opisane przez MF

Ministerstwo wyjaśnia też, że numer podaje faktor lub inny podmiot płacący w imieniu nabywcy, o ile jest czynnym podatnikiem VAT, a nie podaje go nabywca przekazujący zapłatę komornikowi w ramach zajęcia wierzytelności dostawcy. Obowiązek nie obejmuje faktur wystawionych w trybie awaryjnym, a o jego zastosowaniu przesądza data płatności, dlatego faktura otrzymana w KSeF 23 grudnia 2026 r. i opłacona 2 stycznia 2027 r. wymaga już podania numeru. W Firmowidzie, naszym programie do faktur, wysyłka faktury mailem do klienta następuje domyślnie dopiero po nadaniu jej numeru KSeF. Przelewy, które potem przychodzą od klientów, program pobiera z banku i [sam łączy z fakturami](/funkcje/bank).

## Czy numer KSeF musi być w tytule przelewu?

| Kto płaci | Komu | Numer KSeF w przelewie |
|---|---|---|
| Czynny podatnik VAT | czynnemu podatnikowi VAT | tak |
| Zwolniony z VAT | czynnemu podatnikowi VAT | nie |
| Czynny podatnik VAT | zwolnionemu z VAT | nie |
| Faktor, czynny podatnik VAT | czynnemu podatnikowi VAT | tak |
| Nabywca | komornikowi | nie |
| Dowolny, w podzielonej płatności | sprzedawcy | tak |

Tam, gdzie obowiązku nie ma, ministerstwo powtarza to samo zdanie: „Nabywca może jednak podać te dane w tytule przelewu dobrowolnie”. Na pytanie o przesunięcie terminu MF odpowiada: „Nie, nie jest planowane odroczenie obowiązku podawania numeru KSeF lub zbiorczego identyfikatora podczas płatności za e-Fakturę”.

## Od kiedy trzeba podawać numer KSeF w przelewach?

Od płatności wykonanych 1 stycznia 2027 r. i później. O fakturze z grudnia opłacanej w styczniu MF pisze: „Nie ma przy tym znaczenia fakt, że e-Faktura była wystawiona w grudniu 2026 r.”. Tego samego dnia sprawdza się, czy obie strony są czynnymi podatnikami: „Status stron transakcji należy badać na dzień realizacji płatności, na podstawie danych zawartych w Wykazie podatników”.

## Jaki tytuł przelewu za fakturę z KSeF?

Numer KSeF ma 35 znaków, a pole tytułu w banku zwykle 140. Ministerstwo wylicza, że „w jednym tytule zmieszczą się trzy 35-znakowe identyfikatory zbiorcze lub numery KSeF, oddzielone przecinkami”. Własny numer faktury można dopisać obok, bo według MF „Regulacje w zakresie płatności nie zabraniają podatnikowi podawania dodatkowych danych w tytule płatności”.

| Płatność | Co w tytule |
|---|---|
| Jedna faktura | numer KSeF |
| Dwie albo trzy faktury | numery KSeF po przecinku albo identyfikator zbiorczy |
| Więcej faktur jednego sprzedawcy | identyfikator zbiorczy albo osobne przelewy |
| Kilka faktur w podzielonej płatności | zawsze identyfikator zbiorczy |

## Jak wygenerować identyfikator zbiorczy KSeF?

W Aplikacji Podatnika KSeF albo w programie, który ma tę funkcję przez API. MF zapowiada: „funkcjonalności związane z identyfikatorem zbiorczym będą dostępne w Aplikacji Podatnika KSeF”.

| Cecha | Wartość |
|---|---|
| Najmniej faktur | 2 |
| Najwięcej faktur | 500 |
| Jeden numer KSeF w wielu identyfikatorach | do 132 |
| Sprzedawca | zawsze ten sam |
| Edycja i usunięcie | nie |
| Kwota częściowa, waluta, opis faktury | można dodać |

Gdy w dniu płatności KSeF ma awarię i identyfikatora nie da się wygenerować, ministerstwo każe podać numery KSeF faktur albo zapłacić po przywróceniu tej funkcji, jeśli termin na to pozwala.

## Co sprzedawca widzi w przelewie z identyfikatorem zbiorczym?

Sam identyfikator. Ministerstwo wyjaśnia: „Sprzedawca może zdekodować ten identyfikator w KSeF i otrzyma dzięki temu informacje, jakie numery KSeF wchodzą w jego skład”. Nabywców po nim rozpoznać się nie da, „ponieważ w identyfikatorze zbiorczym znajduje się NIP sprzedawcy, a nie NIP nabywcy (podobnie jak w strukturze numeru KSeF)”. Dwóch identyfikatorów nie łączy się w trzeci. MF pisze, że identyfikator zbiorczy „jest generowany wyłącznie dla numerów KSeF, a nie dla identyfikatorów zbiorczych”.

Po co to wszystko, resort tłumaczy jednym zdaniem: „Głównym celem jest przeciwdziałanie zatorom płatniczym”.

## Numer KSeF w przelewie a Firmowid

Firmowid przelewów nie wysyła. Przy fakturze kosztowej jest okno „Dane do przelewu” z przyciskiem „Skopiuj dane”, a tytuł zaczyna się tam od słów „Płatność za fakturę” i zawiera numer nadany przez sprzedawcę. Numer KSeF jest na fakturze osobno i trzeba go dopisać do tytułu samemu. Identyfikatorów zbiorczych program nie generuje.

![Od 2027 r. numer KSeF w tytule przelewu podaje czynny podatnik VAT płacący innemu czynnemu podatnikowi, a zwolnionych z VAT to nie dotyczy, chyba że płacą w MPP. Przelew za kilka faktur jednego sprzedawcy ma identyfikator zbiorczy do 500 faktur. O obowiązku decyduje data płatności.](/images/guides/numer-ksef-w-przelewie-kto-podaje.webp)

## Źródła

- [MF: Pytania i odpowiedzi KSeF 2.0, część „Płatność z numerem KSeF/Identyfikatorem zbiorczym od 1 stycznia 2027 r.”](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/) (wersja z 10.11.2026), dostęp 23.11.2026.
- Art. 108g i art. 108a ust. 3 pkt 3 ustawy z 11 marca 2004 r. o podatku od towarów i usług.

*To informacja ogólna, nie porada podatkowa.*
