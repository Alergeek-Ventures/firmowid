---
title: "Program do analizy przychodów i kosztów małej firmy"
description: "Analiza w Firmowidzie pokazuje, ile zostaje z każdych 100 zł przychodu, dzieli koszty na kategorie po PKD i łączy się z Claude. Jak z niej korzystamy."
published: 2026-11-18
updated: 2026-11-18
---

Analiza daje nam szybki przegląd sytuacji. Zerkamy i od razu wiemy, co mówią ostatnie miesiące. Poza tym daje nam przede wszystkim możliwość korzystania z Claude i robienia analiz bardziej dostosowanych do bieżącego problemu. Firmowid opisuje dane i synchronizuje je z kilku źródeł, więc Claude ma wszystko jak na tacy i może przygotować taką analizę, jaką chcemy.

![Analiza, widok „Podsumowanie”: ile zostaje z każdych 100 zł przychodu](/images/guides/funkcje/analiza-podsumowanie.webp)

## Kiedy tu zaglądamy

Najczęściej pod koniec miesiąca, kiedy patrzymy, jak to wygląda w porównaniu do poprzedniego. Często też wtedy, gdy klienci zapłacili za faktury.

## Ile zostaje ze 100 zł

Ten ekran jest dosyć mocny. Faktycznie można zobaczyć na własne oczy, ile koniec końców zostaje z każdych 100 zł przychodu. Spodziewałem się, że ta kwota będzie trochę wyższa. U nas wydatki dzielą się w miarę równo na parę kategorii. To jest jednak tylko wstęp. Potem patrzymy po kategoriach i rozmawiamy z ChatGPT, z Claude albo z asystentem w aplikacji, kto co woli.

## Kategorie kosztów

Koszty dzielimy na kategorie, takie jak wynagrodzenia czy lokal, ale większość zaznacza nam już AI. Podpowiada kategorię po kodzie PKD kontrahenta, więc w Polsce działa to świetnie, bez ręcznego opisywania każdej transakcji. Do projektów można przypisać samemu, a w dużym stopniu robi to też AI. Z każdym miesiącem się uczy, więc po paru miesiącach trzeba naprawdę niewiele. Ma się wtedy w Firmowidzie prawie że dyrektora finansowego albo szefa analityki finansowej, bo od razu potrafi wyciągnąć bardzo dużo rzeczy i zrobić pytania i analizy indywidualnie pod firmę.

## Projekty i trendy

Na projekty patrzymy osobno, bo bardzo ważne jest, żeby wiedzieć, który projekt jest rentowny, a który nie, i gdzie trzeba coś poprawić. Trendy są istotne zwłaszcza pod koniec roku, kiedy widać, jak rok przebiegał, ale na bieżąco liczą się dla nas każde 3 miesiące. Mamy widok na cały rok.

![Analiza, „Trendy”: wynik miesiąc po miesiącu](/images/guides/funkcje/analiza-trendy.webp)

## Pytania, które zadajemy Claude

- Jaki powtarzalny koszt z ostatnich 3 miesięcy dałoby się zniwelować?
- Jakie są prognozy na kolejne miesiące?
- Co się stanie z wynikiem na koniec roku, jeśli zmienimy jeden czynnik?

Jak podłączyć Claude: [Firmowid w Claude i ChatGPT](/funkcje/claude-chatgpt-mcp).

## Jak liczy Analiza

| | |
|---|---|
| Przychody | faktury sprzedażowe opłacone przelewem |
| Koszty | faktury kosztowe i przelewy bez faktury, opłacone |
| Kwoty | brutto, w złotych po kursie z dnia |
| Miesiące | tylko domknięte |
| Przelewy między własnymi kontami | pomijane |
| Kategorie | 12 kosztów, podpowiada AI, zatwierdzasz Ty |
| Widoki | Podsumowanie, Trendy, filtr projektu |
| Eksport | nie |

Szczegóły: [Analiza: jak czytać Podsumowanie i Trendy](/pomoc/analiza-podsumowanie-i-trendy) · [Rentowność projektu w małej firmie](/poradnik/rentownosc-projektu-firma-uslugowa) · [cennik](/cennik)
