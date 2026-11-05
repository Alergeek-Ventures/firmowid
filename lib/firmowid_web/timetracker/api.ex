defmodule FirmowidWeb.Timetracker.Api do
  @moduledoc "REST endpoints generated from the time tracking resources."

  use AshJsonApi.Router,
    domains: [Firmowid.Timetracker]
end
