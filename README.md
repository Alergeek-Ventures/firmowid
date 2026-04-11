# Firmowid

> **Note for English speakers:** This product is designed for the Polish market, so the README is in Polish. For environment variable configuration, see `env.template` file which contains documentation in English.

## Jeśli masz już zainstalowane środowisko

### 1. Baza Danych

- wejdź do folderu `local` i odpal `docker compose up` lub (`docker compose up -d` jeśli chcesz dalej używać tego terminala)
  (`podman compose up` dla odważnych)

### 2. Konfiguracja zmiennych środowiskowych

- skopiuj `env.template` do `.env` (domyślne wartości działają od razu w środowisku deweloperskim)
- szczegóły w pliku `env.template`

### 3. W głównym folderze `firmowid`

- zainstaluj zależności `mix setup`
- włącz serwer: `mix phx.server`
- wejdź na [`localhost:4000`](http://localhost:4000)

## Development Guide

Po uruchomieniu serwera, zaloguj się na `kira@bytecraft.collective` / `kolejka123456` i odwiedź [`/development`](http://localhost:4000/development) aby zobaczyć pełny przewodnik po danych testowych, kontrahentach, projektach i scenariuszach KSeF.

## Instalacja Środowiska dla elixira  

Do zarządzania wersjami elixira używamy [asdf](https://asdf-vm.com/guide/getting-started.html)

### MacOS, Linux, Windows

ℹ️ **Note**: W przypadku Windowsa najlepiej będzie użyć **WSL** ponieważ instalacja niektórych paczek może być problematyczna.

### 1. Zainstaluj [asdf](https://asdf-vm.com/guide/getting-started.html)

### 2. Zainstaluj [erlang](https://github.com/asdf-vm/asdf-erlang) (OTP) za pomocą asdf
  
 **Najpierw** zainstaluj dependencies zgodnie ze swoim OS (instrukcja w [README](https://github.com/asdf-vm/asdf-erlang))

  Następnie:

  ```bash
  asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
  asdf install erlang
  export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
  ```

### 3. Zainstaluj [elixir](https://github.com/asdf-vm/asdf-elixir.git) za pomocą asdf

```bash
sudo apt install unzip
asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
asdf install elixir
```

### 4. Zainstaluj paczki systemowe

```
sudo apt-get install -y build-essential git libstdc++6 openssl libncurses5 locales ca-certificates libvips chromium
```

## Zmienne środowiskowe

Aplikacja używa zmiennych środowiskowych do konfiguracji. Skopiuj `env.template` do `.env` - domyślne wartości działają od razu z lokalnym docker-compose.

### Wymagane

- `DATABASE_URL` - string połączenia do PostgreSQL
- `SECRET_KEY_BASE` - klucz tajny Phoenix (wygeneruj przez `mix phx.gen.secret`)

### S3 Object Storage

Domyślnie skonfigurowane dla localstack w środowisku deweloperskim.

- `S3_HOST` - host endpointu S3 (domyślnie: `localhost`)
- `S3_SCHEME` - schemat URL (domyślnie: `http://`)
- `S3_PORT` - port S3 (domyślnie: `4566`)
- `AWS_ACCESS_KEY_ID` - klucz dostępu AWS
- `AWS_SECRET_ACCESS_KEY` - tajny klucz AWS

**Produkcja:** Skonfiguruj te zmienne aby wskazywały na twoje S3-kompatybilne storage (AWS S3, Tigris, MinIO, itp.)

### Opcjonalne serwisy

Wszystkie zewnętrzne serwisy są opcjonalne. Aplikacja będzie działać bez nich, choć niektóre funkcje będą wyłączone.

#### Analityka i monitoring

Śledzenie błędów jest obsługiwane przez Sentry.
Analityka i flagi funkcjonalności są obsługiwane przez PostHog i fun_with_flags.

#### Kursy walut

- `OPEN_EXCHANGE_RATES_APP_ID` - klucz API Open Exchange Rates (używa mock danych jeśli nie ustawione)

#### Integracja bankowa

- `GO_LIMITLESS_SECRET_ID` - GoCardless API secret ID
- `GO_LIMITLESS_SECRET_KEY` - GoCardless API secret key

#### Usługi AI

- `OPENAI_API_KEY` - klucz API OpenAI do wzbogacania faktur
- `REDUCTO_API_KEY` - klucz API Reducto do OCR dokumentów

#### Email

- `RESEND_API_KEY` - klucz API Resend do emaili transakcyjnych
- `RESEND_WEBHOOK_SECRET` - sekret do weryfikacji webhooków Resend

**Development:** Email używa lokalnego adaptera domyślnie, nie wymaga klucza API.

### Zmienne tylko dla produkcji

- `PHX_HOST` - domena aplikacji (wymagane w produkcji)
- `PHX_SERVER` - ustaw na `true` aby uruchomić serwer
- `PORT` - port HTTP (domyślnie: 4000)
- `POOL_SIZE` - rozmiar puli połączeń do bazy danych (domyślnie: 5)

## Zarządzanie zależnościami

### Automatyczne (Dependabot)

Dependabot otwiera PR-y w każdy poniedziałek o 06:00 czasu warszawskiego. Śledzi:

- **Paczki Elixir** — `mix.exs` / `mix.lock`
- **Obrazy kontenerów** — `deployment/Containerfile.*` (app, seaweedfs, chromium)
- **Obrazy w Compose** — `local/compose.yml` (paradedb, seaweedfs)
- **GitHub Actions** — wersje akcji w `.github/workflows/`

### Ręczne (deweloperzy)

Te wersje są przypięte w plikach, których Dependabot nie obsługuje.
Sprawdzaj je **co tydzień** przy okazji przeglądania PR-ów Dependabota:

| Co | Gdzie | Gdzie sprawdzić |
|----|-------|-----------------|
| Elixir | `.tool-versions` | <https://github.com/elixir-lang/elixir/releases> |
| Erlang/OTP | `.tool-versions` | <https://github.com/erlang/otp/releases> |
| Tailwind CSS CLI | `config/config.exs` (`:tailwind, version:`) | <https://github.com/tailwindlabs/tailwindcss/releases> |
| esbuild | `config/config.exs` (`:esbuild, version:`) | <https://github.com/evanw/esbuild/releases> |

> **Prompt dla agenta do cotygodniowego sprawdzenia:**
>
> ```
> Check for new stable releases of Elixir, Erlang/OTP, Tailwind CSS,
> and esbuild. Only consider releases that are at least 7 days old
> (supply chain attack mitigation). Compare with versions pinned in
> .tool-versions and config/config.exs. If any are outdated, bump them
> and run mix check. For Elixir/Erlang, also update the hexpm/elixir
> image tag in deployment/Containerfile.app to match.
> ```

## Worktree Development (dla równoległych agentów AI)

Projekt wspiera izolowane środowiska deweloperskie per branch poprzez git worktrees + worktrunk.

### Wymagania

1. **Worktrunk** - [zainstaluj z crates.io](https://crates.io/crates/worktrunk) lub `cargo install worktrunk`
2. **Caddy** - reverse proxy z admin API

### Konfiguracja Caddy

Caddy musi być uruchomiony z admin API dostępnym pod `localhost/caddy`. Szczegóły konfiguracji zależą od twojego setupu systemowego.

### Użycie

```bash
# Stwórz nowy worktree (automatycznie uruchamia izolowane serwisy)
wt switch --create feature-auth

# Pracuj w worktree
# Phoenix: http://feature-auth.firmowid.localhost
# Tidewave MCP: http://localhost:{PORT}/tidewave/mcp

# Usuń worktree (automatycznie zatrzymuje serwisy)
wt remove feature-auth
```

### Jak to działa

1. `wt switch --create` wywołuje hooki z `.config/wt.toml`:
   - generuje `.env.local` z deterministycznymi portami (hash z nazwy brancha)
   - `mix deps.get` / `mix setup` - instaluje zależności, migruje bazę
   - `mix dev.up` - uruchamia Compose + rejestruje route w Caddy

2. Każdy worktree dostaje izolowane:
   - Postgres container z osobnym portem
   - Localstack (S3) container z osobnym portem  
   - Chromium container z osobnym portem
   - Caddy route: `{branch}.firmowid.localhost` → `localhost:{port}`

3. `wt remove` wywołuje `mix dev.down` - zatrzymuje kontenery i usuwa route z Caddy
