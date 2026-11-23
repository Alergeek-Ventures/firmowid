---
title: "Zmiana programu do faktur przed 2027: KSeF, numeracja, dane"
description: "Program do faktur można zmienić w każdej chwili, bo faktury z numerem KSeF zostają w systemie 10 lat. Przenosisz kontrahentów, numerację i połączenie."
published: 2026-11-26
updated: 2026-11-26
category: wybor-programu
---

Fakturownię zamieniliśmy na Firmowida, bo na początku firmy była dla nas zbyt przytłaczająca i brakowało nam niektórych funkcji. Nie mieliśmy przy tym żadnego kłopotu. Dziś jest jeszcze prościej: można mieć parę programów do faktur podłączonych do jednego konta w KSeF, co oznacza, że przenoszenie firmy może być stopniowe. W trakcie przenoszenia wystarczy korzystać z dwóch naraz.

Same faktury zostają tam, gdzie były. Podręcznik KSeF 2.0 podaje, że w systemie ministerstwa „faktury są przechowywane przez okres 10 lat od końca roku, w którym zostały wystawione”, a „W każdej bowiem chwili sprzedawca lub nabywca mogą uwierzytelnić się w systemie i pobrać daną fakturę”.

| Dane | Gdzie są |
|---|---|
| Faktury z numerem KSeF | KSeF, 10 lat |
| Faktury wystawione poza KSeF | stary program |
| Kontrahenci | stary program |
| Numeracja | sprzedawca |
| Token i certyfikat | KSeF |

## Czy można zmienić program do faktur?

Ministerstwo Finansów nie wiąże podatnika z żadnym narzędziem i w podręczniku wymienia obok siebie Aplikację Podatnika KSeF oraz programy komercyjne połączone z API. O samych fakturach pisze: „Nie ma możliwości, aby faktura wystawiona w KSeF zaginęła”.

Na forum jednego z programów użytkownik opisał w kwietniu 2026 r. sytuację odwrotną: „Dodam, że mam problem z utratą faktur sprzedaży na skutek awarii bazy danych”.

## Co z numeracją faktur po zmianie programu?

Art. 106e ust. 1 pkt 2 ustawy o VAT wymaga, żeby faktura zawierała, jak streszcza to podręcznik, „kolejny numer faktury nadany w ramach jednej lub więcej serii, który w sposób jednoznaczny identyfikuje fakturę”. Przepis mówi o serii, nie o programie, więc po zmianie narzędzia stosuje się albo dalszy ciąg dotychczasowej serii, albo nową serię.

Kolejności numerów KSeF nie sprawdza. O fakturach przesłanych nie po kolei podręcznik pisze, że „nie będzie to przesłanką odrzucenia faktury przez system”.

## Jak przenieść kontrahentów?

W 2017 r. na forum elektroda.pl użytkownik starego programu pytał: „Pytanie, czy da się przenieść jakoś bazę danych z tego programu do jakiegoś innego darmowego???”. Miesiąc później inny odpisał w tym samym wątku: „Kontrahentów przeniosłem poprzez eksport do pliku xml i import do abc”.

| Program | Co musi umieć |
|---|---|
| Stary | eksport kontrahentów do pliku |
| Nowy | import kontrahentów z pliku |

W KSeF listy kontrahentów nie ma, są tylko dane nabywców na fakturach.

## Jak połączyć nowy program z KSeF?

Tokenem albo certyfikatem KSeF. Według podręcznika „Wygenerowany token pozostaje ważny do czasu jego unieważnienia przez użytkownika”, a jednocześnie „Nie są przewidziane ograniczenia systemowe co do liczby posiadanych lub używanych tokenów”. Stary i nowy program mogą więc być połączone w tym samym czasie i stąd bierze się stopniowe przejście, o którym piszemy na początku. MF udostępnia na stronie Aplikacji Podatnika instrukcje wideo „Generowanie tokena” i „Unieważnienie tokena”. O certyfikatach jest osobny tekst: [certyfikat KSeF typu 1 i 2](/poradnik/certyfikat-ksef-typ-1-i-2).

## Czego nie znajdziesz w KSeF po zmianie programu

| Dokument | W KSeF |
|---|---|
| Faktura wystawiona poza KSeF | nie |
| Proforma | nie |
| Załącznik PDF albo zdjęcie | nie |
| Nota obciążeniowa albo uznaniowa | nie |

Podręcznik wymienia je wprost: „w KSeF nie jest możliwe wystawienie faktury pro forma, dowodu wewnętrznego, noty uznaniowej czy noty obciążeniowej”, a o plikach dodaje: „Innego rodzaju załączniki, np. w postaci plików pdf czy zdjęć nie są przyjmowane przez system”.

## Zmiana programu na Firmowida

[Firmowid](/ksef), nasz program, pobiera z KSeF faktury z ostatnich 30 dni. Starszych nie pobiera.

| Co | W Firmowidzie |
|---|---|
| Faktury z KSeF | ostatnie 30 dni, potem co 2 godziny |
| Faktury ze starego programu | do wglądu |
| Import kontrahentów z pliku | nie |
| Kontrahent po NIP | tak, „Pobierz dane” |
| Numeracja | dowolna seria |

Numer wpisuje się ręcznie. Ostrzeżenia są dwa: „Numer tworzy lukę w numeracji” i „Numer faktury już istnieje”.

## Co sprawdzić przed wyborem nowego programu

Z naszego doświadczenia jedno: sprawdź, czy dany program nie będzie Cię ograniczał w przyszłości ani nie generował zbyt dużych kosztów wraz z rozwojem firmy.

Porównanie planów bez opłat jest w tekście [darmowe programy do KSeF](/poradnik/darmowe-programy-ksef), a lista kryteriów w tekście [jak wybrać program do faktur](/poradnik/jak-wybrac-program-do-faktur).

![Przy zmianie programu do faktur faktury z numerem KSeF zostają w KSeF przez 10 lat, faktury wystawione poza KSeF i kontrahenci są w starym programie, numerację ustala sprzedawca, a token i certyfikat są w KSeF. Do jednego konta w KSeF można podłączyć kilka programów naraz, więc przejście może być stopniowe.](/images/guides/zmiana-programu-do-faktur-gdzie-sa-dane.webp)

## Źródła

- [MF: Podręcznik KSeF 2.0, cz. I](https://ksef.podatki.gov.pl/media/dmrfdixs/podrecznik-ksef-20-cz-i-rozpoczecie-korzystania-z-ksef-06082026.pdf) (wersja z sierpnia 2026 r., przechowywanie faktur, tokeny, załączniki), dostęp 23.11.2026.
- [MF: Podręcznik KSeF 2.0, cz. II, rozdział 1.6.7](https://ksef.podatki.gov.pl/media/rronoxyt/podrecznik-ksef-20-cz-ii-wystawianie-i-otrzymywanie-faktur-w-ksef-06082026.pdf) (wersja z sierpnia 2026 r., numeracja), dostęp 23.11.2026.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/) (proforma), dostęp 23.11.2026.

*To informacja ogólna, nie porada podatkowa.*
