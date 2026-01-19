# Stop PhoenixAnalytics to prevent Batcher from trying to write to the database
# (it doesn't use Sandbox and causes ownership errors)
Application.stop(:phoenix_analytics)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Firmowid.Repo, :manual)
