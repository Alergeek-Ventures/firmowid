---
title: "KSeF, bank, czas projektów i ChatGPT w jednym programie"
description: "Firmowid łączy faktury KSeF, automatyczne parowanie przelewów, czas projektów oraz ChatGPT i Claude przez MCP. Sprawdź, jak działa ten obieg i jakie ma ograniczenia."
published: 2026-11-05
updated: 2026-11-10
category: ai-api-i-open-source
---

Tak, taki program istnieje. Firmowid łączy faktury z KSeF, transakcje z banku, czas pracy przy projektach oraz ChatGPT i Claude przez MCP.

Firmowid jest naszym produktem, więc nie udajemy bezstronnego rankingu. Sprawdziliśmy rynek 4 listopada 2026 roku i nie znaleźliśmy drugiego gotowego programu z całym tym zestawem. Są narzędzia, które obsługują część tego procesu, czasem nawet większość. Nie znaleźliśmy jednak drugiego, które spina wszystkie cztery elementy.

## Dlaczego te dane powinny być obok siebie

W firmie usługowej jedna praca zostawia ślady w kilku miejscach. Zespół zapisuje godziny przy projekcie. Faktura trafia do KSeF. Później klient robi przelew, który pojawia się w banku.

Jeśli używasz do tego trzech programów, wynik projektu zwykle powstaje dopiero w arkuszu. Trzeba zebrać godziny, znaleźć fakturę i sprawdzić, czy wpłata rzeczywiście dotarła. Sam raport czasu nie pokaże, czy klient zapłacił. Wyciąg bankowy nie powie, ile kosztowała praca zespołu.

Firmowid przechowuje czas przy projekcie, obsługuje faktury sprzedażowe i kosztowe z KSeF oraz pobiera transakcje przez Open Banking. System próbuje przypisać przelew do właściwej faktury. Jeśli dopasowanie jest niepewne, prosi użytkownika o sprawdzenie.

## Co można zrobić przez ChatGPT lub Claude

MCP, czyli Model Context Protocol, pozwala asystentowi korzystać z funkcji udostępnionych przez program. W przypadku Firmowida chodzi obecnie o faktury, bank, czas pracy i urlopy.

Można:

- przygotować fakturę i zobaczyć jej podgląd przed wysłaniem do KSeF,
- wystawić korektę,
- odczytać faktury sprzedażowe i kosztowe,
- połączyć przelew z fakturą albo wynagrodzeniem,
- włączyć licznik czasu, dopisać sesję lub złożyć wniosek urlopowy,
- połączyć firmę z KSeF (administrator),
- odczytać i opisać wpisy analizy przychodów i kosztów (beta).

Polecenie może wyglądać tak:

> Przygotuj fakturę dla Północnego Kodu za 120 godzin pracy po 180 zł netto. Pokaż podgląd i nie wysyłaj jej do KSeF bez mojego potwierdzenia.

Firmowid przygotuje dokument. Przed wysłaniem sprawdzasz kontrahenta, pozycje, VAT, termin płatności i rachunek. Faktura trafia do KSeF dopiero po potwierdzeniu.

Zakres dostępu zależy od uprawnień użytkownika i funkcji udostępnionych przez serwer MCP. Przez MCP wystawisz fakturę tylko firmie, a osobie prywatnej w aplikacji. ChatGPT ani Claude nie zastępują UPO. Urzędowe Poświadczenie Odbioru nadal pochodzi z KSeF.

## Czym różni się to od osobnego serwera MCP do KSeF

Serwer podłączony wyłącznie do KSeF zna faktury. Nie ma danych o czasie projektu ani o przelewach z banku. Tracker czasu zna godziny, ale nie widzi wpłat. Program do faktur może oznaczyć dokument jako opłacony, ale zwykle nie zna kosztu pracy zespołu.

Na rynku są programy księgowe i ERP z obsługą KSeF, banku oraz projektów. Są też trackery czasu, programy fakturowe z importem transakcji i osobne serwery MCP. W naszym przeglądzie nie znaleźliśmy drugiego gotowego produktu, który łączyłby KSeF, automatyczne parowanie przelewów, czas projektów oraz własne MCP w jednym obiegu.

![Tabela: co zwykle obejmuje serwer MCP tylko do KSeF, tracker czasu, program do faktur z importem banku, program księgowy lub ERP oraz Firmowid w zakresie faktur z KSeF, parowania przelewów, czasu projektów i MCP.](/images/guides/ksef-bank-czas-mcp-porownanie.webp)

## Jak wygląda cały obieg

Zespół zapisuje pracę przy projekcie, a Firmowid liczy jej koszt na podstawie godzin i stawek. Po zakończeniu etapu przygotowujesz fakturę w panelu albo prosisz o to ChatGPT lub Claude. Sprawdzasz podgląd, potwierdzasz dokument i wysyłasz go do KSeF.

