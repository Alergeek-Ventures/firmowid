---
title: "Program do faktur KSeF open source na własny serwer"
description: "Firmowid ma otwarty kod na licencji AGPL-3.0. Uruchomisz go na własnym serwerze bez opłaty licencyjnej. Co jest w kodzie i czym różni się od firmowid.pl."
published: 2026-11-23
updated: 2026-11-27
path: /open-source
landing:
  kicker: "Open source · AGPL-3.0"
  note: "ten sam kod co na firmowid.pl"
  facts:
    - label: "Licencja"
      value: "AGPL-3.0"
    - label: "Opłata licencyjna"
      value: "0 zł"
    - label: "Kod"
      value: "publiczny, na GitHubie"
---

![KSeF w chmurze, na własnym serwerze i w programie desktopowym: gdzie działa, kto robi aktualizacje i kopie zapasowe i dla kogo jest każdy model](/images/guides/ksef-self-hosted-chmura-czy-wlasny-serwer.webp)

## Co jest w otwartym kodzie

Cały program. Faktury i KSeF, faktury kosztowe, bank z dopasowaniem przelewów, Skrzynka, analiza, czas pracy, zespół z urlopami, delegacje, asystent AI i serwer MCP dla Claude i ChatGPT.

Na firmowid.pl działa ten sam kod. Każda zmiana na gałęzi `main` trafia na firmowid.pl, a własną instalację budujesz z tej samej gałęzi.

Kod leży w [repozytorium Firmowida na GitHubie](https://github.com/Alergeek-Ventures/firmowid), razem z instrukcją uruchomienia w pliku README.

## firmowid.pl czy własny serwer

| | firmowid.pl | Własny serwer |
|---|---|---|
| Kod | ten sam, z gałęzi `main` | ten sam, budujesz z gałęzi `main` |
| Opłata | plan Darmowy 0 zł, płatne plany od 9 do 149 zł netto miesięcznie | brak opłaty licencyjnej, płacisz za serwer |
| Aktualizacje i kopie zapasowe | robimy my | robisz Ty albo Twój administrator |
| KSeF | Profil Zaufany, certyfikat albo token | tak samo |
| Bank | w cenie planu | własne konto w GoCardless |
| Asystent AI i opisy faktur | w cenie planu | własny klucz OpenAI |
| Odczyt faktur ze zdjęć i PDF | w cenie planu | własny klucz Reducto |
| E-maile do klientów | w cenie planu | własny klucz Resend |
| Limity planu | według wybranego planu | ustawienie organizacji w Twojej bazie danych |

Bez kluczy do zewnętrznych usług program też działa. Wyłączone są wtedy tylko funkcje, które z nich korzystają, na przykład pobieranie przelewów z banku.

## Czego potrzebujesz

| Krok | Gdzie | Co |
|---|---|---|
| Serwer | Twój serwer albo VPS | Linux z Dockerem albo Podmanem, a obok PostgreSQL, magazyn plików zgodny z S3 i Gotenberg do PDF-ów |
| Konfiguracja | README i `env.template` | klucze szyfrowania, adres bazy i środowisko KSeF `prod`, a dla banku, AI i e-maili własne klucze |
| Połączenie z KSeF | ustawienia firmy w Firmowidzie | Profil Zaufany, certyfikat albo token, jak na firmowid.pl: [Jak połączyć Firmowid z KSeF](/pomoc/polaczenie-z-ksef) |

Gotowego instalatora ani wydań z numerem wersji nie ma. Instalację budujesz z gałęzi `main` i sam decydujesz, kiedy ją aktualizujesz.

## Kiedy własny serwer, a kiedy firmowid.pl

**Własny serwer** ma sens, gdy masz administratora i chcesz trzymać faktury na swojej infrastrukturze. Bierzesz wtedy na siebie aktualizacje, kopie zapasowe, certyfikat TLS i dostęp użytkowników.

**firmowid.pl** wystarczy, gdy nie chcesz zajmować się serwerem. Plan Darmowy nie ma limitu faktur ani wysyłki do KSeF.

Porównanie chmury, własnego serwera i programu desktopowego: [KSeF self-hosted: czy własny serwer jest bezpieczniejszy?](/poradnik/ksef-self-hosted)

## Licencja AGPL-3.0

Program możesz uruchomić w firmie, zmieniać i rozwijać bez opłat. Gdy zmienioną wersję udostępniasz innym przez sieć, musisz dać im też jej kod na tej samej licencji. Pełny tekst jest w pliku [LICENSE](https://github.com/Alergeek-Ventures/firmowid/blob/main/LICENSE).

## Jak pomóc w rozwoju

Pytania zadajesz, a pomysły zgłaszasz w [Dyskusjach na GitHubie](https://github.com/Alergeek-Ventures/firmowid/discussions). Błąd zgłaszasz jako issue z krokami do odtworzenia, a poprawkę wysyłasz jako pull request do gałęzi `main`. Podatności zgłaszasz prywatnie, według pliku [SECURITY.md](https://github.com/Alergeek-Ventures/firmowid/blob/main/SECURITY.md).

## Najważniejsze dane

| | |
|---|---|
| Licencja | AGPL-3.0-or-later |
| Technologia | Elixir, Phoenix LiveView, Ash Framework |
| Baza danych | PostgreSQL |
| Wydania z numerem wersji | nie, instalacja z gałęzi `main` |
| Opłata licencyjna | 0 zł |

Zobacz też: [Polskie programy open source do faktur i KSeF](/poradnik/polskie-programy-open-source-do-faktur) · [Cennik](/cennik) · [Wszystkie funkcje](/funkcje)

## Najczęstsze pytania

### Czy wersja open source jest okrojona?
Nie. Na GitHubie jest ten sam kod, który działa na firmowid.pl.

### Ile kosztuje własna instalacja?
Licencja nic nie kosztuje. Płacisz za serwer i za zewnętrzne usługi, z których chcesz korzystać, na przykład połączenie z bankiem albo asystenta AI.

### Czy na własnym serwerze działa KSeF?
Tak. Firma łączy się z KSeF tak samo jak na firmowid.pl: Profilem Zaufanym, certyfikatem albo tokenem.

### Gdzie zadać pytanie o instalację?
W [Dyskusjach na GitHubie](https://github.com/Alergeek-Ventures/firmowid/discussions).
