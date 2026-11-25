defmodule FirmowidWeb.Invoicing.Api do
  @moduledoc """
  Version 1 of the public API, served at `/api/v1` to an organization's servers with one of its
  API keys (see `Firmowid.Core.ApiKey`). It issues and reads sales invoices; the routes are in
  the `json_api` block of `Firmowid.Invoicing`, and `/api/v1/open_api` describes them.
  """

  use AshJsonApi.Router,
    domains: [Firmowid.Invoicing],
    open_api: "/open_api",
    open_api_title: "Firmowid API",
    open_api_version: "1.0.0"
end
