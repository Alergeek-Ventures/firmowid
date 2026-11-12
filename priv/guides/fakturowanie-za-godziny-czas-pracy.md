---
title: "Faktura za godziny pracy: jak liczymy czas projektów i wystawiamy fakturę w KSeF"
description: "Jak w Firmowidzie godziny z licznika czasu w projekcie trafiają na fakturę w KSeF: raport godzin dla klienta, szkic faktury od asystenta albo Claude przez MCP, wysyłka po potwierdzeniu."
published: 2026-11-12
updated: 2026-11-12
category: firma-uslugowa
---

Kiedyś czas pracy zbieraliśmy w Excelu i w kilku innych narzędziach, a potem ktoś ręcznie oznaczał, w którym projekcie co się robiło. Teraz każdy pracownik ma w Firmowidzie przypisane projekty i wybiera ten, w którym zaczyna pracę: start, czas leci pod konkretnym projektem i nic więcej nie musi pamiętać, a projekt może w każdej chwili zmienić.

W widoku projektu widzimy, kto ile nad nim przepracował. Z tych godzin korzystamy przy wystawianiu faktury: sami albo prosząc asystenta, który przygotowuje szkic z liczbą godzin i stawką. To samo robi Claude podłączony przez MCP. Zawsze jest miejsce na zmianę danych, a do KSeF faktura idzie dopiero po naszym potwierdzeniu.

Klient dostaje fakturę, a do niej łatwo wygenerować raport godzin z projektu. Klienci są zadowoleni, że tak skrupulatnie i uczciwie liczymy czas pracy nad ich projektami.

## Jak to działa w Firmowidzie

| Element | Jak działa |
|---|---|
| Projekt | ma przypisanego klienta i pracowników |
| Licznik czasu | start i stop pod wybranym projektem, sesje z tytułami |
| Raport godzin | plik CSV z godzinami projektu za miesiąc, z widoku projektu |
| Szkic faktury | pozycja z liczbą godzin, jednostką i stawką, ręcznie, przez asystenta albo MCP |
| KSeF | wysyłka po potwierdzeniu, numer KSeF, mail do klienta |
| Plan Darmowy | czas pracy w 3 projektach |

## Inne programy

| Program | Czas pracy w projektach | KSeF | Faktura przez asystenta AI |
|---|---|---|---|
| Firmowid | tak | tak | tak, po potwierdzeniu |
| Fakturownia | w module Zadania | tak | MCP do odczytu |
| inFakt | nie | tak | MCP we wszystkich planach |
| Kadromierz, RCPonline | tak | nie | nie |

MCP działa od planu [Przedsiębiorca](/cennik).

![Porównanie programów: Firmowid ma czas pracy w projektach, KSeF i fakturę przez asystenta AI po potwierdzeniu. Fakturownia ma KSeF i czas pracy w module Zadania, inFakt ma KSeF i MCP, ale nie czas pracy w projektach. Kadromierz i RCPonline mają czas pracy, ale nie KSeF.](/images/guides/faktura-za-godziny-czas-pracy-programy.webp)

## Źródła

- Firmowid: kod źródłowy (AGPL-3.0), moduły czasu pracy, faktur i MCP, stan 11.11.2026.
- Cenniki i opisy funkcji Fakturowni, inFaktu, Kadromierza i RCPonline, stan na listopad 2026.
- Więcej o łączeniu programu z asystentem AI: [faktury w KSeF z ChatGPT i Claude](/poradnik/faktury-ksef-chatgpt-claude-mcp).
