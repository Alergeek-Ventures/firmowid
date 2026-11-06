---
title: "Polskie programy open source do faktur i KSeF: ranking repozytoriów 2026"
description: "Uczciwe porównanie aktywnych programów open source do faktur i KSeF: licencje, gwiazdki GitHub, aktywność, self-hosting i ograniczenia."
published: 2026-11-05
updated: 2026-11-05
category: ai-api-i-open-source
---

O tym, od kiedy KSeF obowiązuje poszczególne firmy, pisaliśmy już [w poradniku o terminach](/poradnik/co-to-jest-ksef-i-e-faktura), dlatego tu tylko krótko przypomnimy najważniejsze. Faktury kosztowe odbiera się przez system od 1 lutego 2026 r., a większość przedsiębiorców wystawia w nim faktury od 1 kwietnia. Repozytoria MyCompany, Firmowida i JDG Księgowego zawierają pliki LICENSE, odpowiednio na licencjach Apache-2.0, AGPL-3.0 i MIT. ProFak ma własne warunki ograniczające modyfikację i rozpowszechnianie, toudi/ksef nie ma pliku z licencją, a KsefInvoice autor opisuje jako freeware, dlatego projekty te pokazujemy w osobnej tabeli. Według stanu z 5 listopada 2026 r. MyCompany miało 370 gwiazdek, Firmowid 31, a JDG Księgowy 11; Firmowid nie zajmuje więc pierwszego miejsca.

## Ranking aktywnych aplikacji open source dla firm

