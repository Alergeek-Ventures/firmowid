---
title: "Zaliczka wyższa niż cena końcowa: korekta w KSeF"
description: "Zaliczka przewyższa cenę końcową? Sprawdź, którą fakturę skorygować w KSeF, jak zwrócić różnicę i jakie dane przygotować."
published: 2026-11-06
updated: 2026-11-27
category: ksef-w-praktyce
---

Jeżeli zafakturowana zaliczka jest wyższa niż ostateczna cena, różnicę zwracasz klientowi, a fakturę zaliczkową zmniejszasz fakturą korygującą. Art. 106f ust. 3 ustawy o VAT przewiduje fakturę końcową wtedy, gdy wcześniejsze faktury nie objęły całej zapłaty. Tutaj jest odwrotnie: wpłata przewyższa cenę towaru albo usługi. Korekta wystawiona w KSeF musi wskazywać fakturę pierwotną, w tym jej numer KSeF.

## Przykład

| Pozycja | Kwota brutto |
|---|---:|
| Zafakturowana zaliczka | 1 230 zł |
| Ostateczna cena usługi | 984 zł |
| Kwota zwrotu i zmniejszenia zaliczki | 246 zł |

W tym przykładzie wystawiasz fakturę korygującą do faktury zaliczkowej na 246 zł brutto i zwracasz klientowi 246 zł. Nie wystawiasz osobnej faktury sprzedaży na kwotę ujemną.

![Przykład: zaliczka 1 230 zł, ostateczna cena 984 zł, korekta faktury zaliczkowej i zwrot klientowi 246 zł.](/images/guides/za-wysoka-zaliczka-przyklad-korekty.webp)
*Różnicę zwracasz, a fakturę zaliczkową zmniejszasz korektą.*

## Co sprawdzić przed korektą

1. Odszukaj fakturę zaliczkową i jej numer KSeF.
2. Potwierdź z klientem ostateczną cenę oraz kwotę zwrotu.
3. Sprawdź stawkę VAT i kwoty z faktury zaliczkowej.
4. Wystaw korektę zmniejszającą wartość zaliczki.
5. Wyślij korektę do KSeF i zapisz nadany numer.
6. Zwróć różnicę przelewem z numerem korygowanej faktury w tytule.

## Który dokument wystawić

| Sytuacja | Dokument |
|---|---|
| Zaliczka nie pokrywa całej ceny | Faktura końcowa pomniejszona o wcześniejsze zaliczki |
| Zaliczka jest równa cenie | Co do zasady nie ma kwoty pozostałej do rozliczenia |
| Zafakturowana zaliczka przewyższa cenę i zwracasz różnicę | Faktura korygująca do faktury zaliczkowej |
| Nadwyżka ma zostać na poczet innej dostawy lub usługi | Najpierw uzgodnij rozliczenie z klientem i biurem księgowym; nie opisuj jej automatycznie jako zwrotu |

## Jak oznaczyć korektę faktury zaliczkowej w KSeF?

Korekta zaliczki ma własny rodzaj faktury. Podręcznik KSeF 2.0: „KOR_ZAL” to „oznaczenie wskazywane, jeśli wystawiana jest faktura korygująca do faktury zaliczkowej”.

O kwocie podręcznik pisze: „W polu P_15 należy wówczas wskazać kwotę różnicy wartości zaliczki w stosunku do faktury pierwotnej”. Pole P_15ZK przy korekcie zaliczki „zawiera kwotę zapłaty przed korektą”.

| Pole | W przykładzie, stawka 23% |
|---|---:|
| RodzajFaktury | KOR_ZAL |
| P_15ZK | 1 230 zł |
| P_13_1 | -200 zł |
| P_14_1 | -46 zł |
| P_15 | -246 zł |

## Co wpisać w części Zamowienie?

Faktura zaliczkowa ma pozycje w części Zamowienie, a nie FaWiersz. Gdy samo zamówienie się nie zmienia, MF radzi pokazać je dwa razy: „zaleca się wprowadzenie zapisu wg stanu przed korektą i zapisu w stanie po korekcie”. Powód podaje wprost: „w celu potwierdzenia braku zmiany wartości danej pozycji faktury”.

Gdy zmienia się cena z umowy, zmienia się też pole WartoscZamowienia. Podręcznik: „pole to powinno zawierać prawidłową wartość zamówienia w stanie po korekcie”.

Gotowe pliki są w dokumencie MF „Przykładowe pliki dla struktury logicznej e-Faktury FA(3)”, przykład nr 12 i nr 18.

## Zaliczka w Firmowidzie

[Firmowid](/ksef), nasz program, wystawia fakturę VAT i fakturę zaliczkową. Korektę wystawia tylko do faktury VAT.

Czego nie ma. Korekty faktury zaliczkowej, czyli KOR_ZAL, Firmowid nie wystawia. Faktury końcowej też nie. Taką korektę trzeba wystawić w innym narzędziu.

## Dalsze czytanie

- [Jak wystawić pierwszą fakturę w KSeF](https://firmowid.pl/poradnik/pierwsza-faktura-ksef)
- [Co to jest KSeF i e-faktura](https://firmowid.pl/poradnik/co-to-jest-ksef-i-e-faktura)
- [Jak bezpiecznie przetestować KSeF](https://firmowid.pl/poradnik/jak-bezpiecznie-przetestowac-ksef)
- [Cennik Firmowida](https://firmowid.pl/cennik)

## Źródła

- [Ministerstwo Finansów: Podręcznik KSeF 2.0, część II, Wystawianie i otrzymywanie faktur w KSeF, rozdziały 2.13.1 i 2.13.5](https://ksef.podatki.gov.pl/media/rronoxyt/podrecznik-ksef-20-cz-ii-wystawianie-i-otrzymywanie-faktur-w-ksef-06082026.pdf), publikacja 6.08.2026, dostęp 24.11.2026.
- [Ministerstwo Finansów: Faktura ustrukturyzowana i struktura logiczna FA(3)](https://ksef.podatki.gov.pl/informacje-ogolne-ksef-20/faktura-ustrukturyzowana-i-struktura-logiczna-fa/), dostęp 6.11.2026.
- Ustawa z 11 marca 2004 r. o podatku od towarów i usług, art. 106f i 106j, stan sprawdzony 6.11.2026.
- Firmowid, fakty produktowe zweryfikowane 22.10.2026 i 24.11.2026.
