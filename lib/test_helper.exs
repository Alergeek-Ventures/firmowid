# Tests tagged :external require real third-party credentials (e.g. GoCardless).
# Tests tagged :e2e are end-to-end Playwright tests that require a running server.
# They are excluded by default so CI and plain `mix test` skip them.
# Use `mix test --include external` or `mix test --include e2e` to run them.
ExUnit.configure(exclude: [:external, :e2e])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Firmowid.Repo, :manual)
