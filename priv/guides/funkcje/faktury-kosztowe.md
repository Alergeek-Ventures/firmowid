---
title: "Program do faktur kosztowych z KSeF, ze skanu i z PDF"
description: "Firmowid pobiera faktury kosztowe z KSeF automatycznie, a te spoza KSeF odczytuje z PDF i ze zdjęcia. Cena, porównanie z innymi programami i ograniczenia."
published: 2026-11-18
updated: 2026-11-27
landing:
  kicker: "Funkcje · Faktury kosztowe"
  note: "przychodzą z KSeF automatycznie"
  facts:
    - label: "Cena"
      value: "0 zł, faktury z KSeF bez limitu"
    - label: "Faktury z KSeF"
      value: "pobierane co 2 godziny"
    - label: "Pliki"
      value: "PDF i zdjęcia, do 50 naraz"
---

Wcześniej faktury kosztowe gromadziły się na mailu. Często płaciliśmy w innym terminie, niż te maile przychodziły, więc na końcu miesiąca musieliśmy w ogóle szukać tych faktur po mailach. To było uciążliwe. Część była na papierze, musieliśmy to skanować i coś się gubiło. Teraz faktury z KSeF przychodzą same, a papierowe zazwyczaj skanujemy prosto do Firmowida. Komentarz dla biura księgowego kiedyś dopisywaliśmy ręcznie, teraz robimy to z pomocą AI, która uczy się na poprzednich fakturach i kategoriach firm. To naprawdę mocno uprzyjemnia pracę.

![Lista faktur zakupowych z KSeF i wgranych z pliku](/images/guides/funkcje/faktury-zakupowe.webp)

## Jak to działa

Firmę łączysz z KSeF raz. Od tej chwili każda faktura zakupu, na której jesteś nabywcą, trafia na listę bez Twojego udziału. Zostaje Ci opisać koszt, zapłacić i na koniec miesiąca wysłać dokumenty do biura księgowego.

| Krok | Gdzie | Co | Ekran |
|---|---|---|---|
| Połącz KSeF | Ustawienia | faktury z ostatnich 30 dni pobierają się od razu, kolejne co 2 godziny | ![Ustawienia z aktywnym połączeniem z KSeF](/images/guides/pomoc/ksef-6-polaczono.webp) |
| Opisz i zapłać | strona faktury | komentarz dla biura księgowego, dane do przelewu i przelew z banku przypięty do faktury | ![Faktura kosztowa z komentarzem, danymi do przelewu i proponowanym przelewem](/images/guides/funkcje/kosztowa-sugestie.webp) |
| Wyślij paczkę | Faktury | jeden plik ZIP z dokumentami za miesiąc | ![Okno „Pobierz faktury” z wyborem dokumentów do paczki](/images/guides/pomoc/paczka-okno.webp) |

Krok po kroku: [Pobieranie faktur z KSeF](/pomoc/pobieranie-faktur-z-ksef).

## Faktury spoza KSeF

Faktury od zagranicznych dostawców i dokumenty papierowe dodajesz z pliku. Przeciągasz PDF albo zdjęcie na listę faktur, najwyżej 50 plików naraz. Na telefonie dodajesz zdjęcie zrobione aparatem.

Firmowid odczytuje z pliku sprzedawcę, numer faktury, daty, kwotę, walutę i pozycje. Po chwili faktura jest na liście obok tych z KSeF.

**Brakująca faktura.** Jeśli do przelewu z banku nie ma dokumentu, przelew zostaje na liście bez pary. Wiesz wtedy, której faktury poszukać u dostawcy.

**Ten sam dokument dwa razy.** Plik wgrany drugi raz nie utworzy drugiej faktury. Tak samo plik z fakturą, która wcześniej przyszła z KSeF.

**Błędny odczyt.** Odczytanych danych nie poprawisz ręcznie. Usuwasz fakturę i wgrywasz plik jeszcze raz.

## Na co dzień

**Opis i komentarz.** Każda faktura dostaje krótki opis tego, co kupiono, i czytelną nazwę sprzedawcy. Komentarz dla biura księgowego wpisujesz na stronie faktury, a do pliku PDF trafia on jako osobna strona.

**Płatność.** Przycisk „Skopiuj dane” podaje odbiorcę, numer konta, tytuł i kwotę przelewu. Płacisz w swoim banku. Gdy przelew pojawi się na podłączonym koncie, Firmowid przypina go do faktury. Fakturę opłaconą gotówką oznaczasz przyciskiem „Pomiń”. Więcej: [Bank i dopasowanie przelewów](/funkcje/bank).

**Biuro księgowe.** Dokumenty za miesiąc pobierasz w jednej paczce ZIP: pliki PDF, faktury z KSeF i zdjęcia, razem z komentarzami. Jak ją przygotować: [Paczka dokumentów dla biura księgowego](/pomoc/paczka-dla-biura-ksiegowego).

