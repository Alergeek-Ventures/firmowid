defmodule Mix.Tasks.Chatgpt.Tunnel.Readiness do
  @moduledoc """
  Checks the existing worktree locally and at its advertised OAuth origin before tunnel launch.

  Requests are bounded by timeouts and never follow redirects. This module
  does not start Firmowid, read credentials or launch any external process.
  """

  @doc "Returns the verified worktree origin without exposing response bodies or transport errors."
  @spec check(1..65_535) ::
          {:ok, String.t()}
          | {:error, :http_client_unavailable | :not_ready | {:worktree_url_unreachable, String.t()}}
  def check(port) when is_integer(port) and port in 1..65_535 do
    with {:ok, _apps} <- Application.ensure_all_started(:inets),
         {:ok, _apps} <- Application.ensure_all_started(:ssl) do
      origin = "http://localhost:#{port}"

      case check_endpoints(origin) do
        {:ok, issuer} -> check_worktree_url(origin, issuer)
        {:error, _reason} = error -> error
      end
    else
      {:error, _reason} -> {:error, :http_client_unavailable}
    end
  end

  defp check_worktree_url(origin, origin), do: {:ok, origin}

  defp check_worktree_url(_origin, issuer) do
    case check_endpoints(issuer) do
      {:ok, ^issuer} -> {:ok, issuer}
      _ -> {:error, {:worktree_url_unreachable, issuer}}
    end
  end

  defp check_endpoints(origin) do
    with {:ok, %{"status" => "healthy"}} <- metadata(origin, "/health"),
         {:ok, issuer} <- check_authorization_server(origin),
         :ok <- check_resource(origin, issuer),
         :ok <- check_challenge(origin) do
      {:ok, issuer}
    else
      _ -> {:error, :not_ready}
    end
  end

  defp check_resource(origin, issuer) do
    with {:ok,
          %{
            "resource" => resource,
            "authorization_servers" => servers,
            "scopes_supported" => scopes
          }} <-
           metadata(origin, "/.well-known/oauth-protected-resource"),
         true <- is_binary(resource) and String.starts_with?(resource, "https://"),
         true <- is_list(servers) and issuer in servers,
         true <- is_list(scopes) and "mcp" in scopes do
      :ok
    else
      _ -> {:error, :not_ready}
    end
  end

  defp check_authorization_server(origin) do
    # PHX_URL can advertise a tailnet origin rather than the local listener.
    with {:ok, %{"issuer" => issuer, "authorization_endpoint" => authorize, "token_endpoint" => token}} <-
           metadata(origin, "/.well-known/oauth-authorization-server"),
         true <- is_binary(issuer),
         {:ok,
          %URI{
            scheme: scheme,
            host: host,
            port: port,
            userinfo: nil,
            path: path,
            query: nil,
            fragment: nil
          }} <-
           URI.new(issuer),
         true <-
           scheme in ["http", "https"] and is_binary(host) and host != "" and port in 1..65_535,
         true <- path in [nil, ""],
         true <- authorize == issuer <> "/oauth/authorize" and token == issuer <> "/oauth/token" do
      {:ok, issuer}
    else
      _ -> {:error, :not_ready}
    end
  end

  defp check_challenge(origin) do
    with {:ok, {{_version, 401, _reason}, headers, _body}} <- request(origin <> "/mcp"),
         {_name, challenge} <- List.keyfind(headers, ~c"www-authenticate", 0) do
      challenge = List.to_string(challenge)

      if String.starts_with?(challenge, "Bearer ") and
           String.contains?(challenge, "resource_metadata="),
         do: :ok,
         else: {:error, :not_ready}
    else
      _ -> {:error, :not_ready}
    end
  end

  defp metadata(origin, path) do
    case request(origin <> path) do
      {:ok, {{_version, 200, _reason}, _headers, body}} -> Jason.decode(body)
      _ -> {:error, :not_ready}
    end
  end

  defp request(url) do
    :httpc.request(
      :get,
      {String.to_charlist(url), []},
      [timeout: 3_000, connect_timeout: 1_000, autoredirect: false],
      body_format: :binary
    )
  end
end
