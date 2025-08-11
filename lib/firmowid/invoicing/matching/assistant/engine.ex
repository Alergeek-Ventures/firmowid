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
  alias Firmowid.Invoicing.Matching.Assistant.MessagesStorage
  alias Firmowid.Invoicing.Matching.Assistant.Message
  alias Firmowid.Invoicing.Matching.Assistant.Tool
  alias OpenaiEx.Responses
  alias OpenaiEx.ChatMessage

  @max_steps 10

  def send_message_streaming(
        conversation_id,
        user_message,
        prompt,
        tools
      ) do
    listening_process = self()
    send(listening_process, {:loading, true})

    org_id = Firmowid.Repo.get_org_id()

    Task.start_link(fn ->
      Firmowid.Repo.put_org_id(org_id)

      user_message = Message.new(:user, user_message)
      send(listening_process, user_message)
      MessagesStorage.append(conversation_id, user_message)

      base_messages = [ChatMessage.system(prompt)] ++ to_llm_messages(conversation_id)

      do_function_loop_streaming(
        conversation_id,
        base_messages,
        tools,
        listening_process
      )

      send(listening_process, {:loading, false})
    end)

    :ok
  end

  defp do_function_loop_streaming(
         conversation_id,
         messages,
         tools,
         listening_process,
         step \\ 0
       )

  defp do_function_loop_streaming(
         _conversation_id,
         _messages,
         _tools,
         _listening_process,
         @max_steps
       ),
       do: {:error, :max_function_steps}

  defp do_function_loop_streaming(
         conversation_id,
         messages,
         tools,
         listening_process,
         step
       ) do
    openai = Application.get_env(:firmowid, :openai_api_key) |> OpenaiEx.new()

    response =
      Responses.create!(
        openai,
        %{
          model: "gpt-4o",
          input: messages,
          tools: Enum.map(tools, &Tool.to_openai_response/1)
        },
        stream: true
      )

    stream =
      response.body_stream
      |> Stream.flat_map(& &1)
      |> Stream.map(& &1.data)
      |> Stream.transform(nil, fn item, acc ->
        case item do
          %{
            "type" => "response.output_item.added",
            "item" => %{"type" => "message"}
          } ->
            msg = Message.new(:assistant, "", %{done: false})
            {[msg], msg}

          %{"type" => "response.output_text.delta", "delta" => delta} ->
            msg = Map.update!(acc, :text, &(&1 <> delta))
            {[msg], msg}

          %{"type" => "response.output_text.done", "text" => text} ->
            msg =
              acc
              |> Map.replace(:text, text)
              |> Map.update(:payload, %{}, &Map.put(&1, :done, true))

            {[msg], nil}

          %{
            "type" => "response.output_item.added",
            "item" => %{
              "type" => "function_call",
              "name" => fname,
              "call_id" => call_id
            }
          } ->
            msg =
              Message.new(:function_call, fname, %{
                name: fname,
                args: %{},
                call_id: call_id,
                done: false
              })

            {[msg], msg}

          %{
            "type" => "response.output_item.done",
            "item" => %{"type" => "function_call", "arguments" => args_json}
          } ->
            call_msg =
              Map.update!(acc, :payload, fn payload ->
                payload
                |> Map.put(:done, true)
                |> Map.put(:args, Jason.decode!(args_json))
              end)

            msgs = execute_function_call(call_msg, tools)
            {msgs, nil}

          _ ->
            {[], acc}
        end
      end)
      |> Stream.each(fn msg -> send(listening_process, msg) end)
      |> Stream.filter(fn msg -> msg.payload && msg.payload.done end)
      |> Stream.each(fn msg -> MessagesStorage.append(conversation_id, msg) end)

    msgs = Enum.to_list(stream)

    cond do
      _replied_with_text = Enum.any?(msgs, &(&1.role == :assistant and &1.text != "")) ->
        {:ok, List.last(msgs)}

      _halted = Enum.any?(msgs, &Map.get(&1.payload, :halt, false)) ->
        {:ok, :function_halted}

      true ->
        new_messages = messages ++ Enum.map(msgs, &to_llm_message/1)

        do_function_loop_streaming(
          conversation_id,
          new_messages,
          tools,
          listening_process,
          step + 1
        )
    end
  end

  defp execute_function_call(
         %Message{
           role: :function_call,
           payload: %{name: fname, args: args, call_id: call_id, done: true}
         } = call_msg,
         tools
       ) do
    Logger.debug("function_call: exec: #{inspect(fname)}, args: #{inspect(args)}")

    tool = Enum.find(tools, &(&1.name == fname))

    try do
      tool_result = tool.handler.(args)

      case tool_result do
        :halt ->
          call_msg = call_msg |> Map.update!(:payload, &Map.put(&1, :halt, true))
          [call_msg]

        _ ->
          llm_render = tool.llm_render.(tool_result)

          result_msg =
            Message.new(:function_result, llm_render, %{
              name: fname,
              args: args,
              call_id: call_id,
              result: tool_result,
              done: true
            })

          [call_msg, result_msg]
      end
    rescue
      error ->
        error_msg =
          Message.new(:function_result, "Error: #{inspect(error)}", %{
            name: fname,
            args: args,
            call_id: call_id,
            result: nil,
            done: true
          })

        Logger.error("#{inspect(error)}")
        [call_msg, error_msg]
    end
  end

  defp to_llm_messages(conversation_id) do
    MessagesStorage.get(conversation_id)
    |> Enum.filter(&(&1.role in [:user, :assistant, :function_call, :function_result]))
    |> Enum.map(&to_llm_message/1)
  end

  defp to_llm_message(%Message{role: :user, text: text}), do: ChatMessage.user(text)
  defp to_llm_message(%Message{role: :assistant, text: text}), do: ChatMessage.assistant(text)

  defp to_llm_message(%Message{
         role: :function_call,
         payload: %{name: name, args: args, call_id: call_id}
       }),
       do: %{
         type: "function_call",
         name: name,
         arguments: Jason.encode!(args),
         call_id: call_id
       }

  defp to_llm_message(%Message{
         role: :function_result,
         payload: %{call_id: call_id},
         text: text
       }),
       do: %{
         type: "function_call_output",
         call_id: call_id,
         output: text
       }

  defp to_llm_message(item), do: raise("Unsupported message type: #{inspect(item)}")
end
