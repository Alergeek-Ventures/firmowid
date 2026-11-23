---
title: "Numer KSeF w JPK: od kiedy i co wpisać, gdy go nie ma"
description: "Numer KSeF podaje się w JPK_VAT od rozliczenia za luty 2026 r., dla faktur sprzedaży i zakupu. Gdy faktura go nie ma, wpisujesz OFF, BFK albo DI."
published: 2026-11-27
updated: 2026-11-27
category: ksef-w-praktyce
---

Numer KSeF wpisuje się w JPK_VAT od rozliczenia za luty 2026 r. Dotyczy to faktur sprzedaży i faktur zakupu. Podręcznik Ministerstwa Finansów ujmuje to tak: podatnik „ma obowiązek podawać numery KSeF wystawionych faktur sprzedażowych i otrzymywanych faktur zakupowych, a w przypadku braku nr KSeF ma obowiązek stosowania odpowiednich oznaczeń”.

| Co wpisać | Kiedy |
|---|---|
| NrKSeF | faktura ma numer KSeF w dniu złożenia JPK |
| OFF | faktura z awarii KSeF, jeszcze bez numeru |
| BFK | faktura wystawiona poza KSeF |
| DI | dowód inny niż faktura; faktura offline24 bez numeru |

## Od kiedy numer KSeF w JPK VAT?

Ministerstwo podało to w komunikacie z 23 grudnia 2025 r.: „19 grudnia 2025 r. zostały opublikowane nowe wersje struktur JPK_V7M(3) oraz JPK_V7K(3), obowiązujące od 1 lutego 2026 r.”. Pierwsza obsługuje rozliczenia miesięczne, druga kwartalne. Obie mają nowe pole na numer KSeF albo jedno z trzech oznaczeń.

## Czy numer KSeF jest obowiązkowy w JPK?

Obowiązkowe jest wypełnienie pola. Broszura MF o JPK_VAT mówi: „Należy wprowadzić numer KSeF albo wybrać oznaczenie”. Sam numer podaje się wtedy, gdy faktura już go ma. W broszurze brzmi to tak: „pole uzupełnia się, gdy na dzień złożenia JPK_VAT faktura ma nadany nr KSeF”.

Liczy się więc dzień wysłania pliku JPK, nie dzień wystawienia faktury. Faktura offline, która zdążyła dostać numer przed złożeniem JPK, trafia do ewidencji z numerem.

## Co wpisać, gdy faktura nie ma numeru KSeF?

| Oznaczenie | Definicja z broszury MF | Korekta JPK po nadaniu numeru |
|---|---|---|
| OFF | faktura wystawiona w trybie awarii KSeF | nie |
| BFK | faktura elektroniczna albo papierowa wystawiona poza KSeF | nie dotyczy |
| DI | dowód inny niż faktura; także faktura offline24 i z niedostępności systemu, jeszcze bez numeru | tak, przy offline24 i niedostępności |

Różnica między OFF a DI jest w ostatniej kolumnie. O fakturze z awarii broszura pisze: „Podatnik nie ma obowiązku dokonania korekty ewidencji JPK_VAT po uzyskaniu numeru KSeF”. O fakturze offline24 oznaczonej DI: „po uzyskaniu numeru KSeF podatnik powinien skorygować zastosowane oznaczenie poprzez wprowadzenie nadanego numeru KSeF”.

Więcej o samych trybach: [tryb offline w KSeF](/poradnik/tryb-offline-ksef).

## Jak oznaczyć w JPK fakturę dla osoby fizycznej?

Fakturę dla konsumenta wystawioną poza KSeF oznacza się BFK. Broszura podaje ten przypadek jako przykład: oznaczenie dotyczy faktur wystawionych poza systemem, „np. faktura na rzecz konsumenta lub faktury wystawione przed obowiązkiem fakturowania za pośrednictwem KSeF”. Fakturę konsumencką wystawioną dobrowolnie w KSeF wpisuje się z jej numerem.

