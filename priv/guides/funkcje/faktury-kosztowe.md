---
title: "Faktury kosztowe z KSeF, ze skanu i z PDF"
description: "Faktury kosztowe z KSeF przychodzą same co 2 godziny, papierowe skanujesz, a brakujące widać przy przelewie. Porównanie z Fakturownią, inFaktem i wFirmą."
published: 2026-11-18
updated: 2026-11-18
landing:
  kicker: "Funkcje · Faktury kosztowe"
  note: "same przychodzą z KSeF"
  facts:
    - label: "Faktury z KSeF"
      value: "pobierane co 2 godziny"
    - label: "Pliki"
      value: "PDF, JPG, PNG, do 50 naraz"
    - label: "Koniec miesiąca"
      value: "paczka ZIP dla biura księgowego"
---

Wcześniej faktury kosztowe gromadziły się na mailu. Często płaciliśmy w innym terminie, niż te maile przychodziły, więc na końcu miesiąca musieliśmy w ogóle szukać tych faktur po mailach. To było słabe. Część była na papierze, musieliśmy to skanować i coś się gubiło.

## Teraz

Faktury z KSeF przychodzą same. Jeśli brakuje jakiejś zagranicznej faktury, widzimy to od razu, bo przelew stoi bez dokumentu. Wtedy ściągamy fakturę i dodajemy ją z pliku. Papierowe faktury zazwyczaj skanujemy prosto do Firmowida.

![Lista faktur zakupowych z KSeF i wgranych z pliku](/images/guides/funkcje/faktury-zakupowe.webp)

## Komentarz dla biura księgowego

Komentarz wewnętrzny jest dla biura księgowego, bo sama faktura bywa mało informacyjna, czasem to kilka słów. Kiedyś dopisywaliśmy to ręcznie, teraz robimy to z pomocą AI, która uczy się na poprzednich fakturach i kategoriach firm. To naprawdę mocno uprzyjemnia pracę, a dokumenty mają kontekst, który przydaje się później w analizie.

![Faktura kosztowa z komentarzem, danymi do przelewu i proponowanym przelewem](/images/guides/funkcje/kosztowa-sugestie.webp)

## Najważniejsze dane

| | |
|---|---|
| Faktury z KSeF | pobierane same, co 2 godziny |
| Pliki | PDF, JPG, PNG, do 50 naraz |
| Telefon | zdjęcie aparatem |
| Odczyt danych z pliku | automatyczny; poprawka przez ponowne wgranie |
| Duplikaty | wykrywane po zawartości pliku i numerze KSeF |
| Płatność | przycisk „Skopiuj dane” do przelewu w banku |
| Zapłacone gotówką | przycisk „Pomiń” |
| Koniec miesiąca | paczka ZIP dla biura księgowego |

## Porównanie z innymi programami

| Program | Koszty z KSeF | Odczyt z pliku (OCR) | Paczka dla biura księgowego | Najtańszy plan z OCR |
|---|---|---|---|---|
| Firmowid | same, co 2 godziny | tak | ZIP za miesiąc | 0 zł, plan Darmowy |
| Fakturownia | same, częstotliwość niepodana | 3 do 10 skanów miesięcznie, więcej w paczkach | eksport do Raks i Optima w planie Pro | Start, 9,99 zł netto |
| wFirma | raz na dobę, nocą | Magic Box, bez limitu w Księgowości | panel biura | Księgowość, 60 zł netto |
| inFakt | same | AI w aplikacji i w inFakt Plus | bez danych | inFakt Plus od 59,90 zł netto |
| Faktura.pl | sprzeczne informacje na stronie | 20 dokumentów w OPTIMUM | paczka dokumentów, JPK | OPTIMUM od 24,99 zł netto |
| Fakturoza | same, w tle | AI, sprawdza NIP i IBAN | ZIP z PDF i XML | 0 zł, 5 kosztów miesięcznie |

Stan na 18.11.2026, według stron producentów: [Fakturownia](https://fakturownia.pl/import-wydatkow-z-ksef), [wFirma](https://pomoc.wfirma.pl/-import-faktur-zakupu-z-ksef-w-systemie-wfirma-pl), [inFakt](https://www.infakt.pl/infakt-plus/), [Faktura.pl](https://faktura.pl/cennik/), [Fakturoza](https://fakturoza.pl). Komentarza wewnętrznego dla biura księgowego i kopiowania danych do przelewu nie opisuje żaden z nich.

Zobacz też: [Pobieranie faktur z KSeF](/pomoc/pobieranie-faktur-z-ksef) · [Paczka dokumentów dla biura księgowego](/pomoc/paczka-dla-biura-ksiegowego) · [Bank i dopasowanie przelewów](/funkcje/bank)

## Najczęstsze pytania

### Czy Firmowid sam pobiera faktury kosztowe z KSeF?
Tak, co 2 godziny.

### Skąd wziąć faktury od zagranicznych dostawców?
Z maila albo z panelu dostawcy. Do Firmowida dodajesz je z pliku.

### Jak nie zaksięgować dwa razy tej samej faktury z KSeF i z PDF-u?
Firmowid wykrywa duplikat po numerze KSeF i po zawartości pliku.

### Czy Firmowid zapłaci fakturę?
Nie. Kopiujesz dane do przelewu i płacisz w banku.