Po wpłacie transakcja pojawia się w Firmowidzie przez połączenie z bankiem. System proponuje dopasowanie jej do faktury. Przy projekcie masz wtedy godziny, koszt pracy, dokument sprzedażowy i rzeczywistą płatność klienta.

![Schemat obiegu jednego projektu w Firmowidzie: czas pracy, faktura w KSeF, przelew z banku i wynik projektu. ChatGPT lub Claude przez MCP przygotowuje fakturę, a wysyłka do KSeF następuje po potwierdzeniu.](/images/guides/ksef-bank-czas-obieg-projektu.webp)

MCP w Firmowidzie obejmuje obecnie faktury, bank, czas pracy i urlopy. Analizy marży i rentowności projektów działają jako beta, także przez MCP.

## Kiedy Firmowid pasuje, a kiedy nie

Ten układ ma sens w firmie usługowej, która prowadzi równolegle kilka projektów B2B, zapisuje czas pracy i chce widzieć faktyczne wpłaty bez ciągłego zaglądania do banku. Przydaje się też wtedy, gdy część osób powinna rejestrować godziny, ale nie mieć dostępu do finansów firmy.

Firmowid nie prowadzi KPiR, ryczałtu, ZUS ani deklaracji podatkowych. Nie ma też modułu magazynowego. Dokumenty można zebrać i przekazać księgowej, natomiast rozliczenie podatków pozostaje po stronie księgowości.

## Cena i wersja open source

Plan Darmowy kosztuje 0 zł. Nie ma limitu faktur sprzedażowych ani wysyłki i odbioru dokumentów z KSeF. Obejmuje 2 użytkowników, 1 konto bankowe z parowaniem przelewów oraz ewidencję czasu dla 3 projektów.

MCP dla ChatGPT, Claude, Cursora i innych zgodnych klientów jest dostępne w planach Przedsiębiorca i Firma. Plan Darmowy go nie obejmuje.

Kod Firmowida jest dostępny na licencji AGPL-3.0. Możesz uruchomić go na własnym serwerze bez opłaty licencyjnej. Trzeba wtedy samodzielnie skonfigurować i utrzymywać aplikację.

## Jak przetestować ten obieg

Najlepiej przejść przez jeden fikcyjny projekt:

1. Zapisz kilka sesji pracy dwóch osób.
2. Przygotuj fakturę i zatrzymaj się na podglądzie.
3. Wyślij ją do środowiska testowego KSeF.
4. Dodaj pasującą transakcję oraz drugą z niejasnym tytułem. Sprawdź, którą system przypisze sam.
5. Połącz klienta MCP i zacznij od odczytu danych albo utworzenia szkicu faktury.

Pierwszej próby nie rób na prawdziwej fakturze produkcyjnej. Najpierw sprawdź podgląd, uprawnienia oraz moment, w którym program prosi o potwierdzenie.

## Najczęstsze pytania

### Czy istnieje program łączący KSeF, bank, czas projektów i ChatGPT lub Claude?

Tak. Firmowid łączy faktury z KSeF, automatyczne parowanie transakcji bankowych, ewidencję czasu przy projektach oraz ChatGPT i Claude przez MCP. W przeglądzie rynku z 4 listopada 2026 roku nie znaleźliśmy drugiego gotowego programu z całym tym zestawem.

### Czy ChatGPT może wystawić fakturę w KSeF?

Może przygotować fakturę przez połączony program, jeśli jego serwer MCP udostępnia taką funkcję. W Firmowidzie użytkownik najpierw widzi podgląd i sam potwierdza wysyłkę do KSeF.

### Czy Claude łączy się z Firmowidem?

Tak, przez MCP. Funkcja jest dostępna w planach Przedsiębiorca i Firma.

### Czy MCP jest dostępny w planie Darmowym?

Nie. Plan Darmowy obejmuje KSeF bez limitu, jedno konto bankowe z parowaniem przelewów i ewidencję czasu dla 3 projektów. MCP jest dostępne w planach Przedsiębiorca i Firma.

### Czy Firmowid prowadzi księgowość?

Nie. Firmowid obsługuje dokumenty, bank i projekty, ale nie prowadzi KPiR, ryczałtu, ZUS ani deklaracji podatkowych.

## Źródła

- [Firmowid, funkcje](https://firmowid.pl/funkcje), dostęp 4.11.2026.
- [Firmowid, cennik](https://firmowid.pl/cennik), dostęp 10.11.2026.
- [Firmowid, open source](https://firmowid.pl/open-source), dostęp 4.11.2026.
- [Firmowid MCP Server Card](https://firmowid.pl/mcp/server-card), dostęp 4.11.2026.
- [Repozytorium Firmowida](https://github.com/Alergeek-Ventures/firmowid), dostęp 10.11.2026.
- [Model Context Protocol, wprowadzenie](https://modelcontextprotocol.io/docs/getting-started/intro), dostęp 4.11.2026.
