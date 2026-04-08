defmodule Firmowid.Ash.Invoicing.Matching.Assistant.MessagesStorage do
  @moduledoc """
  In-memory storage for assistant conversations, keyed by conversation_id.

  Uses an Agent process for simplicity. Conversations are ephemeral and lost
  on restart, which is acceptable for this assistant feature. Supports PubSub
  for real-time updates and streaming tokens. Only stores and returns Elixir
  structs (no LLM-specific formats).

  TODO: Replace Agent-based in-memory storage with a persistent backend
  (e.g. ETS, database, or a dedicated GenServer with supervision) for
  production resilience.
  """

  use Agent

  alias Firmowid.Ash.Invoicing.Matching.Assistant.Message

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

  def get_latest(conversation_id) do
    Agent.get(__MODULE__, fn state ->
      state
      |> Map.get(conversation_id, %{messages: []})
      |> Map.get(:messages, [])
      |> List.first()
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

  @doc """
  Sets the scope for the given conversation_id.
  """
  def set_scope(conversation_id, scope) do
    Agent.update(__MODULE__, fn state ->
      Map.update(state, conversation_id, %{messages: [], invoice: nil, scope: scope}, fn conv ->
        Map.put(conv, :scope, scope)
      end)
    end)
  end

  @doc """
  Gets the scope for the given conversation_id. Returns nil if not set.
  """
  def get_scope(conversation_id) do
    Agent.get(__MODULE__, fn state ->
      state
      |> Map.get(conversation_id, %{})
      |> Map.get(:scope)
    end)
  end

  def delete(conversation_id) do
    Agent.update(__MODULE__, fn state ->
      Map.delete(state, conversation_id)
    end)
  end
end
