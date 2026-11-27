# Tests tagged :external require real third-party credentials (e.g. GoCardless).
# They are excluded by default so CI and plain `mix test` skip them.
# Use `mix test --include external` to run them.
#
# `render_async/2`, `assert_patch`, `assert_redirect` and `assert_receive` wait at most
# `assert_receive_timeout`, 100 ms by default. Pages that read their lists in async tasks take
# up to that long locally, and longer on a busy CI runner, so they get 2 s. A passing test
# finishes as soon as the work does; only a failing one waits the whole limit.
ExUnit.configure(exclude: [:external], assert_receive_timeout: 2_000)
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Firmowid.Repo, :manual)
