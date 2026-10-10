defmodule FirmowidMcp.Ksef.Views.Connection do
  @moduledoc "Embedded KSeF setup with scoped admin actions and model-visible connection status."
  use FirmowidMcp, :live_view

  import Phoenix.Component

  alias FirmowidMcp.Ksef.Connection
  alias FirmowidMcp.LiveSession
  alias FirmowidMcp.Widgets
  alias FirmowidUI.Components.KsefConnection
  alias FirmowidUI.Ksef.Connection, as: ConnectionState

  @impl true
  def mount(_params, session, socket) do
    socket = assign(socket, connection: nil, connection_initialized?: false, error: nil)

    LiveSession.mount(session, socket, Connection,
      on_mount: &load_status/1,
      on_expire: &clear/1
    )
  end

  @impl true
  def handle_event(event, params, socket) do
    LiveSession.handle_event(event, params, socket, fn
      "save_ksef_token", _params, socket ->
        {:noreply, socket}

      "select_ksef_auth_method", %{"method" => "token"}, socket ->
        {:noreply, socket}

      event, params, socket ->
        if socket.assigns.connection_initialized? and socket.assigns.scope.actor.role == :admin do
          {:noreply, updated} =
            ConnectionState.handle_event(event, params, socket, socket.assigns.scope)

          {:noreply, load_status(updated)}
        else
          {:noreply, load_status(socket)}
        end
    end)
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "credential:" <> _} = message, socket) do
    LiveSession.handle_info(message, socket, fn message, socket ->
      if socket.assigns.connection_initialized? and socket.assigns.scope.actor.role == :admin do
        {:noreply, updated} = ConnectionState.handle_info(message, socket, socket.assigns.scope)
        {:noreply, load_status(updated)}
      else
        {:noreply, load_status(socket)}
      end
    end)
  end

  defp load_status(socket) do
    case Widgets.execute(Connection, %{}, socket.assigns.scope) do
      {:ok, result, connection} ->
        socket =
          cond do
            not connection.can_connect ->
              clear(socket)

            socket.assigns.connection_initialized? ->
              socket

            true ->
              socket
              |> ConnectionState.init(socket.assigns.scope)
              |> assign(:connection_initialized?, true)
          end

        socket
        |> assign(connection: connection, error: nil)
        |> push_event("mcp:context", %{structuredContent: result, arguments: %{}})

      {:error, _reason} ->
        socket
        |> clear()
        |> assign(:error, gettext("Unable to load the KSeF connection status. Try again."))
    end
  end

  defp clear(socket) do
    socket =
      if socket.assigns.connection_initialized?, do: ConnectionState.clear(socket), else: socket

    assign(socket, connection: nil, connection_initialized?: false, error: nil)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section
      id="mcp-ksef-connection"
      phx-hook="McpContext"
      class="grid gap-4 p-4"
      phx-disconnected={JS.set_attribute({"inert", ""})}
      phx-connected={JS.remove_attribute("inert")}
    >
      <LiveToast.toast_group
        :if={@status == :ready}
        flash={@flash}
        connected={@connected?}
        toasts_sync={[]}
        kinds={[:info, :error, :success]}
        connection_notifications={false}
      />
      <h1 class="text-lg font-semibold">{gettext("KSeF integration")}</h1>
      <p :if={@status == :expired} role="status">
        {gettext("KSeF setup is unavailable.")}
      </p>
      <p :if={@error} role="alert">{@error}</p>
      <%= if @status == :ready and @connection do %>
        <%= if @connection.can_connect do %>
          <KsefConnection.ksef_connection
            ksef_credential={@ksef_credential}
            ksef_auth_method={@ksef_auth_method}
            ksef_auth_status={@ksef_auth_status}
            ksef_failure={@ksef_failure}
            uploads={@uploads}
            download_hook="McpKsefDownload"
            allow_token?={false}
          />
        <% else %>
          <p>{gettext("Only an organization administrator can connect KSeF.")}</p>
        <% end %>
      <% end %>
    </section>
    """
  end
end
