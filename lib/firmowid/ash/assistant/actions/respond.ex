defmodule Firmowid.Ash.Assistant.Actions.Respond do
  @moduledoc "Streams one assistant turn for the conversation selected by AshOban."
  use Ash.Resource.ManualUpdate

  alias AshAi.Transcript, as: AshTranscript
  alias Firmowid.Ash.Assistant
  alias Firmowid.Ash.Assistant.Conversation
  alias Firmowid.Ash.Assistant.Prompt
  alias Firmowid.Ash.Assistant.ToolPolicy
  alias Firmowid.Ash.Assistant.Transcript

  @doc "Runs the selected turn and returns its terminal conversation or the stream error."
  @spec update(Ash.Changeset.t(), Keyword.t(), Ash.Resource.ManualUpdate.Context.t()) ::
          {:ok, Ash.Resource.Record.t()} | {:error, term()}
  @impl true
  def update(changeset, _opts, context) do
    conversation = changeset.data
    opts = [actor: context.actor, tenant: context.tenant, context: context.source_context]

    case ToolPolicy.fresh_scope(conversation) do
      {:ok, scope} ->
        stream(conversation, scope, opts)

      {:error, :actor_tenant_mismatch} ->
        {:ok, Conversation.fail!(conversation, %{reason: "access_revoked"}, opts)}
    end
  end

  defp stream(conversation, scope, opts) do
    tools = ToolPolicy.tools(scope)
    tool_names = Enum.map(tools, &Atom.to_string/1)

    messages =
      Assistant.list_messages!(
        %{conversation_id: conversation.id},
        Keyword.put(opts, :page, false)
      )

    result =
      conversation
      |> Map.put(:messages, messages)
      |> Transcript.messages()
      |> AshAi.ToolLoop.stream(
        otp_app: :firmowid,
        model: "openai:gpt-6-luna",
        tools: tools,
        actor: scope.actor,
        tenant: scope.tenant,
        # Never forward the worker's private AshOban authorization context.
        context: %{},
        system_prompt: fn _opts -> Prompt.system() end,
        approve_tool_call: fn call, _context -> ToolPolicy.approve(call, tool_names) end,
        approvals: ToolPolicy.approvals(conversation.approvals),
        max_iterations: 20,
        req_llm_opts: [max_retries: 0]
      )
      |> Enum.reduce_while(
        %{conversation: conversation, result_status: nil},
        &handle_stream_event(&1, &2, opts)
      )

    case result do
      {:error, _reason} = error -> error
      state -> finish(state, opts)
    end
  end

  defp handle_stream_event({:content, text}, state, _opts) when is_binary(text) do
    id = state.conversation.id
    Phoenix.PubSub.broadcast(Firmowid.PubSub, Assistant.topic(id), {:assistant_delta, id, text})
    {:cont, state}
  end

  defp handle_stream_event({:message, message}, state, opts) do
    parts = AshTranscript.to_parts([message], reasoning: false)

    if Enum.any?(parts, fn
         %{"type" => "step"} -> false
         %{"type" => "text", "text" => text} -> text != ""
         _part -> true
       end) do
      conversation =
        Conversation.append_response!(
          state.conversation,
          %{role: message.role, parts: parts},
          opts
        )

      {:cont, %{state | conversation: conversation}}
    else
      {:cont, state}
    end
  end

  defp handle_stream_event({:error, reason}, _state, _opts), do: {:halt, {:error, reason}}

  defp handle_stream_event({:done, result}, state, _opts), do: {:cont, %{state | result_status: result.status}}

  defp handle_stream_event(_event, state, _opts), do: {:cont, state}

  defp finish(%{result_status: :awaiting_approval} = state, opts) do
    {:ok, Conversation.await_approval!(state.conversation, %{}, opts)}
  end

  defp finish(%{result_status: :complete} = state, opts) do
    {:ok, Conversation.complete!(state.conversation, %{}, opts)}
  end

  defp finish(_state, _opts), do: {:error, :incomplete_response}
end
