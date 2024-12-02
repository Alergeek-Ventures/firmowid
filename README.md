# Firmowid

## lokalne środowisko

- wystartuj bazę: `docker run --rm --name redux-postgres -p 5432:5432 -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres paradedb/paradedb`
- zainstaluj zależności i odpal migracje: `mix setup`
- włącz serwer: `mix phx.server`
- wejdź na [`localhost:4000`](http://localhost:4000)
