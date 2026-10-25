defmodule Firmowid.Ash.Assistant do
  @moduledoc "Durable, organization-scoped assistant conversations and approval decisions."
  use Ash.Domain

  resources do
    resource Firmowid.Ash.Assistant.Conversation do
      define :get_or_create_conversation, action: :get_or_create
      define :get_conversation, action: :read, get_by: [:id]
      define :send_message, action: :send_message
      define :respond_to_plan, action: :respond_to_plan
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  @doc "Returns the unanswered calls from the canonical pending assistant turn."
  @spec pending_calls(map()) :: [map()]
  def pending_calls(%{status: :awaiting_approval, transcript: transcript}) do
    transcript
    |> List.last()
    |> Map.fetch!("parts")
    |> AshAi.Transcript.pending_tool_calls()
    |> Enum.map(&Map.take(&1, ["id", "name", "arguments"]))
  end

  def pending_calls(_conversation), do: []

  @doc "PubSub topic carrying canonical updates and ephemeral response tokens."
  @spec topic(String.t()) :: String.t()
  def topic(id), do: "assistant:conversation:" <> id
end
