defmodule Firmowid.Assistant.Telemetry do
  @moduledoc """
  Reports every model call of the assistant to PostHog LLM analytics as an
  `$ai_generation` event: model, token counts, cost, duration and outcome.

  The events carry no content. The questions, the answers, tool arguments and
  tool results never leave the application; only the numbers above do, together
  with the stable user and organization IDs the other server-side events use.
  A failed call reports the kind of error, not its message.

  One turn of a conversation is one trace, and the conversation is the session,
  so the cost of a question is the sum of the calls its tools needed.

  The data comes from ReqLLM's own request events. `request_options/2` marks the
  assistant's requests; model calls made elsewhere in the application are ignored.
  """

  @events [[:req_llm, :request, :stop], [:req_llm, :request, :exception]]
  @context_key :firmowid_assistant

  @doc "Attaches the reporter once at application startup."
  @spec attach() :: :ok | {:error, :already_exists}
  def attach, do: :telemetry.attach_many(__MODULE__, @events, &__MODULE__.handle_event/4, nil)

  @doc """
  Returns the ReqLLM options that mark the requests of one turn of `conversation`,
  run in `scope`, so that their events can be attributed. Each call starts a new trace.
  """
  @spec request_options(%{id: term()}, %{actor: %{id: term()}, tenant: term()}) :: keyword()
  def request_options(%{id: conversation_id}, %{actor: %{id: user_id}, tenant: organization_id}) do
    context = %{
      user_id: to_string(user_id),
      organization_id: to_string(organization_id),
      conversation_id: to_string(conversation_id),
      trace_id: Ash.UUID.generate()
    }

    [telemetry: [extra_metadata: %{@context_key => context}]]
  end

  @doc "Captures a finished or failed assistant request. Never raises: telemetry must not break a turn."
  @spec handle_event([atom()], map(), map(), nil) :: :ok
  def handle_event([:req_llm, :request, outcome], measurements, metadata, nil) do
    with {user_id, properties} <- generation(outcome, measurements, metadata),
         true <- enabled?() do
      PostHog.bare_capture("$ai_generation", user_id, properties)
    end

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  @doc """
  Builds the user ID and the properties of the `$ai_generation` event for a ReqLLM
  request event, or `nil` when the request was not made by the assistant.
  """
  @spec generation(:stop | :exception, map(), map()) :: {String.t(), map()} | nil
  def generation(outcome, measurements, %{extra_metadata: %{@context_key => context}} = metadata) do
    properties =
      %{
        "$ai_trace_id" => context.trace_id,
        "$ai_session_id" => context.conversation_id,
        "$ai_span_name" => "assistant_turn",
        "$ai_provider" => provider(metadata),
        "$ai_model" => model(metadata),
        "$ai_latency" => latency(measurements),
        "$ai_http_status" => metadata[:http_status],
        "$ai_stream" => metadata[:mode] == :stream,
        "$ai_is_error" => outcome == :exception,
        "$ai_error" => error_kind(outcome, metadata[:error]),
        "surface" => "app",
        "auth_state" => "identified",
        "$groups" => %{"organization" => context.organization_id}
      }
      |> Map.merge(usage(metadata[:usage]))
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    {context.user_id, properties}
  end

  def generation(_outcome, _measurements, _metadata), do: nil

  defp provider(%{provider: provider}) when not is_nil(provider), do: to_string(provider)
  defp provider(_metadata), do: nil

  defp model(%{model: %{id: id}}) when is_binary(id), do: id
  defp model(%{model: model}) when is_binary(model), do: model
  defp model(_metadata), do: nil

  defp latency(%{duration: duration}) when is_integer(duration),
    do: System.convert_time_unit(duration, :native, :millisecond) / 1000

  defp latency(_measurements), do: nil

  defp usage(usage) when is_map(usage) do
    %{
      "$ai_input_tokens" => usage[:input_tokens],
      "$ai_output_tokens" => usage[:output_tokens],
      "$ai_input_cost_usd" => usage[:input_cost],
      "$ai_output_cost_usd" => usage[:output_cost],
      "$ai_total_cost_usd" => usage[:total_cost]
    }
  end

  defp usage(_usage), do: %{}

  # An error message can quote the request, so only the kind of error is reported.
  defp error_kind(:exception, %module{}), do: inspect(module)

  defp error_kind(:exception, reason) when is_atom(reason) and not is_nil(reason), do: Atom.to_string(reason)

  defp error_kind(:exception, _reason), do: "error"
  defp error_kind(_outcome, _error), do: nil

  defp enabled? do
    match?(%{enabled: true}, PostHog.config())
  rescue
    _error -> false
  end
end
