defmodule Firmowid.Config.McpResourceUrl do
  @moduledoc "Validates the configured canonical HTTPS MCP resource URL without rewriting it."

  @doc "Returns the exact configured URL, raising without exposing invalid values."
  @spec validate!(String.t()) :: String.t()
  def validate!(value) when is_binary(value) do
    with false <- Regex.match?(~r/[\s\p{Cc}]/u, value),
         {:ok, %URI{scheme: "https", host: host, port: port, userinfo: nil, query: nil, fragment: nil}} <-
           URI.new(value),
         true <- is_binary(host) and host != "" and is_integer(port) and port in 1..65_535 do
      value
    else
      _ ->
        raise ArgumentError,
              "Invalid MCP_RESOURCE_URL: expected an HTTPS URL with a host, a valid port, " <>
                "and no userinfo, query, fragment, whitespace or control characters"
    end
  end
end
