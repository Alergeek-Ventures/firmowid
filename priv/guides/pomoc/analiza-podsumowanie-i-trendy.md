---
title: "Analiza: jak czytać Podsumowanie i Trendy"
description: "Co znaczą liczby w Analizie Firmowida: przychody, koszty, wynik, miesiąc domknięty, pasek 100 zł i nieopłacone faktury poza sumą."
published: 2026-11-18
updated: 2026-11-18
category: analiza
---

„Podsumowanie” odpowiada na pytanie, na co poszły pieniądze w wybranym okresie i ile z nich zostało. „Trendy” pokazują wynik każdego miesiąca osobno. Oba widoki liczą tylko opłacone faktury i tylko miesiące domknięte.

## Co trzeba mieć

- Rolę fakturowanie, księgowość albo admin. Pracownik nie ma dostępu do Analizy.
- Połączony KSeF i bank oraz przelewy dopasowane do faktur. Faktura bez płatności nie wejdzie do wyniku.
- Co najmniej jeden miesiąc domknięty, czyli taki, który się skończył i ma najwyżej dwie faktury czekające na zapłatę.

## Krok po kroku

1. Otwórz „Analizę” z menu. Domyślny okres to bieżący rok.
2. W polu „Okres” wybierz zakres miesięcy. Najdłuższy zakres to 36 miesięcy. Przycisk „Ten rok” wraca do bieżącego roku.
3. Przeczytaj zdanie na górze „Podsumowania”: „Z każdych 100 zł przychodu zostało…”. Przy stracie brzmi ono „Na każde 100 zł przychodu wydano…”.
4. Spójrz na pasek pod zdaniem. Kolorowe odcinki to największe kategorie kosztów, a zielony to część, która zostaje w firmie.
5. W kolumnach „Koszty” i „Przychody” kliknij nazwę kategorii, żeby zobaczyć kontrahentów, którzy się na nią składają.
6. Przejdź na zakładkę „Trendy”. Każdy słupek to wynik jednego miesiąca: zysk rośnie w górę, strata w dół.
7. Kliknij słupek albo nazwę miesiąca w tabeli „Miesiąc po miesiącu”. Otworzy się „Podsumowanie” tego jednego miesiąca.

![Analiza, „Podsumowanie” z paskiem kosztów i tym, co zostaje w firmie](/images/guides/pomoc/analiza-podsumowanie.webp)

## Co znaczą liczby

| Liczba | Co zawiera | Czego nie zawiera |
|---|---|---|
| Przychody | opłacone faktury sprzedażowe (brutto, po korektach), zwroty na fakturach kosztowych, wpływy bez faktury oznaczone jako pominięte | faktur nieopłaconych |
| Koszty | opłacone faktury kosztowe, wydatki bez faktury oznaczone jako pominięte, przelewy wynagrodzeń | przelewów między własnymi rachunkami, wpisów z kategorią „Pominięte” |
| Wynik | przychody minus koszty | podatków do zapłaty |
| „X ze 100” | ile złotych z każdych 100 zł przychodu poszło na daną kategorię | |
| „Poza sumą: nieopłacone faktury” | faktury przyjęte w KSeF, które czekają na zapłatę | nie wpływają na wynik |

Przykład ze zrzutu wyżej: z każdych 100 zł przychodu zostało 7 zł, a 93 zł to koszty. Na zrzucie wszystkie stoją jeszcze w kategorii „Do przypisania”; po przypisaniu kategorii zobaczysz, ile z tych 93 zł poszło na wynagrodzenia, lokal czy oprogramowanie.

Faktura trafia do miesiąca według daty sprzedaży, a nie daty wystawienia. Przelew bez faktury liczy się w miesiącu księgowania. Wynagrodzenie liczy się w miesiącu, za który zostało wypłacone, nawet jeśli przelew wyszedł później.

Kwoty w walutach obcych są przeliczane na złote po kursie z dnia wpisu.

## Porównania w „Podsumowaniu”

Pod głównym paskiem pojawiają się paski porównawcze:

- „Poprzedni mies.”, gdy oglądasz jeden miesiąc.
- „Rok wcześniej”, gdy oglądasz kilka miesięcy. Znika, jeśli rok wcześniej nie było przychodu.
- „Ostatnie 3 mies.”, gdy okres ma co najmniej cztery domknięte miesiące.

Przy jednym miesiącu każda kategoria ma też dopisek „zwykle…” ze średnią z pozostałych miesięcy okresu. Procent odchylenia pojawia się dopiero przy zmianie o co najmniej 10%.

## Jak czytać „Trendy”

Wykres nosi tytuł „Wynik netto według miesięcy”. Po najechaniu na słupek zobaczysz przychody, wydatki i osobno nieopłacone przychody oraz wydatki tego miesiąca.

Tabela „Miesiąc po miesiącu” ma kolumny „Przychody”, „Koszty”, „Wynik” i „Z każdych 100 zł przychodu”. Wiersz „Razem” sumuje tylko miesiące domknięte.

![Analiza, „Trendy”: wynik miesiąc po miesiącu](/images/guides/pomoc/analiza-trendy.webp)

### Jeden projekt

Przełącznik „Pokaż:” w „Trendach” zawęża liczby do jednego projektu. Widzisz wtedy przychody i koszty przypisane do projektu oraz wynagrodzenia podzielone według godzin z czasu pracy. W tym trybie nieopłacone faktury nie są pokazywane, a miesiąca nie da się kliknąć.

## Gdy ekran jest pusty

- „Żaden miesiąc tego okresu nie jest jeszcze domknięty.” Wybierz wcześniejszy okres albo dopasuj zaległe przelewy do faktur.
- Miesiąc podpisany „Niedomknięty”. Wynik pojawi się, gdy miesiąc się skończy i najwyżej dwie jego faktury będą czekać na zapłatę.
- „Brak przychodów i wydatków w tym okresie.” W wybranych miesiącach nie ma opłaconych faktur ani przelewów.
- Kategoria „Do przypisania” albo „Bez kategorii”. Wpisy czekają na kategorię. Osoba z rolą księgowość lub admin może ją wybrać po kliknięciu kontrahenta.

## Czego Analiza nie robi

Nie liczy podatków i nie odejmuje VAT. Nie ma eksportu do pliku. Kosztów wspólnych firmy nie rozkłada na projekty.

## Powiązane

- [Analiza: ile zostaje w firmie](/funkcje/analiza)
- [Rentowność projektu w małej firmie](/poradnik/rentownosc-projektu-firma-uslugowa)
