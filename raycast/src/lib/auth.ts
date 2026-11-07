import { getPreferenceValues, LocalStorage, OAuth } from "@raycast/api";
import { OAuthService } from "@raycast/utils";
import { z } from "zod";

import { fetchFirmowid, rethrowConnectionError } from "./http";

const MetadataSchema = z.object({
  authorization_endpoint: z.url(),
  token_endpoint: z.url(),
  registration_endpoint: z.url(),
  revocation_endpoint: z.url(),
});

const ClientSchema = z.object({ client_id: z.string().min(1) });

const TokenSchema = z.object({
  access_token: z.string().min(1),
  refresh_token: z.string().min(1),
  expires_in: z.number().positive(),
  scope: z.string(),
});

const OAuthErrorSchema = z.object({ error: z.string() });

export class AuthenticationError extends Error {
  constructor(message = "Sign in to Firmowid again.") {
    super(message);
    this.name = "AuthenticationError";
  }
}

export function getOrigin(): string {
  const { serverUrl } = getPreferenceValues<Preferences>();
  const url = new URL(serverUrl.trim());

  const local =
    ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname) ||
    url.hostname.endsWith(".localhost");

  if (
    (url.protocol !== "https:" && !(url.protocol === "http:" && local)) ||
    url.username ||
    url.password ||
    url.pathname !== "/" ||
    url.search ||
    url.hash
  ) {
    throw new Error(
      "Enter the HTTPS URL of your Firmowid instance without a path. HTTP is supported only for local servers."
    );
  }

  return url.origin;
}

function oauthClient(origin: string) {
  return new OAuth.PKCEClient({
    redirectMethod: OAuth.RedirectMethod.Web,
    providerName: "Firmowid",
    providerId: `firmowid:timetracker:${origin}`,
    providerIcon: "icon.png",
  });
}

function clientKey(origin: string) {
  return `oauth-client:timetracker:${origin}`;
}

async function discovery(origin: string) {
  const response = await fetchFirmowid(
    `${origin}/.well-known/oauth-authorization-server`
  );

  if (!response.ok) {
    throw new Error("Couldn't load the Firmowid sign-in configuration.");
  }

  return MetadataSchema.parse(await response.json());
}

async function requestTokens(
  endpoint: string,
  parameters: Record<string, string>
) {
  const response = await fetchFirmowid(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: new URLSearchParams(parameters),
  });

  if (!response.ok) {
    if (response.status !== 400 && response.status !== 401) {
      throw new Error(`Firmowid returned an error (${response.status}).`);
    }

    const error = OAuthErrorSchema.parse(await response.json());

    if (error.error === "invalid_grant" || error.error === "invalid_client") {
      throw new AuthenticationError();
    }

    throw new Error(`Firmowid rejected the sign-in request (${error.error}).`);
  }

  return TokenSchema.parse(await response.json());
}

export async function getBackgroundAccessToken(): Promise<string | undefined> {
  const origin = getOrigin();
  const client = oauthClient(origin);
  const tokens = await client.getTokens();

  if (tokens && !tokens.isExpired()) {
    return tokens.accessToken;
  }

  if (!tokens?.refreshToken) {
    return undefined;
  }

  const storedClientId = await LocalStorage.getItem<string>(clientKey(origin));

  if (storedClientId) {
    const metadata = await discovery(origin);

    try {
      const refreshed = await requestTokens(metadata.token_endpoint, {
        grant_type: "refresh_token",
        client_id: storedClientId,
        refresh_token: tokens.refreshToken,
      });

      // Do not restore tokens after the user logs out during a refresh.
      if (!(await client.getTokens())) {
        return undefined;
      }

      await client.setTokens(refreshed);

      return refreshed.access_token;
    } catch (error) {
      if (!(error instanceof AuthenticationError)) {
        throw error;
      }

      await client.removeTokens();
      await LocalStorage.removeItem(clientKey(origin));
    }
  }

  return undefined;
}

export async function authorize(): Promise<string> {
  // OAuthService clears tokens on any failed refresh, including service outages.
  const accessToken = await getBackgroundAccessToken();

  if (accessToken) {
    return accessToken;
  }

  const origin = getOrigin();
  const client = oauthClient(origin);

  const [metadata, storedClientId] = await Promise.all([
    discovery(origin),
    LocalStorage.getItem<string>(clientKey(origin)),
  ]);

  let clientId = storedClientId;

  if (!clientId) {
    const request = await client.authorizationRequest({
      endpoint: metadata.authorization_endpoint,
      clientId: "registration",
      scope: "api",
    });

    const response = await fetchFirmowid(metadata.registration_endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        client_name: "Firmowid for Raycast",
        redirect_uris: [request.redirectURI],
        grant_types: ["authorization_code", "refresh_token"],
        response_types: ["code"],
        token_endpoint_auth_method: "none",
      }),
    });

    if (!response.ok) {
      throw new Error("Couldn't register the extension with Firmowid.");
    }

    clientId = ClientSchema.parse(await response.json()).client_id;
    await LocalStorage.setItem(clientKey(origin), clientId);
  }

  const service = new OAuthService({
    client,
    clientId,
    scope: "api",
    authorizeUrl: metadata.authorization_endpoint,
    tokenUrl: metadata.token_endpoint,
    bodyEncoding: "url-encoded",
    tokenResponseParser: (response) => TokenSchema.parse(response),
    tokenRefreshResponseParser: (response) => TokenSchema.parse(response),
  });

  try {
    return await service.authorize();
  } catch (error) {
    rethrowConnectionError(error, origin);
  }
}

export async function invalidateAccessToken({
  origin,
  token,
}: {
  origin: string;
  token: string;
}): Promise<void> {
  const client = oauthClient(origin);
  const tokens = await client.getTokens();

  if (tokens?.accessToken === token) {
    await client.setTokens({
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      idToken: tokens.idToken,
      scope: tokens.scope,
      expiresIn: 0,
    });
  }
}

export async function signOut(): Promise<void> {
  const origin = getOrigin();
  const client = oauthClient(origin);

  const [tokens, clientId] = await Promise.all([
    client.getTokens(),
    LocalStorage.getItem<string>(clientKey(origin)),
  ]);

  await client.removeTokens();

  if (!tokens?.refreshToken || !clientId) {
    return;
  }

  const metadata = await discovery(origin);

  const response = await fetchFirmowid(metadata.revocation_endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: new URLSearchParams({
      client_id: clientId,
      token: tokens.refreshToken,
      token_type_hint: "refresh_token",
    }),
  });

  if (!response.ok) {
    throw new Error(
      "Signed out locally, but Firmowid couldn't confirm that access was revoked."
    );
  }
}
