# Firmowid
## Baza Danych
- wejdź do `local` i odpal `docker compose up` lub (`docker compose up -d` jeśli chcesz dalej używać tego terminala)
  (`podman compose up` dla odważnych)

## Środowisko dla elixira  
- wejdź spowrotem do folderu firmowid (`cd ..`)
- spróbuj zbuildować dockerfile `docker build -t firmowid .` 
- następnie: `docker run -it --rm firmowid`

## 
## Jeśli Dockerfile nie działa: Instalacja środowiska lokalnie 



### macOS, Ubuntu, Windows
ℹ️ **Note**: W przypadku windowsa najlepiej będzie użyć **WSL** ponieważ instalacja niektórych paczek może być problematyczna:

 W swoim systemie:
1. Zainstaluj elixir i erlang

```bash
curl -fsSO https://elixir-lang.org/install.sh
sh install.sh elixir@1.18.1 otp@27.2
installs_dir=$HOME/.elixir-install/installs
export PATH=$installs_dir/otp/27.2/bin:$PATH
export PATH=$installs_dir/elixir/1.18.1-otp-27/bin:$PATH
```

2. Zainstaluj paczki do elixira
```bash
sudo apt-get update -y && sudo apt-get install -y build-essential git && sudo apt-get clean`
```
```bash
sudo apt-get update -y && \
  sudo apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates libvips chromium \
  && sudo apt-get clean 
```
3. W głównym folderze `firmowid`:
    - zainstaluj zależności `mix setup`
    - włącz serwer: `mix phx.server`
    - wejdź na [`localhost:4000`](http://localhost:4000)
### Inne distro Linuxa
Zainstaluj elixir i erlang według [instrukcji](https://elixir-lang.org/install.html) pamiętaj aby wersje się zgadzały tzn.
- elixir - 1.18.1
- otp - 27.2

Następnie postępuj zgodnie z instrukcjami od **Punktu 2.**



