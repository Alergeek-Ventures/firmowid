---
title: "Asystent AI w Firmowidzie: w aplikacji, w Claude, w ChatGPT i przez API"
description: "Asystent AI w Firmowidzie przygotowuje faktury i szuka do nich przelewów. Te same dane masz w Claude przez MCP, w ChatGPT jako plugin i w API dla sklepu. Każdą fakturę od AI zatwierdzasz sam."
published: 2026-11-18
updated: 2026-11-27
landing:
  kicker: "Funkcje · AI"
  note: "zmiany zatwierdzasz Ty"
  author: franek
  facts:
    - label: "Asystent AI w aplikacji"
      value: "od planu Przedsiębiorca"
    - label: "Claude i ChatGPT"
      value: "w każdym planie, w ChatGPT jako plugin"
    - label: "Faktura do KSeF"
      value: "dopiero po Twoim potwierdzeniu"
---

Najczęściej proszę Firmowida, żeby mi przygotował fakturę. Druga rzecz to lista kandydatów, czyli przelewów do faktury, żeby mi znalazł jak najwięcej. To dwie najczęstsze rzeczy. Teraz coraz częściej pytam też, jaka to kategoria, kiedy nie mam pewności.

Dla mnie asystent różni się od Claude i ChatGPT tylko tym, że lepiej sugeruje mi konkretne pytania. Nie muszę ich pisać od zera, po prostu klikam przygotowany prompt. W Claude i w ChatGPT trzeba to robić trochę samodzielnie.

Claude podłączonego do Firmowida używamy głównie do analiz, bo dane są już opisane i zebrane z kilku źródeł. Robi też rzecz, której się nie spodziewaliśmy: opisuje faktury dla naszego biura księgowego. Dopisuje do faktury 2–3 zdania, które pomagają zrozumieć, co to za faktura.

Nie zdarza mi się odrzucać jego propozycji. Zazwyczaj tylko dokładnie sprawdzam fakturę, zanim ją wyślę.

![Strona asystenta z gotowymi pytaniami o faktury, przelewy, koszty i projekty](/images/guides/funkcje/asystent.webp)

## Jak to działa

Firmowid daje AI dostęp do faktur, przelewów, czasu pracy i Analizy Twojej firmy. Możesz z niego korzystać w dwóch miejscach: w aplikacji albo w Claude i ChatGPT.

| Krok | Gdzie | Co |
|---|---|---|
| Zapytaj | panel w aplikacji albo czat w Claude i ChatGPT | gotowe pytanie jednym kliknięciem albo własne polecenie |
| Sprawdź propozycję | karta „Proponowane zmiany” albo okno podglądu | szkic faktury, przelew do faktury, kategoria kosztu |
| Zatwierdź | przycisk w aplikacji | faktura trafia do KSeF dopiero po Twoim kliknięciu |

## Asystent AI w aplikacji

Asystent AI jest w panelu dostępnym z każdego widoku i na osobnej stronie „Asystent”. Zaczyna od gotowych pytań: o faktury po terminie, przelewy bez faktury, koszty stałe i projekty.

**Faktury.** Przygotowuje szkic faktury na podstawie wcześniejszych, na przykład refakturę powtarzaną co miesiąc.

**Przelewy.** Szuka przelewów pasujących do faktury, także wtedy, gdy zapłata przyszła dużo wcześniej albo później, a nazwa kontrahenta na przelewie różni się od tej z faktury. Jeden przelew połączy z kilkoma fakturami.

**Kategorie.** Podpowiada kategorię kosztu, gdy nie masz pewności.

Rozmowę widzi tylko jej autor. Dostęp mają role, które widzą finanse firmy, czyli fakturowanie, księgowość i admin.

## Firmowid w Claude i ChatGPT

W ChatGPT Firmowid jest oficjalnym pluginem. Znajdujesz go w katalogu pluginów, klikasz „Install plugin”, logujesz się kontem Firmowida i na ekranie zgody wybierasz firmę.

