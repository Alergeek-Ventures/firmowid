import { getPreferenceValues, LocalStorage, OAuth } from "@raycast/api";
import { OAuthService } from "@raycast/utils";
import { z } from "zod";

import { fetchFirmowid } from "./http";

const MetadataSchema = z.object({
  authorization_endpoint: z.url(),
  token_endpoint: z.url(),
  registration_endpoint: z.url(),
});

const ClientSchema = z.object({ client_id: z.string().min(1) });

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

const origin = getOrigin();

const client = new OAuth.PKCEClient({
  redirectMethod: OAuth.RedirectMethod.Web,
  providerName: "Firmowid",
  providerId: `firmowid:timetracker:${origin}`,
  providerIcon: "icon.png",
});

const clientKey = `oauth-client:timetracker:${origin}`;

async function discovery() {
  const response = await fetchFirmowid(
    `${origin}/.well-known/oauth-authorization-server`
  );

  if (!response.ok) {
    throw new Error("Couldn't load the Firmowid sign-in configuration.");
  }

  return MetadataSchema.parse(await response.json());
}

export async function authorize(): Promise<string> {
  const tokens = await client.getTokens();

  if (tokens?.accessToken && !tokens.isExpired()) {
    return tokens.accessToken;
  }

  const metadata = await discovery();

  const storedClientId = tokens?.refreshToken
    ? await LocalStorage.getItem<string>(clientKey)
    : undefined;

  const clientId = storedClientId ?? (await register(metadata));

  const service = new OAuthService({
    client,
    clientId,
    scope: "api",
    authorizeUrl: metadata.authorization_endpoint,
    tokenUrl: metadata.token_endpoint,
    bodyEncoding: "url-encoded",
  });

  return service.authorize();
}

async function register(
  metadata: z.infer<typeof MetadataSchema>
): Promise<string> {
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

  const { client_id: clientId } = ClientSchema.parse(await response.json());

  await LocalStorage.setItem(clientKey, clientId);

  return clientId;
}

export async function invalidateAccessToken({
  token,
}: {
  token: string;
}): Promise<void> {
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
