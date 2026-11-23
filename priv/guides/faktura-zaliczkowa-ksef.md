---
title: "Faktura zaliczkowa w KSeF: jak wystawić i rozliczyć zaliczkę"
description: "Fakturę zaliczkową dla firmy wystawia się w KSeF jako rodzaj ZAL, a końcową jako ROZ z numerami KSeF zaliczek. Przy zaliczce 100% końcowej nie trzeba."
published: 2026-11-24
updated: 2026-11-24
category: ksef-w-praktyce
---

Faktury zaliczkowe wystawia się w KSeF. Struktura e-faktury ma dla nich rodzaj ZAL, a dla faktury po dostawie albo usłudze, którą MF nazywa rozliczającą, rodzaj ROZ. Ta druga musi według ministerstwa zawierać „numery KSeF faktur wystawionych przed wydaniem towaru lub wykonaniem usługi (tj. numer KSeF faktur zaliczkowych)”.

| Dokument | Oznaczenie | Kiedy |
|---|---|---|
| Faktura zaliczkowa | ZAL | zapłata przed dostawą albo usługą |
| Faktura rozliczająca (końcowa) | ROZ | po dostawie albo usłudze |
| Faktura końcowa „zerowa” | ROZ | zaliczka 100%, dobrowolnie |
| Korekta faktury zaliczkowej | KOR_ZAL | błąd albo zwrot zaliczki |
| Korekta faktury rozliczającej | KOR_ROZ | błąd w fakturze końcowej |

## Czy fakturę zaliczkową trzeba wysyłać do KSeF?

Trzeba, gdy nabywcą jest firma. Pytanie o faktury zaliczkowe i końcowe zadała ministerstwu jednostka budżetowa zwolniona z VAT i dostała odpowiedź, że przy sprzedaży na rzecz podmiotu prowadzącego działalność gospodarczą „będzie zobligowana wystawić tą fakturę przy użyciu KSeF”. Proformy to nie dotyczy, bo MF nie uznaje jej za fakturę. Zamówienia też nie, o czym ministerstwo pisze: „Zamówienie może pojawić się jedynie jako element danych przy fakturze zaliczkowej (zgodnie z przepisami)”.

## Kiedy wystawia się fakturę zaliczkową?

| Sytuacja | Termin albo zasada | Podstawa |
|---|---|---|
| Otrzymano zaliczkę | faktura do 15. dnia miesiąca następującego po miesiącu wpłaty | art. 106i ust. 2 ustawy o VAT |
| Faktura przed wpłatą | najwcześniej 60 dni przed otrzymaniem zapłaty | art. 106i ust. 7 ustawy o VAT |
| Zaliczka i dostawa albo usługa w tym samym miesiącu | można nie wystawiać faktury zaliczkowej, tylko jedną fakturę z datą i kwotą otrzymanej zapłaty | art. 106b ust. 1a ustawy o VAT |

W tym trzecim przypadku dane o wpłacie trafiają do sekcji ZaliczkaCzesciowa zwykłej faktury.

## Jak wygląda faktura zaliczkowa w KSeF?

Nie ma w niej pozycji sprzedaży. Podręcznik wymienia wśród jej cech „wypełniony element Zamowienie” oraz „pominięty element FaWiersz”, czyli zamiast tego, co sprzedano, opisuje się to, co zamówiono.

| Element | Co zawiera |
|---|---|
| RodzajFaktury | ZAL |
| Data otrzymania zapłaty | pole P_6, gdy różni się od daty wystawienia |
| Kwota należności ogółem (P_15) | kwota otrzymanej zaliczki |
| Zamowienie | nazwa towaru lub usługi, ilość, wartość netto, stawka i kwota podatku, wartość zamówienia brutto |
| FakturaZaliczkowa | numery KSeF wcześniejszych faktur zaliczkowych, jeśli ta jest ostatnia i razem pokrywają całą zapłatę |

Podatek liczy się od otrzymanej kwoty brutto. MF podaje wzór: kwota podatku równa się kwocie zapłaty pomnożonej przez stawkę i podzielonej przez sumę 100 i stawki. Przy zaliczce 1 230 zł i stawce 23% daje to 230 zł VAT.

## Jak wystawić fakturę końcową w KSeF?

Faktura rozliczająca ma pełne pozycje sprzedaży, ale kwoty podsumowania i należność ogółem są według podręcznika „odnoszące się wyłącznie do kwoty pozostałej do zapłaty (czyli kwoty zapłaty końcowej)”. Musi też wskazać zaliczki: numery KSeF faktur zaliczkowych, a dla wystawionych poza systemem numery nadane przez sprzedawcę.

