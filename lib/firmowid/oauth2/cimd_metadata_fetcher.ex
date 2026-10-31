defmodule Firmowid.Oauth2.CimdMetadataFetcher do
  @moduledoc """
  Negotiates public-client CIMD authentication using the official metadata policy.

  The server implements only `none`. A plural capability declaration takes
  precedence over the legacy singular preference, but must explicitly include
  `none`. Without the plural field, the singular field must explicitly be
  `none`. Unlike the native omission default, missing declarations fail closed
  for CIMD only; Dynamic Client Registration is unaffected.

  Uses the official URL and IP policy with a single, unpooled Mint connection,
  retaining pinned TLS, redirect, response-size and timeout restrictions without
  creating permanent Finch pool names from untrusted hostnames. Native document
  validation still runs after negotiation and before returning a cacheable result.
  """

  @behaviour AshAuthentication.Oauth2Server.CIMD.Fetcher

  alias AshAuthentication.Oauth2Server.CIMD
  alias AshAuthentication.Oauth2Server.CIMD.Fetcher
  alias AshAuthentication.Oauth2Server.CIMD.ReqFetcher

  @implemented_methods ["none"]
  @string_fields ~w(client_id client_name token_endpoint_auth_method)
  @string_list_fields ~w(redirect_uris grant_types response_types token_endpoint_auth_methods_supported)

  @type negotiation_error ::
          :invalid_metadata_document
          | :invalid_auth_methods
          | :missing_auth_method
          | :unsupported_auth_method

  @doc """
  Fetches, negotiates and natively validates CIMD metadata, preserving cache TTL.

  Failures expose only finite atoms, never fetched metadata or transport details.
  """
  @impl true
  @spec fetch(String.t(), keyword()) ::
          {:ok, Fetcher.result()} | {:error, negotiation_error() | :metadata_fetch_failed}
  def fetch(url, opts \\ []) do
    case fetch_document(url, opts) do
      {:ok, %{document: document} = result} ->
        with {:ok, negotiated} <- negotiate(document),
             :ok <- validate_document(negotiated, url) do
          {:ok, %{result | document: negotiated}}
        end

      _transport_failure ->
        {:error, :metadata_fetch_failed}
    end
  end

  defp fetch_document(url, opts) do
    connect_timeout = Keyword.get(opts, :connect_timeout, 5_000)
    receive_timeout = Keyword.get(opts, :receive_timeout, 5_000)

    with {:ok, uri} <- ReqFetcher.validate_url(url, opts),
         {:ok, ip} <- resolve_and_validate(uri.host, opts),
         {:ok, conn} <-
           Mint.HTTP.connect(:https, ip, uri.port,
             hostname: uri.host,
             protocols: [:http1],
             mode: :passive,
             transport_opts: [
               timeout: connect_timeout,
               inet6: tuple_size(ip) == 8,
               inet4: tuple_size(ip) == 4
             ]
           ) do
      # HTTP/1 keeps one socket. Close it on every return without retaining a pool.
      try do
        path = uri.path <> if(uri.query, do: "?" <> uri.query, else: "")
        deadline = System.monotonic_time(:millisecond) + receive_timeout
        max_body = Keyword.get(opts, :max_body_bytes, 5_120)

        with {:ok, conn, ref} <-
               Mint.HTTP.request(conn, "GET", path, [{"accept", "application/json"}], nil) do
          receive_document(conn, ref, deadline, max_body, %{status: nil, headers: [], body: ""})
        end
      after
        Mint.HTTP.close(conn)
      end
    end
  end

  # ReqFetcher keeps its resolver private. Preserve its all-addresses check and
  # IPv4 preference, then connect only to the selected, already validated tuple.
  defp resolve_and_validate(host, opts) do
    host = String.to_charlist(host)

    ips =
      case :inet.parse_address(host) do
        {:ok, ip} ->
          [ip]

        {:error, _} ->
          Enum.uniq(resolve_addresses(host, :inet) ++ resolve_addresses(host, :inet6))
      end

    cond do
      ips == [] -> {:error, :metadata_fetch_failed}
      Keyword.get(opts, :allow_non_public_ips?, false) -> {:ok, hd(ips)}
      Enum.all?(ips, &ReqFetcher.public_ip?/1) -> {:ok, hd(ips)}
      true -> {:error, :metadata_fetch_failed}
    end
  end

  defp resolve_addresses(host, family) do
    case :inet.getaddrs(host, family) do
      {:ok, ips} -> ips
      {:error, _} -> []
    end
  end

  defp receive_document(conn, ref, deadline, max_body, response) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      with {:ok, conn, events} <- Mint.HTTP.recv(conn, 0, remaining) do
        case collect_response(events, ref, max_body, response) do
          {:cont, response} -> receive_document(conn, ref, deadline, max_body, response)
          result -> result
        end
      end
    else
      {:error, :metadata_fetch_failed}
    end
  end

  defp collect_response([], _ref, _max_body, response), do: {:cont, response}

  defp collect_response([{:status, ref, status} | rest], ref, max_body, response) do
    collect_response(rest, ref, max_body, %{response | status: status})
  end

  defp collect_response([{:headers, ref, headers} | rest], ref, max_body, response) do
    collect_response(rest, ref, max_body, %{response | headers: headers})
  end

  defp collect_response([{:data, ref, chunk} | rest], ref, max_body, response) do
    if byte_size(response.body) + byte_size(chunk) <= max_body do
      collect_response(rest, ref, max_body, %{response | body: response.body <> chunk})
    else
      {:error, :metadata_fetch_failed}
    end
  end

  defp collect_response([{:done, ref} | _rest], ref, _max_body, response) do
    with 200 <- response.status,
         {:ok, document} when is_map(document) <- Jason.decode(response.body) do
      {:ok, %{document: document, cache_ttl: cache_ttl(response.headers)}}
    else
      _ -> {:error, :metadata_fetch_failed}
    end
  end

  # Keep ReqFetcher's private Cache-Control parser semantics, including the
  # first header value, permissive integer suffix and no-cache precedence.
  defp cache_ttl(headers) do
    case Req.Response.get_header(Req.Response.new(headers: headers), "cache-control") do
      [value | _] ->
        directives =
          value
          |> String.downcase()
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)

        cond do
          Enum.any?(directives, &(&1 in ["no-store", "no-cache", "private"])) -> 0
          max_age = Enum.find_value(directives, &parse_max_age/1) -> max_age
          true -> nil
        end

      [] ->
        nil
    end
  end

  defp parse_max_age("max-age=" <> value) do
    case Integer.parse(value) do
      {seconds, _} when seconds >= 0 -> seconds
      _ -> nil
    end
  end

  defp parse_max_age(_), do: nil

  @doc """
  Purely negotiates an explicitly declared method with the server's capabilities.

  A plural declaration must be a nonempty list of unique, nonempty strings.
  Unsupported capabilities are preserved, not removed. If `none` is declared,
  it is projected into the singular field for the official singular-only
  validator, even when the legacy preference is an unsupported JWT method.
  All other metadata, including the original plural declaration, is preserved.
  This function does not replace native identity or redirect URI validation.
  """
  @spec negotiate(term()) :: {:ok, map()} | {:error, negotiation_error()}
  def negotiate(document) when is_map(document) do
    if valid_metadata_shapes?(document) do
      case Map.fetch(document, "token_endpoint_auth_methods_supported") do
        {:ok, methods} -> negotiate_methods(document, methods)
        :error -> negotiate_legacy_method(document)
      end
    else
      {:error, :invalid_metadata_document}
    end
  end

  def negotiate(_document), do: {:error, :invalid_metadata_document}

  defp valid_metadata_shapes?(document) do
    strings_valid? =
      document
      |> Map.take(@string_fields)
      |> Enum.all?(fn {_field, value} -> is_binary(value) end)

    lists_valid? =
      document
      |> Map.take(@string_list_fields)
      |> Enum.all?(fn {_field, value} ->
        is_list(value) and Enum.all?(value, &is_binary/1)
      end)

    # Version 0.3.1 treats malformed optional arrays as absent during validation,
    # but consumes their original values when registering the client.
    strings_valid? and lists_valid?
  end

  defp negotiate_methods(document, methods) when is_list(methods) and methods != [] do
    cond do
      not Enum.all?(methods, &(is_binary(&1) and &1 != "")) ->
        {:error, :invalid_auth_methods}

      length(Enum.uniq(methods)) != length(methods) ->
        {:error, :invalid_auth_methods}

      Enum.any?(@implemented_methods, &(&1 in methods)) ->
        {:ok, Map.put(document, "token_endpoint_auth_method", "none")}

      true ->
        {:error, :unsupported_auth_method}
    end
  end

  defp negotiate_methods(_document, _methods), do: {:error, :invalid_auth_methods}

  defp negotiate_legacy_method(document) do
    case Map.fetch(document, "token_endpoint_auth_method") do
      {:ok, "none"} -> {:ok, document}
      {:ok, method} when is_binary(method) and method != "" -> {:error, :unsupported_auth_method}
      {:ok, _method} -> {:error, :invalid_auth_methods}
      :error -> {:error, :missing_auth_method}
    end
  end

  defp validate_document(document, url) do
    case CIMD.validate_document(document, url) do
      :ok -> :ok
      {:error, _description} -> {:error, :invalid_metadata_document}
    end
  end
end