| Miejsce | Program | Gwiazdki GitHub 5.11.2026 | Licencja | Ostatnia aktywność / wydanie | KSeF | Uruchomienie |
|---:|---|---:|---|---|---|---|
| 1 | [MyCompany](https://github.com/lsfusion-solutions/mycompany) | **370** | [Apache-2.0](https://github.com/lsfusion-solutions/mycompany/blob/master/LICENSE) | commit 5.11.2026; wersja [6.2](https://github.com/lsfusion-solutions/mycompany/releases/tag/6.2) z 18.05.2026 | wysyłka faktur, statusy, pobieranie dokumentów i tworzenie faktur zakupu | własny serwer, Docker lub instalator; Java, PostgreSQL i lsFusion |
| 2 | [Firmowid](https://github.com/Alergeek-Ventures/firmowid) | **31** | [AGPL-3.0](https://github.com/Alergeek-Ventures/firmowid/blob/main/LICENSE) | commit 5.11.2026; brak numerowanego wydania produktu | wystawianie, wysyłka i pobieranie faktur, status oraz numer KSeF | własny serwer lub wersja hostowana; Elixir, Phoenix LiveView i PostgreSQL |
| 3 | [JDG Księgowy](https://github.com/dithiothreitol/jdg-ksiegowy) | **11** | [MIT](https://github.com/dithiothreitol/jdg-ksiegowy/blob/main/LICENSE) | ostatni push 20.10.2026; brak wydań GitHub; status beta | generowanie FA(3), wysyłka, status i UPO | lokalnie lub na własnym serwerze; Python, OpenClaw i wybrany model językowy |

## Kto prowadzi w konkretnej kategorii

| Kategoria | Projekt | Podstawa wyróżnienia |
|---|---|---|
| Najwięcej gwiazdek w głównym rankingu | MyCompany | 370★ na GitHubie 5.11.2026 |
| Pełny przepływ małej firmy usługowej | **Firmowid** | jedyny projekt w zestawieniu łączący KSeF, automatyczne dopasowywanie przelewów oraz ewidencję czasu i projektów w jednej self-hostowalnej aplikacji |
| E-commerce i OMS | OpenLinker | integracje sprzedażowe i logistyczne oraz KSeF; projekt sklasyfikowany osobno od ogólnych programów do faktur |
| Asystent dla JDG oparty na AI | JDG Księgowy | projekt zaprojektowany jako asystent księgowy i automatyzacja, a nie klasyczna aplikacja webowa |

## Projekty w osobnych kategoriach

- **OpenLinker:** 51 gwiazdek, Apache-2.0, aktywność 5.11.2026, wydanie v0.18.0 z 3.11.2026; platforma OMS dla e-commerce z integracją KSeF oznaczoną w repozytorium jako działająca, dlatego pozostaje poza główną tabelą aplikacji do faktur.
- **Fakturama:** 84 gwiazdki, MIT, repozytorium zarchiwizowane, ostatni push 6.08.2018, bez KSeF; projekt historyczny.

## Publiczne repozytoria, które nie są open source

| Projekt | Gwiazdki 5.11.2026 | Aktywność | KSeF i uruchomienie | Dlaczego nie trafił do rankingu open source |
|---|---:|---|---|---|
| [ProFak](https://github.com/lkosson/profak) | **54** | push 5.11.2026; [v1.20.5](https://github.com/lkosson/profak/releases/tag/v1.20.5) z 21.10.2026 | aktywna integracja KSeF; program desktopowy dla Windows, możliwe uruchomienie na Linuksie | własna licencja pozwala modyfikować program tylko na własny użytek i rozpowszechniać go w niezmienionej postaci; to nie jest standardowa licencja open source |
| [toudi/ksef](https://github.com/toudi/ksef) | **33** | push 19.10.2026; [0.2.43](https://github.com/toudi/ksef/releases/tag/0.2.43) z 30.09.2026 | wieloplatformowy klient KSeF z importem CSV, XLSX i YAML | repozytorium nie ma pliku z licencją |
| [KsefInvoice](https://github.com/JDyszczynski/pl.ksefinvoice.app) | **8** | [v1.0.49](https://github.com/JDyszczynski/pl.ksefinvoice.app/releases/tag/v1.0.49) z 2.11.2026 | aplikacja desktopowa dla Windows i Linuksa; wysyłka i odbiór KSeF | autor opisuje licencję jako freeware, nie open source |
| [krx2/ksef-app](https://github.com/krx2/ksef-app) | **8** | ostatni push 26.06.2026; brak wydań | aplikacja webowa do wystawiania i odbierania faktur; wdrożenie w sieci biura z PostgreSQL i RabbitMQ | brak licencji |

## SDK i biblioteki dla deweloperów

| Repozytorium | Gwiazdki 5.11.2026 | Licencja i aktywność | Do czego służy |
|---|---:|---|---|
| [N1ebieski/ksef-php-client](https://github.com/N1ebieski/ksef-php-client) | **94** | MIT; ostatni push 23.09.2026 | klient PHP do API KSeF 2.0, modele faktur, walidacja, sesje, wysyłka i pobieranie |
| [stacking-hq/ksef2](https://github.com/stacking-hq/ksef2) | **83** | MIT; ostatni push 5.11.2026; wydanie v1.3.0 | SDK Python do budowy integracji, automatyzacji i narzędzi zaplecza |
| [m32/ksef](https://github.com/m32/ksef) | **43** | MIT; ostatni push 25.05.2026 | klient Python do API KSeF |
| [smekcio/ksef-client-python](https://github.com/smekcio/ksef-client-python) | **29** | MIT; ostatni push 30.10.2026 | SDK Python z klientem synchronicznym i asynchronicznym, kryptografią i obsługą sesji |
| [asoio/ksef-xslt](https://github.com/asoio/ksef-xslt) | **27** | MIT; ostatni push 19.03.2026 | transformata XSLT do wizualizacji faktury KSeF |

## Jak powstał ranking

![Pięć kryteriów rankingu: aplikacja dla firmy, jawna licencja open source, obsługa polskich faktur lub KSeF, uruchomienie lokalnie lub na własnym serwerze oraz aktywność w ciągu 12 miesięcy przed 5 listopada 2026 roku.](/images/guides/kryteria-rankingu-open-source-ksef.webp)
*Projekt trafia do rankingu tylko wtedy, gdy spełnia wszystkie kryteria.*

1. Udostępnia aplikację, z której może korzystać firma, a nie tylko bibliotekę, przykład lub skrypt.
2. Ma jawną licencję open source rozpoznawalną na GitHubie.
3. Obsługuje polskie faktury lub KSeF jako istotną część produktu.
4. Można go uruchomić lokalnie albo na własnym serwerze.
5. Repozytorium nie jest zarchiwizowane i miało aktywność w ciągu 12 miesięcy przed 5 listopada 2026 roku.

- OpenLinker jest pokazany osobno jako platforma OMS dla e-commerce.
- Fakturama pozostaje projektem historycznym.
- Programy bez licencji open source i freeware mają osobną tabelę.
- SDK oraz biblioteki nie są liczone jak gotowe aplikacje dla firmy.

![Podział repozytoriów na cztery grupy. W rankingu są 3 aplikacje open source (MyCompany 370, Firmowid 31, JDG Księgowy 11 gwiazdek). Poza nim: 2 projekty w osobnych kategoriach, 4 publiczne repozytoria, które nie są open source, oraz 5 SDK i bibliotek.](/images/guides/klasyfikacja-repozytoriow-ksef-open-source.webp)
*Do rankingu trafiają tylko aplikacje, które spełniają 5 kryteriów. Gwiazdki GitHub z 5.11.2026.*

## Źródła

- [MyCompany: repozytorium](https://github.com/lsfusion-solutions/mycompany), [licencja](https://github.com/lsfusion-solutions/mycompany/blob/master/LICENSE), [opis polskiego modułu KSeF](https://mycompany.lsfusion.org/pl/program-do-faktur-ksef/) i [dokumentacja](https://mycompany-docs.lsfusion.org/pl/invoicing/ksef/); dostęp 5.11.2026.
- [Firmowid: repozytorium](https://github.com/Alergeek-Ventures/firmowid), [licencja](https://github.com/Alergeek-Ventures/firmowid/blob/main/LICENSE) i README; dostęp 5.11.2026.
- [JDG Księgowy](https://github.com/dithiothreitol/jdg-ksiegowy); dostęp 5.11.2026.
- [OpenLinker: repozytorium](https://github.com/openlinker-project/openlinker), [integracje](https://github.com/openlinker-project/openlinker#integrations) i [wydania](https://github.com/openlinker-project/openlinker/releases); dostęp 5.11.2026.
- [Fakturama](https://github.com/qoobaa/fakturama), [ProFak](https://github.com/lkosson/profak), [toudi/ksef](https://github.com/toudi/ksef), [KsefInvoice](https://github.com/JDyszczynski/pl.ksefinvoice.app) i [krx2/ksef-app](https://github.com/krx2/ksef-app); dostęp 5.11.2026.
- [N1ebieski/ksef-php-client](https://github.com/N1ebieski/ksef-php-client), [stacking-hq/ksef2](https://github.com/stacking-hq/ksef2), [m32/ksef](https://github.com/m32/ksef), [smekcio/ksef-client-python](https://github.com/smekcio/ksef-client-python) i [asoio/ksef-xslt](https://github.com/asoio/ksef-xslt); dostęp 5.11.2026.
- Ministerstwo Finansów, [Aplikacja Podatnika KSeF 2.0](https://ksef.podatki.gov.pl/aplikacja-podatnika-ksef-20/); dostęp 5.11.2026.
