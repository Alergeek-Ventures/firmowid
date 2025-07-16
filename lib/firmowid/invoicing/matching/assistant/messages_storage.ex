defmodule Firmowid.Invoicing.Matching.Assistant.MessagesStorage do
  use Agent

  alias Firmowid.Invoicing.Matching.Assistant.Message

  @moduledoc """
  In-memory storage for assistant conversations, keyed by conversation_id.
  Stores lists of Message structs per conversation, and conversation metadata (e.g., invoice).
  Not for production use.
  Now supports PubSub for real-time updates and streaming tokens.
  Only stores and returns Elixir structs (no LLM-specific formats).
  """

  @pubsub Firmowid.PubSub
  @pubsub_prefix "assistant:conversation"

  @doc """
  Returns the PubSub topic for a given conversation_id.
  """
  def topic(conversation_id), do: "#{@pubsub_prefix}:#{conversation_id}"

  @doc """
  Broadcasts a payload to the conversation's topic.
  """
  def broadcast(conversation_id, payload) do
    Phoenix.PubSub.broadcast(@pubsub, topic(conversation_id), payload)
  end

  @doc """
  Subscribes the current process to the conversation's topic.
  """
  def subscribe(conversation_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(conversation_id))
  end

  @doc """
  Unsubscribes the current process from the conversation's topic.
  """
  def unsubscribe(conversation_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(conversation_id))
  end

  def start_link(_) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Appends a Message struct to the conversation with the given ID and broadcasts it.
  """
  def append(conversation_id, %Message{} = message) do
    Agent.update(__MODULE__, fn state ->
      Map.update(state, conversation_id, %{messages: [message], invoice: nil}, fn conv ->
        %{conv | messages: [message | conv.messages || []]}
      end)
    end)

    broadcast(conversation_id, {:new_message, message})
  end

  @doc """
  Broadcasts a streamed token (partial content) for a conversation.
  """
  def broadcast_token(conversation_id, token) do
    broadcast(conversation_id, {:stream_token, token})
  end

  @doc """
  Returns the list of Message structs for the given conversation_id, oldest first.
  """
  def get(conversation_id) do
    Agent.get(__MODULE__, fn state ->
      state
      |> Map.get(conversation_id, %{messages: []})
      |> Map.get(:messages, [])
      |> Enum.reverse()
    end)
  end

  @doc """
  Sets the invoice for the given conversation_id.
  """
  def set_invoice(conversation_id, invoice) do
    Agent.update(__MODULE__, fn state ->
      Map.update(state, conversation_id, %{messages: [], invoice: invoice}, fn conv ->
        %{conv | invoice: invoice}
      end)
    end)
  end

  @doc """
  Gets the invoice for the given conversation_id. Returns nil if not set.
  """
  def get_invoice(conversation_id) do
    Agent.get(__MODULE__, fn state ->
      state
      |> Map.get(conversation_id, %{invoice: nil})
      |> Map.get(:invoice)
    end)
  end

  def delete(conversation_id) do
    Agent.update(__MODULE__, fn state ->
      Map.delete(state, conversation_id)
    end)
  end
end
