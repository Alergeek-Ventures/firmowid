defmodule Firmowid.Invoicing.Matching.Assistant.Engine do
  @moduledoc """
  Generic engine for LLM-powered assistants with function/tool support.
  Handles:
    - function-call loop (sync)
    - streaming chat with token broadcasting
    - message persistence (user, assistant, tool_call, tool_result)
  Accepts:
    - prompt (string)
    - conversation_id
    - tools ([Tool.t()])
    - exec_function (name, args -> result)
    - options (model, etc.)
  No domain logic; only plumbing.
  """

  require Logger
  alias Firmowid.LLMOpenAI
  alias Firmowid.Invoicing.Matching.Assistant.MessagesStorage
  alias Firmowid.Invoicing.Matching.Assistant.Message

  @max_steps 10

  @doc """
  Synchronous message send with function-call loop.
  """
  def send_message(conversation_id, user_message, prompt, tools, exec_function, opts \\ []) do
    MessagesStorage.append(conversation_id, Message.new(:user, user_message))
    base_messages = [%{role: "system", content: prompt}] ++ to_llm_messages(conversation_id)
    llm_tools = tools
    llm_opts = Keyword.merge([tools: llm_tools, function_call: "auto"], opts)
    do_function_loop(conversation_id, base_messages, llm_tools, exec_function, llm_opts, 0)
  end

  defp do_function_loop(_conversation_id, _messages, _tools, _exec_function, _opts, @max_steps),
    do: {:error, :max_function_steps}

  defp do_function_loop(conversation_id, messages, tools, exec_function, opts, step) do
    case LLMOpenAI.chat(messages, opts) do
      {:ok, %{"choices" => [%{"message" => %{"role" => "assistant", "content" => content}} | _]}} ->
        msg = Message.new(:assistant, content)
        MessagesStorage.append(conversation_id, msg)
        {:ok, msg}

      {:ok,
       %{
         "choices" => [
           %{
             "message" => %{
               "role" => "assistant",
               "function_call" => %{"name" => fname, "arguments" => args_json}
             }
           }
           | _
         ]
       }} ->
        llm_render = execute_tool_call(fname, args_json, exec_function, tools, conversation_id)

        new_messages =
          messages ++ [%{role: "function", name: fname, content: llm_render}]

        do_function_loop(conversation_id, new_messages, tools, exec_function, opts, step + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Asynchronous message send with PubSub loading indicator (no streaming).
  Appends the final assistant message after the function-call loop.
  """
  def send_message_async(conversation_id, user_message, prompt, tools, exec_function, opts \\ []) do
    org_id = Firmowid.Repo.get_org_id()
    Task.start_link(fn ->
      # Set org_id for the Task process so all DB calls have correct context
      Firmowid.Repo.put_org_id(org_id)

      Logger.debug(
        "send_message_async: user message: #{inspect({conversation_id, user_message})}"
      )

      MessagesStorage.broadcast(conversation_id, {:loading, true})
      MessagesStorage.append(conversation_id, Message.new(:user, user_message))
      base_messages = [%{role: "system", content: prompt}] ++ to_llm_messages(conversation_id)
      llm_tools = tools
      llm_opts = Keyword.merge([tools: llm_tools, tool_choice: "auto"], opts)
      Logger.debug("function_call_loop: enter: #{inspect(conversation_id)}")

      result =
        do_function_loop_stream(
          conversation_id,
          base_messages,
          llm_tools,
          exec_function,
          llm_opts,
          0
        )

      Logger.debug("function_call_loop: result: #{inspect(result)}")

      case result do
        {:ok, %Message{role: :assistant, text: text}} when is_binary(text) and text != "" ->
          msg = Message.new(:assistant, text)
          MessagesStorage.append(conversation_id, msg)
          Logger.debug("async: appended final assistant message: #{inspect(msg)}")

        _ ->
          Logger.debug("no assistant message: #{inspect(result)}")
          :noop
      end

      MessagesStorage.broadcast(conversation_id, {:loading, false})
    end)
  end

  defp do_function_loop_stream(
         _conversation_id,
         _messages,
         _tools,
         _exec_function,
         _opts,
         @max_steps
       ),
       do: {:error, :max_function_steps}

  defp do_function_loop_stream(conversation_id, messages, tools, exec_function, opts, step) do
    Logger.debug("do_function_loop_stream: step #{step}, messages: #{inspect(messages)}")

    case LLMOpenAI.chat(messages, opts) do
      # Modern OpenAI tool_calls format
      {:ok,
       %{
         "choices" => [
           %{"message" => %{"role" => "assistant", "tool_calls" => tool_calls}}
           | _
         ]
       }}
      when is_list(tool_calls) and tool_calls != [] ->
        Logger.debug("LLM response: tool_calls: #{inspect(tool_calls)}")
        # Build the assistant message with tool_calls for the message history
        assistant_msg_map = %{
          role: "assistant",
          content: "",
          tool_calls: tool_calls
        }

        # For each tool_call, execute and build the tool message
        Enum.reduce_while(tool_calls, [], fn tool_call, acc ->
          fname = tool_call["function"]["name"]
          args_json = tool_call["function"]["arguments"]

          case execute_tool_call(fname, args_json, exec_function, tools, conversation_id) do
            {:stop, _llm_render} ->
              {:halt, :stop}

            {:halt, _llm_render} ->
              {:halt, :halt}

            {:ok, llm_render} ->
              tool_result =
                %{
                  role: "tool",
                  tool_call_id: tool_call["id"],
                  name: fname,
                  content: llm_render
                }

              {:cont, acc ++ [tool_result]}
          end
        end)
        |> case do
          :stop ->
            MessagesStorage.delete(conversation_id)
            {:ok, nil}

          :halt ->
            {:ok, nil}

          tool_msgs when is_list(tool_msgs) ->
            # Append the assistant message with tool_calls, then all tool messages
            new_messages = messages ++ [assistant_msg_map] ++ tool_msgs
            Logger.debug("tool_call message sequence: #{inspect(new_messages)}")

            do_function_loop_stream(
              conversation_id,
              new_messages,
              tools,
              exec_function,
              opts,
              step + 1
            )
        end

      # Plain assistant message
      {:ok, %{"choices" => [%{"message" => %{"role" => "assistant", "content" => content}} | _]}} ->
        Logger.debug("LLM response: assistant: #{inspect(content)}")
        msg = Message.new(:assistant, content)
        {:ok, msg}

      {:error, reason} ->
        Logger.debug("LLM error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp execute_tool_call(fname, args_json, exec_function, tools, conversation_id) do
    args =
      case Jason.decode(args_json) do
        {:ok, decoded} -> decoded
        _ -> %{}
      end

    call_msg =
      Message.new(:function_call, "#{fname}(#{inspect(args)})", %{name: fname, args: args})

    MessagesStorage.append(conversation_id, call_msg)
    Logger.debug("function_call: exec: #{inspect(fname)}, args: #{inspect(args)}")
    result = exec_function.(fname, args)
    tool = Enum.find(tools, &(&1.name == fname))

    llm_render = if tool, do: tool.llm_render.(result), else: inspect(result)

    result_msg =
      Message.new(:function_result, llm_render, %{name: fname, args: args, result: result})

    MessagesStorage.append(conversation_id, result_msg)

    Logger.debug("function_result: appended: #{inspect(fname)}, result: #{inspect(result)}")

    case result do
      {:stop, _} -> {:stop, llm_render}
      {:halt, _} -> {:halt, llm_render}
      _ -> {:ok, llm_render}
    end
  end

  defp to_llm_messages(conversation_id) do
    Firmowid.Invoicing.Matching.Assistant.MessagesStorage.get(conversation_id)
    |> Enum.filter(&(&1.role in [:user, :assistant, :function_call, :function_result]))
    |> Enum.map(&to_llm_message/1)
  end

  defp to_llm_message(%Message{role: :user, text: text}), do: %{role: "user", content: text}

  defp to_llm_message(%Message{role: :assistant, text: text}),
    do: %{role: "assistant", content: text}

  defp to_llm_message(%Message{role: :function_call, payload: %{name: name, args: _}, text: text}),
    do: %{role: "function", name: name, content: text || ""}

  defp to_llm_message(%Message{
         role: :function_result,
         payload: %{name: name},
         text: text
       }),
       do: %{role: "function", name: name, content: text}

  defp to_llm_message(_), do: nil
end
