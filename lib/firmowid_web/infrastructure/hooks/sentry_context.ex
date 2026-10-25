defmodule FirmowidWeb.Infrastructure.Hooks.SentryContext do
  @moduledoc "Adds privacy-safe LiveView callback and message metadata to crash reports."

  alias Ash.Notifier.Notification
  alias Phoenix.LiveView
  alias Phoenix.LiveView.Socket
  alias Phoenix.Socket.Broadcast

  @message_keys [
    :message_kind,
    :message_tag,
    :message_arity,
    :resource,
    :action,
    :action_type,
    :processing_target
  ]

  @doc "Attaches diagnostic hooks without intercepting callbacks or handling their errors."
  @spec on_mount(:default, map() | :not_mounted_at_router, map(), Socket.t()) ::
          {:cont, Socket.t()}
  def on_mount(:default, params, _session, socket) do
    put_metadata(socket, "mount")

    socket =
      socket
      |> LiveView.attach_hook(__MODULE__, :handle_info, &handle_info/2)
      |> LiveView.attach_hook(__MODULE__, :handle_event, fn _event, _params, socket ->
        put_metadata(socket, "handle_event")
        {:cont, socket}
      end)
      |> attach_params_hook(params)
      |> LiveView.attach_hook(__MODULE__, :handle_async, fn _name, _result, socket ->
        put_metadata(socket, "handle_async")
        {:cont, socket}
      end)

    {:cont, socket}
  end

  # A child's static socket inherits the parent's router, but has no URL callbacks.
  defp attach_params_hook(socket, :not_mounted_at_router), do: socket

  defp attach_params_hook(socket, _params) do
    LiveView.attach_hook(socket, __MODULE__, :handle_params, fn _params, _uri, socket ->
      put_metadata(socket, "handle_params")
      {:cont, socket}
    end)
  end

  defp handle_info(message, socket) do
    put_metadata(socket, "handle_info", message_metadata(message))
    {:cont, socket}
  end

  defp put_metadata(socket, callback, message_metadata \\ []) do
    # Replace, rather than accumulate, message fields so the next callback cannot
    # accidentally inherit the previous message's resource or action.
    metadata =
      Keyword.merge(Enum.map(@message_keys, &{&1, nil}),
        view: inspect(socket.view),
        live_action: atom_name(socket.assigns[:live_action]),
        callback: callback,
        user_id: socket.assigns[:current_user] && socket.assigns.current_user.id,
        organization_id: socket.assigns[:current_org] && socket.assigns.current_org.id
      )

    Logger.metadata(Keyword.merge(metadata, message_metadata))
  end

  defp message_metadata(%Broadcast{payload: %Notification{} = notification}) do
    [
      message_kind: inspect(Broadcast),
      resource: atom_name(notification.resource),
      action: atom_name(notification.action.name),
      action_type: atom_name(notification.action.type),
      processing_target: processing_target(notification.data)
    ]
  end

  defp message_metadata(%module{}), do: [message_kind: inspect(module)]

  defp message_metadata(message) when is_tuple(message) do
    tag = if tuple_size(message) > 0, do: atom_name(elem(message, 0))
    [message_kind: "tuple", message_tag: tag, message_arity: tuple_size(message)]
  end

  defp message_metadata(message) when is_atom(message), do: [message_kind: "atom", message_tag: atom_name(message)]

  defp message_metadata(message) when is_map(message), do: [message_kind: "map"]
  defp message_metadata(message) when is_list(message), do: [message_kind: "list"]
  defp message_metadata(message) when is_binary(message), do: [message_kind: "binary"]
  defp message_metadata(_message), do: [message_kind: "other"]

  defp processing_target(%{processing_target: target}) when target in [:none, :cost_invoice, :employment_contract],
    do: Atom.to_string(target)

  defp processing_target(_data), do: nil

  defp atom_name(nil), do: nil
  defp atom_name(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_name(_value), do: nil
end
