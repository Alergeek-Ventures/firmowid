# Firmowid

## Jeśli masz już zainstalowane środowisko:
### 1. Baza Danych
- wejdź do folderu `local` i odpal `docker compose up` lub (`docker compose up -d` jeśli chcesz dalej używać tego terminala)
  (`podman compose up` dla odważnych)

### 2. W głównym folderze `firmowid`:
  - zainstaluj zależności `mix setup`
  - włącz serwer: `mix phx.server`
  - wejdź na [`localhost:4000`](http://localhost:4000)


## Instalacja Środowiska dla elixira:  
Do zarządzania wersjami elixira używamy [asdf](https://asdf-vm.com/guide/getting-started.html)
### MacOS, Linux, Windows
ℹ️ **Note**: W przypadku Windowsa najlepiej będzie użyć **WSL** ponieważ instalacja niektórych paczek może być problematyczna.

### 1. Zainstaluj [asdf](https://asdf-vm.com/guide/getting-started.html)
### 2. Zainstaluj [erlang](https://github.com/asdf-vm/asdf-erlang) (OTP) za pomocą asdf
  
 **Najpierw** zainstaluj dependencies zgodnie ze swoim OS (instrukcja w [README](https://github.com/asdf-vm/asdf-erlang))

  Następnie:
  ```bash
  asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
  asdf install erlang 27.2
  asdf set erlang 27.2
  export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
  ```

### 3. Zainstaluj [elixir](https://github.com/asdf-vm/asdf-elixir.git) za pomocą asdf 

```bash
sudo apt install unzip
asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
asdf install elixir 1.18
asdf set elixir 1.18
```
### 4. Zainstaluj paczki systemowe:
```
sudo apt-get install -y build-essential git libstdc++6 openssl libncurses5 locales ca-certificates libvips chromium
```




