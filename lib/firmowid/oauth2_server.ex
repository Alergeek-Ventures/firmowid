defmodule Firmowid.Oauth2Server do
  @moduledoc """
  OAuth 2.1 authorization-server configuration.

  Blocked accounts (in an organization without a billing plan; see the User
  `:access_block` calculation) are rejected by the User authentication
  preparation, which also covers bearer-token user loading. Accounts without an
  organization are rejected by OAuth grant actions and by the MCP authentication
  plug. Leaving the organization (archiving the member) revokes refresh tokens
  and removes codes and consent in the same transaction.

  The installed OAuth library uses stateless access JWTs: restoring a member can
  re-enable an unexpired access token issued before the archive. Its multi-action
  exchange also has no account-generation check across an archive/restore cycle.
  Permanent OAuth revocation across restoration requires support at the exchange
  and JWT verification boundaries; the current guards guarantee denial while the
  account has no organization.

  See `AshAuthentication.Oauth2Server` for all options.
  """

  use AshAuthentication.Oauth2Server,
    otp_app: :firmowid,
    user_resource: Firmowid.Ash.Core.User,
    issuer_url: {Firmowid.Ash.Core.Secrets, []},
    resource_url: {Firmowid.Ash.Core.Secrets, []},
    signing_secret: {Firmowid.Ash.Core.Secrets, []},
    client_resource: Firmowid.Ash.Core.OauthClient,
    authorization_code_resource: Firmowid.Ash.Core.OauthAuthorizationCode,
    refresh_token_resource: Firmowid.Ash.Core.OauthRefreshToken,
    consent_resource: Firmowid.Ash.Core.OauthConsent,
    scopes: ["mcp"],
    # Dynamic client registration (RFC 7591). The library default is
    # `false` for safety; the installer turns it on because most
    # people setting up an OAuth server today need it for MCP-style
    # flows (ChatGPT Apps SDK, Claude.ai connectors, etc.). Set to
    # `false` if your auth server is for a fixed set of first-party
    # clients only.
    dcr_enabled?: true,
    # Client ID Metadata Documents — clients identify with an HTTPS
    # URL pointing at their metadata. This is the registration
    # mechanism the MCP spec (2026-07-28) recommends; DCR above is
    # kept for backwards compatibility. Set to `false` if your auth
    # server is for a fixed set of first-party clients only.
    cimd_enabled?: true,
    cimd_fetcher: Firmowid.Oauth2.CimdMetadataFetcher,
    sign_in_path: "/zaloguj"
end
