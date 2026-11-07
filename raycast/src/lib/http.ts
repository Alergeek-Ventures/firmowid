/** Adds the Firmowid address and recovery steps to transport failures. */
export async function fetchFirmowid(
  url: string,
  options?: RequestInit
): Promise<Response> {
  try {
    return await fetch(url, options);
  } catch (error) {
    rethrowConnectionError(error, url);
  }
}

/** Adds the same connection context to requests made by OAuthService. */
export function rethrowConnectionError(cause: unknown, url: string): never {
  if (!(cause instanceof TypeError)) {
    throw cause;
  }

  throw new Error(
    `Couldn't connect to Firmowid at ${new URL(url).origin}. Check that the server is running and that the extension's Firmowid URL setting is correct.`,
    { cause }
  );
}