## Ile to kosztuje

| Plan | Faktury kosztowe z KSeF | Odczyt danych z pliku | Cena |
|---|---|---|---|
| Darmowy | bez limitu | 10 miesięcznie | 0 zł |
| Mini | bez limitu | 25 miesięcznie | 9 zł netto miesięcznie |
| Przedsiębiorca | bez limitu | 50 miesięcznie | 29 zł netto miesięcznie |
| Firma | bez limitu | bez limitu | 149 zł netto miesięcznie |

Paczka ZIP dla biura księgowego jest w każdym planie.

## Porównanie z innymi programami

Pobieranie kosztów z KSeF mają dziś wszystkie programy z tej tabeli. Różnią się tym, ile kosztuje odczyt faktury z pliku i co dostaje biuro księgowe.

| Program | Koszty z KSeF | Odczyt z pliku (OCR) | Paczka dla biura księgowego | Najtańszy plan z OCR |
|---|---|---|---|---|
| Firmowid | automatycznie, co 2 godziny | tak | ZIP za miesiąc, z komentarzami | 0 zł, 10 odczytów miesięcznie |
| Fakturownia | automatycznie, częstotliwość niepodana | 3 do 10 skanów miesięcznie, więcej w paczkach | eksport do Raks i Optima w planie Pro | Start, 12,49 zł netto |
| wFirma | raz na dobę, nocą | Magic Box, bez limitu w Księgowości | panel biura | Księgowość, 60 zł netto |
| inFakt | automatycznie | AI w aplikacji i w inFakt Plus | bez danych | inFakt Plus od 59,90 zł netto |
| Faktura.pl | sprzeczne informacje na stronie | 20 dokumentów w OPTIMUM | paczka dokumentów, JPK | OPTIMUM od 24,99 zł netto |
| Fakturoza | automatycznie, w tle | AI, sprawdza NIP i IBAN | ZIP z PDF i XML | 0 zł, 5 kosztów miesięcznie |

Stan na 18.11.2026, według stron producentów: [Fakturownia](https://fakturownia.pl/import-wydatkow-z-ksef), [wFirma](https://pomoc.wfirma.pl/-import-faktur-zakupu-z-ksef-w-systemie-wfirma-pl), [inFakt](https://www.infakt.pl/infakt-plus/), [Faktura.pl](https://faktura.pl/cennik/), [Fakturoza](https://fakturoza.pl). Komentarza wewnętrznego dla biura księgowego i kopiowania danych do przelewu nie opisuje żaden z nich.

## Najważniejsze dane

| | |
|---|---|
| Faktury z KSeF | pobierane automatycznie, co 2 godziny |
| Zakres przy pierwszym połączeniu | ostatnie 30 dni |
| Pliki | PDF, JPG, PNG, do 50 naraz |
| Odczyt danych z pliku | automatyczny |
| Poprawianie odczytanych danych | nie, usuwasz fakturę i wgrywasz plik ponownie |
| Płatność | przycisk „Skopiuj dane” do przelewu w banku |
| Zlecanie przelewów z Firmowida | nie |
| Zapłacone gotówką | przycisk „Pomiń” |
| Koniec miesiąca | paczka ZIP dla biura księgowego |

Zobacz też: [Faktury i KSeF za 0 zł](/ksef) · [Skrzynka](/funkcje/skrzynka) · [Analiza kosztów](/funkcje/analiza) · [Obca faktura w KSeF: co zrobić przed zapłatą](/poradnik/obca-faktura-w-ksef) · [Numer KSeF w tytule przelewu od 2027 r.](/poradnik/numer-ksef-w-przelewie-2027)

## Najczęstsze pytania

### Czy Firmowid sam pobiera faktury kosztowe z KSeF?
Tak, co 2 godziny. Po połączeniu od razu pobiera faktury z ostatnich 30 dni.

### Ile kosztuje pobieranie faktur kosztowych z KSeF?
Nic, w każdym planie jest bez limitu. Limit dotyczy tylko odczytu z pliku. Szczegóły są w sekcji [Ile to kosztuje](#ile-to-kosztuje).

### Skąd wziąć faktury od zagranicznych dostawców?
Z maila albo z panelu dostawcy. Do Firmowida dodajesz je z pliku, tak jak opisuje sekcja [Faktury spoza KSeF](#faktury-spoza-ksef).

### Jak nie zaksięgować dwa razy tej samej faktury z KSeF i z PDF-u?
Firmowid rozpoznaje plik wgrany drugi raz oraz fakturę, która wcześniej przyszła z KSeF, i nie tworzy drugiego dokumentu.

### Czy Firmowid zapłaci fakturę?
Nie. Kopiujesz dane do przelewu i płacisz w banku.
