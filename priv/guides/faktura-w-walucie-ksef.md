---
title: "Faktura w walucie obcej w KSeF: euro, kurs i VAT w złotych"
description: "W KSeF można wystawić fakturę w euro i w innej walucie, także dla polskiej firmy. Kwoty zostają w walucie, a sam VAT przelicza się na złote po kursie NBP."
published: 2026-11-28
updated: 2026-11-28
category: ksef-w-praktyce
---

Fakturę w euro, dolarach albo innej walucie wystawia się w KSeF tak jak złotową. Rozdział podręcznika KSeF 2.0 o fakturze walutowej zaczyna się od zdania: „Struktura logiczna FA(3) umożliwia podatnikom wystawianie faktur w walucie obcej”. W złotych musi być podana tylko kwota podatku.

| Co | Pole w FA(3) | Wartość |
|---|---|---|
| Waluta faktury | KodWaluty | kod ISO 4217, np. EUR |
| Netto i VAT przy stawce 23% | P_13_1 i P_14_1 | w walucie obcej |
| VAT 23% w złotych | P_14_1W | w PLN |
| Kurs dla pozycji | KursWaluty | do 6 miejsc po kropce |
| Kurs na fakturze zaliczkowej | KursWalutyZ | do 6 miejsc po kropce |

## Czy w KSeF można wystawić fakturę w euro?

Można, także wtedy, gdy nabywcą jest polska firma. Ministerstwo Finansów dostało pytanie, jak będą wyglądały faktury w walucie obcej dla kontrahentów polskich, i odpisało: „W takiej fakturze kwoty określone są wyłącznie w walucie obcej i jedynie kwota podatku w polu P_14_xW przeliczona jest na złotówki zgodnie z art. 106e ust. 11 ustawy o VAT”.

Dla stawek 8% i 5% są osobne pola, P_14_2W i P_14_3W. Podręcznik wymienia też ryczałt dla taksówek osobowych z polem P_14_4W.

## Jaki kurs waluty na fakturze?

Kurs wynika z art. 31a ustawy o VAT, a nie z przepisów o KSeF.

| Kiedy powstaje faktura | Kurs do przeliczenia |
|---|---|
| W dniu powstania obowiązku podatkowego albo później | średni NBP z ostatniego dnia roboczego przed tym dniem |
| Przed powstaniem obowiązku podatkowego | średni NBP z ostatniego dnia roboczego przed dniem wystawienia |
| Wybór podatnika | kurs Europejskiego Banku Centralnego z tych samych dni |

Sam kurs można pokazać w pliku faktury. Podręcznik: „Dodatkowo, na fakturze możliwe jest wskazanie kursu waluty właściwego dla danej pozycji faktury”. Służy do tego pole KursWaluty w wierszu, a na fakturze zaliczkowej KursWalutyZ.

## Faktura w złotych z ceną ustaloną w euro

To inny przypadek i inne pola. MF wyjaśnia: „Pola KursUmowny i WalutaUmowna dotyczą przypadków, gdy faktura wystawiona jest w złotówkach”. Strony wpisują tam kurs, po którym same przeliczyły cenę z umowy. Ministerstwo zalicza tu także fakturę dwuwalutową, czyli taką, w której wszystkie kwoty są jednocześnie w złotych i w walucie obcej.

## Jak wystawić fakturę w KSeF dla klienta zagranicznego?

Na pytanie o klienta spoza UE ministerstwo odpowiada: „Wystawiasz ją w KSeF, a następnie przekazujesz nabywcy w ustalony sposób (np. PDF)”.

Podręcznik podaje, od kiedy liczy się odbiór: „za datę otrzymania tej faktury uznaje się datę jej faktycznego otrzymania przez tego nabywcę”. W przykładzie MF numer KSeF nadano 1 lutego 2026 r., a PDF dotarł e-mailem 3 lutego.

## Gdzie wpisać zagraniczny numer podatkowy?

Na forum jednego z programów do faktur padło pytanie: „Gdzie wpisać nip zagraniczny, jeśli do KSEF przechodzi 10 cyfr, a np wczesniej pisalismy DE123456789 lub dla Holandii łącznie 14 z przedrostkiem NL?”. Pole NIP jest tylko dla numerów polskich. Zagraniczne mają własne pola w danych nabywcy.

