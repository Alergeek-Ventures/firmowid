defmodule FirmowidMcp.LiveSession do
  @moduledoc "Shared widget session lifetime and validated Ash scope for embedded LiveViews."

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView

  alias FirmowidMcp.Session
  alias Phoenix.LiveView.Socket

  @doc "Establishes the widget scope and runs its initial load within the session lifetime."
  @spec mount(map(), Socket.t(), module(), keyword()) :: {:ok, Socket.t()}
  def mount(session, socket, widget, callbacks) do
    # Also before authorization, so an expired view uses the widget's language.
    # Tool results signed before the widget language existed have no "mcp_locale".
    if locale = session["mcp_locale"] do
      Gettext.put_locale(Firmowid.Gettext, locale)
      {:ok, _locale} = Firmowid.Cldr.put_locale(locale)
    end

    socket =
      socket
      |> assign(connected?: connected?(socket), status: :ready, scope: nil)
      |> put_private(:mcp_session, %{
        token: session["mcp_session"],
        resource_uri: widget.resource_uri(),
        on_expire: Keyword.fetch!(callbacks, :on_expire)
      })
      |> attach_hook(:mcp_session, :handle_info, &handle_info/2)

    case authorize(socket) do
      {:ok, capability} ->
        if connected?(socket) do
          Process.send_after(
            self(),
            :mcp_session_expired,
            max(capability.expires_at - System.system_time(:second), 0) * 1_000
          )
        end

        # Only the signed tool input may become the invoice being confirmed.
        # Socket connect parameters are browser-controlled, including on reconnect.
        socket =
          assign(socket,
            scope: capability.scope,
            arguments: capability.query,
            confirmation_id: capability.confirmation_id
          )

        loaded = Keyword.fetch!(callbacks, :on_mount).(socket)

        {:ok, within_lifetime(socket, loaded, capability.expires_at)}

      {:error, _reason} ->
        {:ok, expire(socket)}
    end
  end

  @doc "Refreshes the Ash scope before a widget interaction and discards results after expiry."
  @spec handle_event(String.t(), map(), Socket.t(), function()) ::
          {:noreply, Socket.t()} | {:reply, map(), Socket.t()}
  def handle_event(event, params, socket, handler) do
    within_session(socket, &handler.(event, params, &1))
  end

  @doc "Refreshes the Ash scope before asynchronous widget updates and rejects expired results."
  @spec handle_info(term(), Socket.t(), function()) :: {:noreply, Socket.t()}
  def handle_info(message, socket, handler) do
    within_session(socket, &handler.(message, &1))
  end

  defp within_session(socket, handler) do
    case authorize(socket) do
      {:ok, capability} ->
        socket = assign(socket, :scope, capability.scope)

        case handler.(socket) do
          {:noreply, updated} ->
            {:noreply, within_lifetime(socket, updated, capability.expires_at)}

          {:reply, reply, updated} ->
            if expired?(capability.expires_at),
              do: {:noreply, expire(socket)},
              else: {:reply, reply, updated}
        end

      {:error, _reason} ->
        {:noreply, expire(socket)}
    end
  end

  defp handle_info(:mcp_session_expired, socket), do: {:halt, expire(socket)}
  defp handle_info(_message, socket), do: {:cont, socket}

  defp authorize(%{private: %{mcp_session: %{token: token, resource_uri: uri}}}), do: Session.authorize(token, uri)

  defp within_lifetime(previous, updated, expires_at) do
    # Discard the whole late result, including queued model-context events.
    if expired?(expires_at), do: expire(previous), else: updated
  end

  defp expired?(expires_at), do: System.system_time(:second) >= expires_at

  defp expire(socket) do
    session = socket.private.mcp_session

    socket
    |> session.on_expire.()
    |> put_private(:mcp_session, %{session | token: nil})
    |> assign(scope: nil, status: :expired)
    |> push_event("mcp:expired", %{})
  end
end
