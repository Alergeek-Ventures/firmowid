defmodule Firmowid.Ash.Finances.GoCardless.TokenManager do
  @moduledoc """
  Manages GoCardless Bank Account Data API access tokens.

  Obtains a JWT token pair (access + refresh) on startup via `/token/new/`,
  then periodically refreshes the short-lived access token (~24h) using the
  long-lived refresh token (~30d) via `/token/refresh/`. Falls back to full
  re-authentication when the refresh token itself expires.

  Exposes `refresh_now/0` for callers (e.g. Oban workers) to reactively
  obtain a fresh access token when a 401 is encountered.
  """

  use GenServer

  require Logger

  @base_url "https://bankaccountdata.gocardless.com/api/v2"

  # Refresh the access token this many seconds before it expires
  @refresh_buffer 60

  # When a token fetch fails, retry after this many seconds
  @retry_interval_seconds 30

  # Give up retrying after this many consecutive failures
  @max_fetch_failures 5

  @doc """
  Starts the TokenManager GenServer, linked to the calling process.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Returns the current access token, fetching one on-demand if none is cached.
  """
  @spec get_access_token() :: String.t() | nil
  def get_access_token do
    GenServer.call(__MODULE__, :get_access_token)
  end

  @doc """
  Forces an immediate token refresh and returns the new access token.

  Tries the lightweight `/token/refresh/` first; falls back to full
  `/token/new/` if the refresh token is expired. Returns `nil` if
  both attempts fail.
  """
  @spec refresh_now() :: String.t() | nil
  def refresh_now do
    GenServer.call(__MODULE__, :refresh_now)
  end

  # --- Server callbacks ---

  @impl true
  def init(_state) do
    state = %{
      access_token: nil,
      access_expires: nil,
      refresh_token: nil,
      refresh_expires: nil,
      fetch_failures: 0
    }

    schedule_token_refresh(nil)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_access_token, _from, state) do
    if is_nil(state.access_token) do
      case do_full_token_refresh(state) do
        {:ok, new_state} ->
          schedule_token_refresh(new_state.access_expires)
          {:reply, new_state.access_token, new_state}

        {:error, _reason, new_state} ->
          {:reply, nil, new_state}
      end
    else
      {:reply, state.access_token, state}
    end
  end

  @impl true
  def handle_call(:refresh_now, _from, state) do
    case do_full_token_refresh(state) do
      {:ok, new_state} ->
        schedule_token_refresh(new_state.access_expires)
        {:reply, new_state.access_token, new_state}

      {:error, _reason, new_state} ->
        {:reply, nil, new_state}
    end
  end

  @impl true
  def handle_info(:refresh_token, state) do
    case do_full_token_refresh(state) do
      {:ok, new_state} ->
        schedule_token_refresh(new_state.access_expires)
        {:noreply, new_state}

      {:error, _reason, new_state} ->
        if new_state.fetch_failures < @max_fetch_failures do
          Logger.warning(
            "Token refresh failed (attempt #{new_state.fetch_failures}/#{@max_fetch_failures}), " <>
              "retrying in #{@retry_interval_seconds}s"
          )

          schedule_token_refresh_after(@retry_interval_seconds)
          {:noreply, new_state}
        else
          Logger.error(
            "Token refresh failed after #{@max_fetch_failures} consecutive attempts; " <>
              "giving up until next scheduled refresh or explicit refresh_now call"
          )

          # Schedule a long retry (1 hour) as a last resort
          schedule_token_refresh_after(3600)
          {:noreply, new_state}
        end
    end
  end

  # --- Token refresh logic ---

  # Tries refresh endpoint first, falls back to full re-auth.
  # Returns {:ok, new_state} or {:error, reason, state_with_incremented_failures}.
  defp do_full_token_refresh(state) do
    if state.refresh_token do
      case refresh_access_token(state.refresh_token) do
        {:ok, tokens} ->
          new_state = %{
            state
            | access_token: tokens.access_token,
              access_expires: tokens.access_expires,
              fetch_failures: 0
          }

          Logger.debug("Access token refreshed via /token/refresh/")
          {:ok, new_state}

        {:error, :invalid_refresh_token} ->
          Logger.info("Refresh token expired or invalid, falling back to /token/new/")
          fetch_new_token_pair(state)

        {:error, reason} ->
          Logger.warning("Token refresh failed: #{inspect(reason)}, falling back to /token/new/")
          fetch_new_token_pair(state)
      end
    else
      fetch_new_token_pair(state)
    end
  end

  # POST /api/v2/token/refresh/ — lightweight, only returns access + access_expires.
  # The refresh token is reusable and not rotated.
  @spec refresh_access_token(String.t()) ::
          {:ok, %{access_token: String.t(), access_expires: integer()}}
          | {:error, :invalid_refresh_token | term()}
  defp refresh_access_token(refresh_token) do
    case Req.post("#{@base_url}/token/refresh/", json: %{refresh: refresh_token}) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{access_token: body["access"], access_expires: body["access_expires"]}}

      {:ok, %{status: 401}} ->
        {:error, :invalid_refresh_token}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Unexpected response from /token/refresh/: #{status} #{inspect(body)}")
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.warning("Network error calling /token/refresh/: #{inspect(reason)}")
        {:error, {:network_error, reason}}
    end
  end

  # POST /api/v2/token/new/ — full re-authentication with secret_id/secret_key.
  # Returns all four fields: access, access_expires, refresh, refresh_expires.
  defp fetch_new_token_pair(state) do
    case Req.post("#{@base_url}/token/new/",
           json: %{
             secret_id: Application.fetch_env!(:firmowid, :go_limitless_secret_id),
             secret_key: Application.fetch_env!(:firmowid, :go_limitless_secret_key)
           }
         ) do
      {:ok, %{status: 200, body: body}} ->
        new_state = %{
          access_token: body["access"],
          access_expires: body["access_expires"],
          refresh_token: body["refresh"],
          refresh_expires: body["refresh_expires"],
          fetch_failures: 0
        }

        Logger.debug("New token pair obtained via /token/new/")
        {:ok, new_state}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to obtain token pair from /token/new/: #{status} #{inspect(body)}")

        {:error, {:unexpected_status, status}, %{state | fetch_failures: state.fetch_failures + 1}}

      {:error, reason} ->
        Logger.error("Network error calling /token/new/: #{inspect(reason)}")
        {:error, {:network_error, reason}, %{state | fetch_failures: state.fetch_failures + 1}}
    end
  end

  # --- Scheduling ---

  defp schedule_token_refresh(nil) do
    # No access_expires known — fetch immediately
    Process.send_after(self(), :refresh_token, 1)
  end

  defp schedule_token_refresh(access_expires) when is_integer(access_expires) do
    interval_ms = max((access_expires - @refresh_buffer) * 1000, 1)
    Process.send_after(self(), :refresh_token, interval_ms)
  end

  defp schedule_token_refresh_after(seconds) do
    Process.send_after(self(), :refresh_token, seconds * 1000)
  end
end
