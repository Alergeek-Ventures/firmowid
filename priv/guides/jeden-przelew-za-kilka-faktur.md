---
title: "Jeden przelew za kilka faktur: tytuł, raty i rozliczenie"
description: "Kilka faktur można opłacić jednym przelewem. Od 2027 r. czynni podatnicy VAT wpisują w tytule numery KSeF albo identyfikator zbiorczy, także przy racie."
published: 2026-11-26
updated: 2026-11-26
category: bank-i-platnosci
---

Kilka faktur można opłacić jednym przelewem. KSeF tego nie reguluje, bo według Ministerstwa Finansów „nie jest systemem służącym do dokonywania płatności za faktury”. Od 1 stycznia 2027 r. zmienia się tylko tytuł takiego przelewu między czynnymi podatnikami VAT.

| Przelew | Tytuł od 2027 r. |
|---|---|
| Za 2 albo 3 faktury | numery KSeF albo identyfikator zbiorczy |
| Za więcej faktur | identyfikator zbiorczy, do 500 faktur |
| Z ratą jednej z faktur | identyfikator zbiorczy, kwota raty opcjonalnie |

Kogo ten obowiązek obejmuje, opisuje tekst [numer KSeF w przelewie od 2027 r.](/poradnik/numer-ksef-w-przelewie-2027)

## Czy można zapłacić kilka faktur jednym przelewem?

Można. Ministerstwo odpowiadało firmie, która płaci jednym przelewem za 6 faktur. W tytule taki podatnik poda „identyfikator zbiorczy (obejmujący wszystkie ww. faktury) lub kilka numerów KSeF lub kilka identyfikatorów zbiorczych”. Limit podaje inna odpowiedź: „Jeden identyfikator zbiorczy może obejmować maksymalnie 500 faktur z możliwością indywidualnego zwiększenia limitu na uzasadniony wniosek”.

## Czy jednym przelewem można zapłacić kilku sprzedawcom?

Nie. Przelew trafia na jedno konto, a identyfikator zbiorczy też ma jednego sprzedawcę. MF: „W ramach jednego identyfikatora muszą wystąpić faktury, w których sprzedawca zawsze jest ten sam”. Nabywcy mogą być różni.

## Czy fakturę można zapłacić w ratach?

Na pytanie o częściową płatność MF odpowiada: „System umożliwia zawarcie w treści faktury informacji o płatności za fakturę, w tym o płatności częściowej”. Chodzi o wpłaty sprzed wystawienia faktury. Schemat FA(3) ma na nie trzy pola.

| Pole | Opis w schemacie |
|---|---|
| Zaplacono | „1 - zapłacono” |
| ZnacznikZaplatyCzesciowej | „1 - zapłacono w części” |
| ZaplataCzesciowa | „Dane zapłat częściowych”, do 100 wpisów |

Późniejsze raty faktury w KSeF nie zmieniają. Rata może za to wejść do przelewu zbiorczego. MF: „w ramach identyfikatora zbiorczego można wskazać dodatkowo kwotę (np. kwotę płatności częściowej – raty), walutę oraz opis faktury. Nie jest to jednak obowiązkowe”.

Tę samą fakturę da się wskazać w kolejnych przelewach. Według ministerstwa „Jeden numer KSeF może występować maks. w 132 identyfikatorach zbiorczych w ramach jednego kontekstu”.

## Czy w KSeF widać, że faktura jest opłacona?

Nie widać. MF: „KSeF służy do wystawiania, przesyłania, odbierania i przechowywania faktur”. Wpłaty są w banku albo w programie do faktur.

## Tytuł przelewu w nietypowych sytuacjach

| Sytuacja | Co w tytule według MF |
|---|---|
| Płaci faktor | numer KSeF albo identyfikator zbiorczy |
| Awaria KSeF w dniu płatności | numery KSeF faktur |
| Tytuł ma 140 znaków | kilka numerów albo identyfikator |

O faktorze ministerstwo pisze: „jeśli w imieniu nabywcy, płatności dokonuje podmiot trzeci to również powinien podać numer KSeF lub zbiorczy identyfikator”.

## Skąd sprzedawca wie, za co dostał przelew?

Z tytułu. Ministerstwo: „Identyfikator zbiorczy podany przez nabywcę dokonującego płatności będzie widoczny dla sprzedawcy, który otrzyma tę płatność”. Nabywca nie musi więc wysyłać osobno listy faktur. Do końca 2026 r. w tytule są zwykle numery nadane przez sprzedawcę.

## Jeden przelew za kilka faktur w Firmowidzie

[Firmowid](/funkcje/bank), nasz program, pobiera przelewy z banku i sam łączy je z fakturami. Automat łączy jeden przelew z jedną fakturą. Jak to działa, opisuje tekst [dopasowanie przelewów do faktur](/poradnik/dopasowanie-przelewow-do-faktur).

Przelew zbiorczy rozlicza się przez asystenta AI. Na stronie transakcji jest przycisk „Zapytaj”. Rozmowa zaczyna się od gotowych podpowiedzi, między innymi „To był przelew zbiorczy za kilka dokumentów” i „Ta transakcja opłaciła kilka faktur z poprzedniego miesiąca”. Asystent AI przypina wtedy jedną wpłatę do kilku faktur.

Czego nie ma. Program nie liczy, ile zostało do zapłaty. Faktura z jedną przypiętą wpłatą ma status opłaconej, także gdy była to rata. Przy kilku wpłatach strona faktury pokazuje ich sumę „Razem”. Raty nie ma też wśród podpowiedzi, bo program szuka wpłat o kwocie zbliżonej do kwoty faktury.

![Jeden przelew za kilka faktur od 1 stycznia 2027 r.: za 2 albo 3 faktury w tytule są numery KSeF albo identyfikator zbiorczy, za więcej faktur identyfikator zbiorczy, który obejmuje do 500 faktur. Przy racie jednej z faktur kwotę raty można dodać do identyfikatora zbiorczego. Kilku sprzedawcom płaci się osobnymi przelewami, bo identyfikator zbiorczy obejmuje faktury jednego sprzedawcy.](/images/guides/jeden-przelew-za-kilka-faktur-tytul.webp)

## Źródła

- [MF: Pytania i odpowiedzi KSeF 2.0](https://ksef.podatki.gov.pl/pytania-i-odpowiedzi-ksef-20/) (wersja z 10.11.2026), dostęp 24.11.2026.
- Struktura logiczna FA(3), element Platnosc: pola Zaplacono, ZnacznikZaplatyCzesciowej i ZaplataCzesciowa (schemat MF).
- Ustawa z 11 marca 2004 r. o podatku od towarów i usług, art. 108g.

*To informacja ogólna, nie porada podatkowa.*