W Claude, Cursorze i innych programach obsługujących MCP dodajesz konektor z adresem serwera `https://firmowid.pl/mcp`. Logowanie i wybór firmy wyglądają tak samo.

AI dostaje 48 narzędzi: faktury, kontrahentów, przelewy, czas pracy, urlopy i Analizę. Widzi tyle, na ile pozwala Twoja rola w firmie, więc pracownik zobaczy swój czas, urlopy i projekty, a faktur firmy nie.

W ChatGPT faktura otwiera się w oknie aplikacji Firmowida wewnątrz czatu. Sprawdzasz ją na podglądzie i dopiero wtedy wysyłasz do KSeF.

![Okno „Potwierdź fakturę” w ChatGPT z podglądem faktury i przyciskiem „Potwierdź i wyślij do KSeF”](/images/guides/funkcje/mcp-potwierdz-fakture.webp)

Pełna lista narzędzi: [Narzędzia MCP Firmowida](/pomoc/narzedzia-mcp).

## API dla sklepu i własnych programów

Te same narzędzia są w publicznym API, więc z Firmowida skorzysta też program, przy którym nikt nie siedzi. Najczęściej to sklep internetowy, który po opłaceniu zamówienia sam wystawia fakturę i wysyła ją do KSeF. Działa to także dla osoby prywatnej, a ponowione zamówienie nie da drugiej faktury.

Klucz tworzysz w ustawieniach, w zakładce „Klucze API”. Osobisty działa z Twoją rolą w firmie. Firmowy dostaje rolę od admina i działa dalej, gdy jego autor odejdzie z firmy. Opis każdego wywołania jest w [dokumentacji API](/api/v1/docs).

## Zatwierdzanie zmian

| Co robi AI | Kiedy zmiana wchodzi w życie |
|---|---|
| Faktura i korekta do KSeF | po Twoim kliknięciu w oknie podglądu |
| Zmiany proponowane przez asystenta AI w aplikacji | po zatwierdzeniu karty „Proponowane zmiany” |
| Godziny pracy, notatki i łączenie przelewów przez Claude i ChatGPT | od razu po poleceniu |
| Faktura wystawiana przez API | od razu, bez okna podglądu |

Faktury przez Claude i ChatGPT wystawisz tylko dla firm. Fakturę dla osoby prywatnej wystawiasz w aplikacji albo przez API.

## Ile to kosztuje

| Plan | Asystent AI w aplikacji | Claude i ChatGPT | API | Cena |
|---|---|---|---|---|
| Darmowy | nie | tak | tak | 0 zł |
| Przedsiębiorca | tak | tak | tak | 29 zł netto miesięcznie |
| Firma | tak | tak | tak | 149 zł netto miesięcznie |

Pierwsze 60 dni płatnego planu jest bez opłat. Konto w Claude albo ChatGPT opłacasz osobno u ich dostawców.

## Porównanie z innymi programami

W programach do faktur, które sprawdziliśmy, AI działa zwykle albo tylko poza aplikacją, albo tylko do odczytu. Firmowid ma oba kanały i w obu może przygotować fakturę.

| Program | Czat w aplikacji | Szkic faktury przez AI | Wysyłka do KSeF przez AI | Pomoc w dopasowaniu przelewów | Zatwierdzanie zmian |
|---|---|---|---|---|---|
| Firmowid | tak | tak | po zatwierdzeniu | tak | karta „Proponowane zmiany” |
| inFakt | nie, wtyczka do ChatGPT i Claude | tak, przez MCP | tak, przez MCP | nie | w rozmowie |
| Fakturownia | nie, MCP tylko do odczytu | nie | nie | nie | nie dotyczy |
| wFirma | nie | nie | nie | częściowo, przy imporcie wyciągu | AI tylko podpowiada |
| KSeFGPT | tak, tylko pytania o KSeF | nie | nie | nie | brak |

