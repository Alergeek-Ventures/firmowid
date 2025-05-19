import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/firmowid start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :firmowid, FirmowidWeb.Endpoint, server: true
end

# is this necessary? the variables:
# go_limitless_secret_id and
# go_limitless_secret_key
# are set in config/config.exs file anyway, and this here overrides those settings with nil, but I can't use import_config in here:
# "
# import_config/1 is not enabled for this configuration file.
# Some configuration files do not allow importing other files as they are often copied to external systems
# "
# with the below config commented, secret_id and secret_key from config/config.exs still hold, and tests pass

# config :firmowid,
#   go_limitless_secret_id: read_config(:firmowid)[:go_limitless_secret_id],
#   go_limitless_secret_key: read_config(:firmowid)[:go_limitless_secret_key]

if config_env() == :prod do
  config :firmowid, Firmowid.Repo,
    ssl: [
      verify: :verify_peer,
      cacertfile: :certifi.cacertfile()
    ],
    url: System.get_env("DATABASE_URL", "firmowid"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :firmowid, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :firmowid, FirmowidWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # configures Swoosh SMTP client
  config :firmowid, Firmowid.Mailer,
    adapter: Swoosh.Adapters.Sendgrid,
    api_key: System.get_env("SENDGRID_API_KEY")
end