Z tego bierze się kłopot opisany na forum jednego z programów: „Teraz w KSeF widzi jedynie ostatnią kwotę płatności tej faktury końcowej i musi ręcznie podsumowywać pozostałe zaliczki, aby obliczyć kwotę zamówienia”. Podręcznik wskazuje, gdzie szukać całej kwoty: w fakturze rozliczającej element FaWiersz zawiera „pełne wartości dotyczące przedmiotu transakcji”.

## Czy przy zaliczce 100% trzeba wystawić fakturę końcową?

Nie trzeba. O sprzedawcy, który dostał całą zapłatę z góry i wystawił na nią fakturę zaliczkową, podręcznik pisze, że „podatnik ten nie ma obowiązku wystawienia po wydaniu towaru lub wykonaniu usługi faktury rozliczającej (końcowej)”. Zaraz potem dodaje: „Obowiązujące przepisy prawa podatkowego nie zabraniają jednak wystawiania faktur końcowych”. Taka faktura ma rodzaj ROZ, kwotę należności 0 i numer faktury zaliczkowej.

## Kilka zaliczek do jednego zamówienia

| Przypadek | Zasada z podręcznika MF |
|---|---|
| Kilka faktur zaliczkowych, które razem pokrywają całą cenę | ostatnia podaje numery KSeF poprzednich |
| Zaliczki nie pokrywają całej ceny | faktura rozliczająca z numerami KSeF wszystkich faktur zaliczkowych |
| Jedna faktura na kilka wpłat | sekcja ZaliczkaCzesciowa, do 31 wpłat z datą i kwotą każdej |

Numery wpisuje się w części FakturaZaliczkowa. Podręcznik podaje limit: „Element FakturaZaliczkowa może wystąpić w fakturze do 100 razy”.

## Czy można anulować fakturę zaliczkową?

Nie, bo żadnej faktury z numerem KSeF nie da się anulować. Błąd albo zwrot zaliczki dokumentuje faktura korygująca z oznaczeniem KOR_ZAL. Zasady korekt opisuje tekst [korekta faktury w KSeF](/poradnik/korekta-faktury-ksef), a przypadek, w którym wpłata okazała się wyższa niż cena, tekst [zaliczka wyższa niż cena końcowa](/poradnik/zaliczka-za-wysoka-faktura-rozliczeniowa).

## Faktura zaliczkowa w Firmowidzie

[Firmowid](/ksef), nasz program do faktur, wystawia fakturę zaliczkową w prostym wariancie: na zapłatę otrzymaną z góry. W kreatorze przy tym rodzaju faktury jest podpowiedź: „Opłacone z góry: w następnym kroku podasz datę otrzymania zapłaty, bez terminu płatności”. Faktura od razu ma status opłaconej.

| Co | W Firmowidzie |
|---|---|
| Faktura zaliczkowa (ZAL) | tak, na zapłatę otrzymaną z góry |
| Faktura rozliczająca (ROZ) | nie |
| Korekta faktury zaliczkowej (KOR_ZAL) | nie |

Przy zaliczce 100% to wystarcza, bo faktura końcowa nie jest wtedy obowiązkowa. Przy zaliczkach częściowych fakturę rozliczającą trzeba wystawić w innym narzędziu. Korekty też: program odpowiada na próbę komunikatem „Firmowid nie pozwala edytować ani korygować faktury zaliczkowej”.

![Faktura zaliczkowa ma w KSeF oznaczenie ZAL i dokumentuje zapłatę przed dostawą albo usługą, faktura rozliczająca, czyli końcowa, oznaczenie ROZ i powstaje po dostawie albo usłudze. Faktura końcowa zerowa przy zaliczce 100% jest dobrowolna. Korekty mają oznaczenia KOR_ZAL i KOR_ROZ. Faktura końcowa podaje numery KSeF faktur zaliczkowych.](/images/guides/faktura-zaliczkowa-ksef-zal-roz.webp)

## Źródła

- [MF: Podręcznik KSeF 2.0, cz. II, rozdziały 2.6, 2.7, 2.8, 2.13.5 i 4.1](https://ksef.podatki.gov.pl/media/rronoxyt/podrecznik-ksef-20-cz-ii-wystawianie-i-otrzymywanie-faktur-w-ksef-06082026.pdf) (wersja z sierpnia 2026 r.), dostęp 23.11.2026.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/) (wersja z 10.11.2026), dostęp 23.11.2026.
- Ustawa z 11 marca 2004 r. o podatku od towarów i usług, art. 106b ust. 1a, art. 106f, art. 106i ust. 2 i 7.

*To informacja ogólna, nie porada podatkowa.*
