defmodule FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents do
  @moduledoc "Extracts the authenticated LiveView context for allowlisted server-side business events."

  alias Firmowid.Analytics
  alias Phoenix.LiveView.Socket

  @doc "Captures an event for a socket with a user and organization; returns the socket unchanged."
  @spec capture(Socket.t(), atom()) :: Socket.t()
  @spec capture(Socket.t(), atom(), map()) :: Socket.t()
  def capture(socket, event, properties \\ %{})

  def capture(socket, event, properties) when is_struct(socket, Socket) and is_atom(event) and is_map(properties) do
    with %{id: user_id} when not is_nil(user_id) <- socket.assigns[:current_user],
         %{id: organization_id} when not is_nil(organization_id) <- socket.assigns[:current_org] do
      Analytics.capture_business_event(event, user_id, organization_id, properties)
    end

    socket
  rescue
    _ -> socket
  end

  def capture(socket, _event, _properties), do: socket
end