Faktura do paragonu ma osobne oznaczenie FP w polu typu dokumentu. Zasady dla konsumentów opisuje tekst [faktura dla osoby prywatnej a KSeF](/poradnik/faktura-dla-osoby-prywatnej-ksef).

## Jak wykazać w JPK korektę błędnego numeru faktury?

To pytanie z forum gofin.pl, z września 2026 r.: „No i przyszła kryska na matyska, też się pomyliłam w numerze faktury”. Broszura opisuje taki przypadek w zasadach ogólnych. Błędny wpis, który nie zmienia kwot podatku, poprawia się „poprzez jego wystornowanie, tj. wpisanie ze znakiem przeciwnym całego wpisu oraz ponowne dodanie prawidłowego wpisu”. Jeśli plik za dany okres nie został jeszcze wysłany, wystarcza jeden zapis z poprawnymi danymi.

Korektę całej ewidencji składa się jako nowy, kompletny plik. Broszura zastrzega: „Niedopuszczalne jest złożenie pliku zawierającego jedynie dane korygowane”.

## Czy za błędne oznaczenie w JPK grozi kara?

Nie od razu. Ministerstwo odpowiada, że „kary za błędnie wypełnione pliki JPK_VAT z deklaracją nie mają charakteru automatycznego”, a urząd najpierw wzywa do poprawienia pliku. Sprawy mają być rozpatrywane indywidualnie, z uwzględnieniem tego, że błąd wiąże się z wdrożeniem KSeF.

## Numer KSeF w JPK a JPK_FA

JPK_FA to inny plik, wysyłany na żądanie urzędu. MF pisze: „Obowiązek przekazywania plików JPK_FA nie będzie dotyczył faktur wystawionych w KSeF”. Dla faktur wystawionych poza systemem urząd nadal może go zażądać.

## Numer KSeF w JPK a Firmowid

Firmowid plików JPK nie tworzy. Numer KSeF jest przy każdej fakturze w polu „Identyfikator KSeF” i pod kodem QR na PDF. Dokumenty z miesiąca wysyła się biuru księgowemu w jednej paczce: [paczka dla biura księgowego](/pomoc/paczka-dla-biura-ksiegowego).

![W JPK_VAT od rozliczenia za luty 2026 r. wpisuje się numer KSeF, gdy faktura ma go w dniu złożenia pliku. OFF oznacza fakturę z awarii KSeF jeszcze bez numeru, BFK fakturę wystawioną poza KSeF, a DI dowód inny niż faktura oraz fakturę offline24 bez numeru. Po nadaniu numeru fakturze offline24 oznaczenie DI poprawia się na numer KSeF.](/images/guides/numer-ksef-w-jpk-oznaczenia.webp)

## Źródła

- [MF: Broszura informacyjna dot. struktury JPK_VAT z deklaracją, JPK_V7M(3) i JPK_V7K(3)](https://podatki.gov.pl/media/wgbkrejs/broszura-jpk_vat-z-deklaracj%C4%85-od-1-lutego-2026-r.pdf) (styczeń 2026 r.), dostęp 23.11.2026.
- [MF: Nowe wzory struktur JPK_VAT dostępne na ePUAP](https://www.gov.pl/web/finanse/nowe-wzory-struktur-jpkvat-dostepne-na-epuap) (23.12.2025), dostęp 23.11.2026.
- [MF: Podręcznik KSeF 2.0, cz. II, rozdział 4.1.6](https://ksef.podatki.gov.pl/media/rronoxyt/podrecznik-ksef-20-cz-ii-wystawianie-i-otrzymywanie-faktur-w-ksef-06082026.pdf) (wersja z sierpnia 2026 r.), dostęp 23.11.2026.
- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/) (wersja z 10.11.2026), dostęp 23.11.2026.

*To informacja ogólna, nie porada podatkowa.*
