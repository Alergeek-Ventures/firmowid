defmodule Firmowid.LLMOpenAI do
  @moduledoc """
  Direct OpenAI API client using Req, for chat completions and streaming.
  Replaces llm_composer and openai packages.
  """

  @openai_url "https://api.openai.com/v1/chat/completions"
  @openai_url_responses "https://api.openai.com/v1/responses"

  @doc """
  Synchronous chat completion.
  - messages: list of OpenAI-formatted message maps
  - opts: model, api_key, tools (as [Tool.t()] or already-converted), function_call, etc.
  Returns {:ok, response} or {:error, reason}
  """
  def chat(messages, opts \\ []) do
    body = build_body(messages, opts)
    headers = build_headers()

    Req.post(@openai_url,
      headers: headers,
      json: body,
      receive_timeout: 50_000,
      connect_options: [timeout: 50_000]
    )
    |> handle_response()
  end

  @doc """
  Streaming chat completion (yields tokens as they arrive).
  - messages: list of OpenAI-formatted message maps
  - opts: model, api_key, tools (as [Tool.t()] or already-converted), function_call, etc.
  Returns a Stream of decoded chunks.
  """
  def stream(messages, opts \\ []) do
    body = build_body_stream(messages, Keyword.put(opts, :stream, true))
    headers = build_headers()

    Stream.resource(
      fn ->
        {:ok, queue} = Agent.start_link(fn -> :queue.new() end)

        task =
          Task.async(fn ->
            Req.post!(@openai_url_responses,
              headers: headers,
              json: body,
              receive_timeout: 50_000,
              connect_options: [timeout: 50_000],
              into: fn {:data, data}, acc ->
                Agent.update(queue, &:queue.in(data, &1))
                {:cont, acc}
              end
            )

            Agent.update(queue, &:queue.in(:done, &1))
          end)

        {queue, task}
      end,
      fn {queue, task} ->
        receive_chunk = fn ->
          Agent.get_and_update(queue, fn q ->
            case :queue.out(q) do
              {{:value, :done}, q2} -> {:done, q2}
              {{:value, chunk}, q2} -> {{:chunk, chunk}, q2}
              {:empty, q2} -> {:empty, q2}
            end
          end)
        end

        case receive_chunk.() do
          :done ->
            Task.await(task, 5000)
            {:halt, {queue, task}}

          {:chunk, chunk} ->
            {[parse_sse_chunk(chunk)], {queue, task}}

          :empty ->
            Process.sleep(10)
            {[], {queue, task}}
        end
      end,
      fn {queue, task} ->
        Agent.stop(queue)
        Task.shutdown(task, :brutal_kill)
      end
    )
    |> Stream.flat_map(& &1)
  end

  defp build_body_stream(messages, opts) do
    tools =
      case Keyword.get(opts, :tools) do
        [head | _tail] = list ->
          case head do
            %Firmowid.Invoicing.Matching.Assistant.Tool{} ->
              Enum.map(
                list,
                &Firmowid.Invoicing.Matching.Assistant.Tool.to_openai_response/1
              )

            _ ->
              list
          end

        _ ->
          nil
      end

    # For GPT-4o, GPT-4-turbo, GPT-3.5-turbo-1106 and newer: use 'tools' and 'tool_choice' only
    base =
      %{
        model: Keyword.get(opts, :model, "gpt-4o"),
        input: messages
      }
      |> maybe_put(:tools, tools)
      |> maybe_put(:stream, opts[:stream])
      |> Map.merge(Keyword.get(opts, :extra, %{}))

    if tools && tools != [] && opts[:function_call] do
      Map.put(base, :tool_choice, opts[:function_call])
    else
      base
    end
  end

  defp build_body(messages, opts) do
    tools =
      case Keyword.get(opts, :tools) do
        [head | _tail] = list ->
          case head do
            %Firmowid.Invoicing.Matching.Assistant.Tool{} ->
              Enum.map(list, &Firmowid.Invoicing.Matching.Assistant.Tool.to_openai/1)

            _ ->
              list
          end

        _ ->
          nil
      end

    # For GPT-4o, GPT-4-turbo, GPT-3.5-turbo-1106 and newer: use 'tools' and 'tool_choice' only
    base =
      %{
        model: Keyword.get(opts, :model, "gpt-4o"),
        messages: messages
      }
      |> maybe_put(:tools, tools)
      |> maybe_put(:stream, opts[:stream])
      |> Map.merge(Keyword.get(opts, :extra, %{}))

    if tools && tools != [] && opts[:function_call] do
      Map.put(base, :tool_choice, opts[:function_call])
    else
      base
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp build_headers do
    api_key = Application.get_env(:openai, :api_key)
    org_key = Application.get_env(:openai, :organization_key)

    base = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    if org_key do
      [{"OpenAI-Organization", org_key} | base]
    else
      base
    end
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}), do: {:ok, body}

  defp handle_response({:ok, %Req.Response{status: status, body: body}}),
    do: {:error, {status, body}}

  defp handle_response({:error, reason}), do: {:error, reason}

  defp parse_sse_chunk(chunk) when is_binary(chunk) do
    chunk
    |> String.split("\n", trim: true)
    |> Enum.filter(&String.starts_with?(&1, "data: "))
    |> Enum.map(fn "data: " <> json -> Jason.decode!(json) end)
    |> Enum.reject(&is_nil/1)
  end
end
