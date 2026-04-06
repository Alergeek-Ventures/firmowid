defmodule Firmowid.Ash.Core.Secrets do
  @moduledoc """
  Secret resolver for `ash_authentication` strategies.

  Reads Google OAuth credentials and token signing secret from application
  config (populated by runtime.exs from environment variables).
  """
  use AshAuthentication.Secret

  alias Firmowid.Ash.Core.User
  alias FirmowidWeb.Core.Endpoint

  @impl true
  def secret_for([:authentication, :tokens, :signing_secret], User, _opts, _context) do
    case Application.fetch_env(:firmowid, Endpoint) do
      {:ok, config} -> {:ok, Keyword.fetch!(config, :secret_key_base)}
      :error -> :error
    end
  end

  def secret_for([:authentication, :strategies, :google, :client_id], User, _opts, _context) do
    fetch_env(:google_client_id)
  end

  def secret_for([:authentication, :strategies, :google, :client_secret], User, _opts, _context) do
    fetch_env(:google_client_secret)
  end

  def secret_for([:authentication, :strategies, :google, :redirect_uri], User, _opts, _context) do
    case Application.fetch_env(:firmowid, Endpoint) do
      {:ok, config} ->
        url = Keyword.get(config, :url, [])
        host = Keyword.get(url, :host, "localhost")
        port = Keyword.get(url, :port, 4000)
        scheme = Keyword.get(url, :scheme, "http")
        {:ok, "#{scheme}://#{host}:#{port}/auth/user/google/callback"}

      :error ->
        :error
    end
  end

  defp fetch_env(key) do
    case Application.fetch_env(:firmowid, key) do
      {:ok, nil} -> :error
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  end
end
