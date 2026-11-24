---
title: "Rentowność projektu: jak ją liczyć w firmie usługowej"
description: "Rentowność projektu to wynik podzielony przez przychód. Jak przypisać koszty i godziny do projektu i co te liczby dały nam w rozmowie z klientem o cenie."
published: 2026-11-12
updated: 2026-11-24
category: firma-uslugowa
---

Wcześniej nie do końca wiedzieliśmy, czy projekt się opłaca, mogliśmy szacować czas i niektóre koszty, jak wyjazdy. Teraz każdy koszt możemy oznaczyć i przypisać do konkretnego projektu. To bardzo wygodne, może to za nas zrobić Claude przez MCP, ChatGPT albo asystent. Bazuje na analogii, na wcześniejszych opisach faktur z poprzednich miesięcy.

Do tego mamy pełny dashboard za zeszły rok: rentowność każdego projektu, czyli koszty kontra faktury, oraz to, co już jest opłacone, a co nie. Możemy poprosić czat o wykres, na którym nam zależy, na przykład symulację, jak nowy etat wpłynie na kolejne miesiące. Pytamy też o prognozy na podstawie trendów i o to, gdzie warto obciąć wydatki.

Małe firmy żyją z miesiąca na miesiąc. Takie dane pozwalają mądrzej planować budżet, strategicznie zrozumieć, gdzie jest problem, i rozwiązać go w ciągu kolejnych miesięcy.

## Jak liczyliśmy rentowność projektu wcześniej?

Zazwyczaj braliśmy wyciągi i patrzyliśmy na to w Excelu. Kosztowało nas to sporo czasu i nie robiliśmy tego regularnie. W czasach jeszcze przed AI naprawdę trudno było wszystko sobie policzyć, bo trzeba było zaznaczyć, co jest powtarzalne, a co jednorazowe, i zobaczyć, jak to będzie w przyszłych miesiącach.

Teraz w teorii można korzystać z czatów, ale one też nie są doskonałe, bo i tak trzeba im wprowadzić cały kontekst finansowy firmy, co jest dosyć skomplikowane.

## Co nas zaskoczyło w pierwszych liczbach?

Zaskoczyło nas, jak wiele rzeczy jest powtarzalnych i jak wielki ma to wpływ na rentowność firmy. Zaskoczyło nas też, jak duża część kosztów jest powiązana z projektami, czego wcześniej nie do końca widzieliśmy.

## Jak rentowność projektu pomogła podnieść cenę?

Na podstawie rentowności projektów byliśmy w stanie przedstawić klientowi solidne argumenty za tym, żeby podwyższyć mu cenę za projekt. Pokazaliśmy po prostu, dlaczego kosztuje nas to więcej, i dzięki temu zwiększyliśmy trochę rentowność na tym projekcie.

## Jak obliczyć rentowność projektu?

| Miara | Wzór |
|---|---|
| Wynik projektu | przychód minus koszty |
| Rentowność projektu | wynik podzielony przez przychód, w procentach |
| Koszt godziny | koszty podzielone przez liczbę godzin |

## Co wlicza się do kosztów projektu?

| Koszt | Przykłady |
|---|---|
| Bezpośredni | podwykonawcy, licencje, wyjazdy |
| Wynagrodzenia | godziny osób pracujących nad projektem |
| Pośredni | biuro, programy, podatki |

## Jak liczymy rentowność projektu

| Pozycja | Skąd się bierze |
|---|---|
| Przychód projektu | opłacone faktury sprzedaży przypisane do projektu |
| Koszty bezpośrednie | faktury kosztowe i wydatki oznaczone projektem, także dzielone między kilka projektów |
| Wynagrodzenia | dzielone między projekty według godzin danej osoby w miesiącu |
| Koszty firmy i podatki | rozkładane na projekty według [przepracowanych godzin](/funkcje/czas-pracy) |
| Projekty wewnętrzne | bez udziału w kosztach firmy, widoczne osobno |
| Nieopłacone faktury | pokazane osobno, poza wynikiem |

W Firmowidzie te liczby zbiera [Analiza przychodów i kosztów](/funkcje/analiza), w której widok Trendy można zawęzić do jednego projektu.

W iFirmie projekt też zbiera przychody i koszty, ale wynagrodzenia pracowników dodaje się do niego ręcznie.

![Rentowność projektu w Firmowidzie: przychód to opłacone faktury przypisane do projektu, koszty bezpośrednie to faktury oznaczone projektem, wynagrodzenia oraz koszty firmy i podatki dzieli się według godzin, projekty wewnętrzne są osobno, a nieopłacone faktury poza wynikiem.](/images/guides/rentownosc-projektu-jak-liczymy.webp)

## Źródła

- Firmowid: kod źródłowy (AGPL-3.0), moduł analizy i rentowności projektów, stan 11.11.2026.
- [iFirma: projekty w ifirma.pl](https://www.ifirma.pl/blog/projekty-w-ifi-do-czego-sluza/), dostęp 11.11.2026.
- Skąd biorą się godziny w projektach: [faktura za godziny pracy](/poradnik/fakturowanie-za-godziny-czas-pracy).
