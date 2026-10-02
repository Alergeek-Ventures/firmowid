defmodule Firmowid.Config.ChatgptOauthResource do
  @moduledoc """
  Validates the optional canonical OAuth resource for isolated ChatGPT development.

  Runtime config reads this setting only in development. It changes the shared
  OAuth audience, not the transport URL or incoming resource parameters.
  """

  @resource_pattern ~r/\Ahttps:\/\/tunnel-service\.gateway\.unified-0\.internal\.api\.openai\.org(?::443)?\/v1\/mcp\/tunnel_[0-9a-f]{32}\z/

  @doc "Returns an absent override or the exact validated URL; raises on malformed configuration."
  @spec validate!(String.t() | nil) :: String.t() | nil
  def validate!(nil), do: nil

  def validate!(value) when is_binary(value) do
    if Regex.match?(@resource_pattern, value) do
      value
    else
      raise ArgumentError,
            "Invalid CHATGPT_OAUTH_RESOURCE_URL: expected the exact HTTPS OpenAI tunnel resource URL"
    end
  end
end
