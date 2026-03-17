# Stop PhoenixAnalytics to prevent Batcher from trying to write to the database
# (it doesn't use Sandbox and causes ownership errors)
Application.stop(:phoenix_analytics)

# Tests tagged :external require real third-party credentials (e.g. GoCardless).
# They are excluded by default so CI and plain `mix test` skip them.
# Use `mix test --include external` or `mix check` (which passes --include) to run them locally.
ExUnit.configure(exclude: [:external])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Firmowid.Repo, :manual)
