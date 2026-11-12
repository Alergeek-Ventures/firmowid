defmodule Firmowid.Assistant do
  @moduledoc "Durable, organization-scoped assistant conversations and approval decisions."
  use Ash.Domain

  resources do
    resource Firmowid.Assistant.Conversation do
      define :start_conversation, action: :start
      define :start_subject_conversation, action: :for_subject
      define :start_analysis_conversation, action: :for_analysis
      define :get_conversation, action: :read, get_by: [:id]
      define :list_conversations, action: :list
      define :send_message, action: :send_message
      define :respond_to_plan, action: :respond_to_plan
    end

    resource Firmowid.Assistant.Message do
      define :list_messages, action: :list
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end

  @doc "Returns unanswered calls from an awaiting session with its ordered messages loaded."
  @spec pending_calls(map()) :: [map()]
  def pending_calls(%{status: :awaiting_approval, messages: messages}) do
    messages
    |> Firmowid.Assistant.Transcript.pending_calls()
    |> Enum.map(&Map.take(&1, ["id", "name", "arguments"]))
  end

  def pending_calls(_conversation), do: []

  @doc """
  Whether the assistant may reopen a conversation without the user choosing it: only
  one active on the current Polish calendar day. Older ones stay available in history.
  """
  @spec resumable?(map()) :: boolean()
  def resumable?(%{updated_at: updated_at}) do
    local_date(updated_at) == local_date(DateTime.utc_now())
  end

  defp local_date(datetime), do: datetime |> DateTime.shift_zone!("Europe/Warsaw") |> DateTime.to_date()

  @doc "PubSub topic carrying canonical updates and ephemeral response tokens."
  @spec topic(String.t()) :: String.t()
  def topic(id), do: "assistant:conversation:" <> id
end