| Nabywca | Pola | Zapis według MF |
|---|---|---|
| Polska firma | NIP | 9999999999, bez kresek |
| Firma z UE, WDT albo usługa z art. 28b | KodUE i NrVatUE | DE i 9999999999 |
| Firma spoza UE | KodKraju i NrID | kod kraju i numer |
| Bez identyfikatora | BrakID | 1 |

Prefiks „PL” sprzedawcy też ma własne miejsce. Podręcznik: „kod należy wyodrębnić w osobnym polu Podmiot1/PrefiksPodatnika”. Zapis PL9999999999 w polu NIP podaje jako nieprawidłowy.

## Czy faktura eksportowa musi być w KSeF?

Podręcznik potwierdza: „W KSeF można wystawić m.in. faktury dokumentujące transakcje tj. WDT i eksport towarów”. Różnią się oznaczeniem stawki 0%.

| Transakcja | Stawka w wierszu (P_12) | Suma sprzedaży |
|---|---|---|
| Eksport towarów | 0 EX | P_13_6_3 |
| WDT | 0 WDT | P_13_6_2 |

Usługi dla firm z Unii opisuje tekst [faktura dla klienta z UE w KSeF](/poradnik/faktura-dla-firmy-z-ue-ksef).

## Czy faktura w KSeF może być po angielsku?

Na pytanie, czy wizualizacja może być po angielsku albo dwujęzyczna, MF odpowiada: „Tak. Wizualizacja może być w innym języku, ale musi być zgodna pod względem merytorycznym (po przetłumaczeniu) z danymi w pliku XML przesłanym do KSeF”. Sam plik też nie musi być po polsku. Według podręcznika „nie ma również przeszkód, aby plik XML przesyłany do KSeF zawierał dane przygotowane w języku obcym”.

## Faktura walutowa w Firmowidzie

[Firmowid](/ksef), nasz program do faktur, wystawia faktury w 32 walutach obcych z tabeli A NBP. Lista walut ma grupy „Popularne” (PLN, EUR, USD) i „Wszystkie”. Dla nabywcy spoza Polski program ustawia EUR.

Kurs pobiera sam. Jest to średni kurs NBP z ostatniego dnia roboczego przed wcześniejszą z dat wystawienia i sprzedaży. Na PDF jest sekcja „Przewalutowanie / Currency conversion” z numerem tabeli i datą kursu. Faktura dla nabywcy spoza Polski jest dwujęzyczna, po polsku i angielsku. Pod kodem QR ma podpis „View in KSeF”.

Czego nie ma. Dla polskiej firmy z NIP pole waluty jest zablokowane i zostaje PLN. Kursu EBC program nie stosuje. Wersji tylko po angielsku nie ma. Gdy NBP nie odpowiada, w miejscu kursu widać komunikat „Nie udało się pobrać kursu NBP. Spróbuj ponownie za chwilę”.

![Faktura w walucie obcej w KSeF: walutę wskazuje pole KodWaluty z kodem ISO 4217, na przykład EUR. Kwoty netto i VAT przy stawce 23% w polach P_13_1 i P_14_1 są w walucie obcej, a VAT w złotych trafia do pola P_14_1W. Kurs dla pozycji podaje się w polu KursWaluty, do 6 miejsc po kropce. Do przeliczenia służy średni kurs NBP z ostatniego dnia roboczego przed powstaniem obowiązku podatkowego.](/images/guides/faktura-w-walucie-ksef-pola.webp)

## Źródła

- [MF: Podręcznik KSeF 2.0, cz. II, rozdziały 1.6.5, 2.1, 2.5, 2.11 i 5.1](https://ksef.podatki.gov.pl/media/rronoxyt/podrecznik-ksef-20-cz-ii-wystawianie-i-otrzymywanie-faktur-w-ksef-06082026.pdf) (wersja z sierpnia 2026 r.), dostęp 23.11.2026.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/) (wersja z 10.11.2026), dostęp 23.11.2026.
- Ustawa z 11 marca 2004 r. o podatku od towarów i usług, art. 31a i art. 106e ust. 11.

*To informacja ogólna, nie porada podatkowa.*
