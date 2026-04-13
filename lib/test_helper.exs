# Tests tagged :external require real third-party credentials (e.g. GoCardless).
# They are excluded by default so CI and plain `mix test` skip them.
# Use `mix test --include external` to run them.
ExUnit.configure(exclude: [:external])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Firmowid.Repo, :manual)
