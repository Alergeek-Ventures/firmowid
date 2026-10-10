defmodule Firmowid.Oauth2.CimdMetadataFetcher do
  @moduledoc """
  Negotiates public-client CIMD authentication using the official fetcher.

  The server implements only `none`. A plural capability declaration takes
  precedence over the legacy singular preference, but must explicitly include
  `none`. Without the plural field, the singular field must explicitly be
  `none`. Unlike the native omission default, missing declarations fail closed
  for CIMD only; Dynamic Client Registration is unaffected.

  Fetch options pass unchanged to `ReqFetcher`, retaining its URL, DNS/IP,
  pinned TLS, redirect, response-size and timeout restrictions. Native document
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
    case ReqFetcher.fetch(url, opts) do
      {:ok, %{document: document} = result} ->
        with {:ok, negotiated} <- negotiate(document),
             :ok <- validate_document(negotiated, url) do
          {:ok, %{result | document: negotiated}}
        end

      {:error, _reason} ->
        {:error, :metadata_fetch_failed}
    end
  end

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