Stan na 18.11.2026, według stron producentów: [inFakt](https://www.infakt.pl/blog/?p=80793), [Fakturownia](https://fakturownia.pl/mcp), [wFirma](https://pomoc.wfirma.pl/-ai-w-systemie-wfirma-pl-poznaj-moc-sztucznej-inteligencji), [KSeFGPT](https://ksefgpt.pl).

## Najważniejsze dane

| | |
|---|---|
| Asystent AI w aplikacji | panel w każdym widoku i strona „Asystent” |
| Gotowe pytania | faktury po terminie, przelewy bez faktury, koszty stałe, projekty |
| Rozmowy | widzi tylko autor |
| Kto ma dostęp do asystenta AI | role od fakturowania wzwyż, pracownik nie |
| Firmowid w ChatGPT | oficjalny plugin w katalogu ChatGPT |
| Adres serwera MCP | `https://firmowid.pl/mcp` |
| Logowanie | konto Firmowida, ekran zgody z wyborem firmy |
| Narzędzia MCP | 48: faktury, kontrahenci, przelewy, czas pracy, urlopy, Analiza |
| API | te same narzędzia, klucz osobisty albo firmowy, [dokumentacja](/api/v1/docs) |
| Uprawnienia przez MCP | jak Twoja rola w firmie |
| Faktury przez Claude i ChatGPT | tylko dla firm |

Zobacz też: [Analiza: ile zostaje w firmie](/funkcje/analiza) · [cennik](/cennik)

## Najczęstsze pytania

### Czy AI może wystawić fakturę bez mojej zgody?
Nie. AI przygotowuje fakturę, a do KSeF wysyłasz ją sam, przyciskiem w oknie podglądu. Co jeszcze wymaga potwierdzenia, pokazuje sekcja [Zatwierdzanie zmian](#zatwierdzanie-zmian).

### Czym asystent AI w aplikacji różni się od Claude i ChatGPT?
Asystent AI w aplikacji ma gotowe pytania i nie wymaga niczego poza kontem Firmowida. W Claude i ChatGPT pracujesz na tych samych danych we własnym czacie, po zainstalowaniu pluginu albo dodaniu konektora.

### Ile kosztuje AI w Firmowidzie?
Asystent AI w aplikacji jest od planu Przedsiębiorca. Połączenie z Claude i ChatGPT oraz API działają w każdym planie, także darmowym. Szczegóły są w sekcji [Ile to kosztuje](#ile-to-kosztuje).

### Czy pracownik zobaczy przez AI faktury firmy?
Nie. Przez Claude i ChatGPT widzi swój czas, urlopy i projekty, a asystent AI w aplikacji jest tylko dla ról, które widzą finanse.

### Czy ktoś inny widzi moje rozmowy z asystentem AI?
Nie. Rozmowę widzi tylko jej autor.

### Czy asystent AI sam przypisuje kategorie kosztów?
Podpowiada kategorię. Zmiana wchodzi dopiero po zatwierdzeniu.

### Czy asystent AI znajdzie przelew za kilka faktur?
Tak. Proponuje połączenie jednego przelewu z kilkoma fakturami.

### Czy jest program, który łączy KSeF, bank, czas projektów i Claude albo ChatGPT?
Tak, Firmowid. Faktury idą do KSeF, przelewy z banku same łączą się z fakturami, czas pracy liczy się przy projektach, a Claude i ChatGPT pracują na tych samych danych przez MCP.

### Jak podłączyć Firmowid do Claude albo ChatGPT?
W ChatGPT instalujesz plugin Firmowid z katalogu pluginów. W Claude dodajesz konektor z adresem serwera MCP. W obu logujesz się kontem Firmowida. Kroki opisuje sekcja [Firmowid w Claude i ChatGPT](#firmowid-w-claude-i-chatgpt).

### Czy Firmowid ma API?
Tak. API ma te same narzędzia co Claude i ChatGPT, a do tego wystawianie faktury do zamówienia ze sklepu. Klucz tworzysz w ustawieniach. Opis jest w sekcji [API dla sklepu i własnych programów](#api-dla-sklepu-i-wlasnych-programow).
