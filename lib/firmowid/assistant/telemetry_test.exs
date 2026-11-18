defmodule Firmowid.Assistant.TelemetryTest do
  use ExUnit.Case, async: true

  alias Firmowid.Assistant.Telemetry
  alias Firmowid.Core.User

  @user_id "0198a1f0-0000-7000-8000-000000000001"
  @organization_id "0198a1f0-0000-7000-8000-000000000002"
  @conversation_id "0198a1f0-0000-7000-8000-000000000003"

  defp turn do
    [telemetry: telemetry] =
      Telemetry.request_options(%{id: @conversation_id}, %{
        actor: %User{id: @user_id},
        tenant: @organization_id
      })

    telemetry
  end

  defp metadata(extra \\ %{}) do
    Map.merge(
      %{
        provider: :openai,
        model: %{id: "gpt-example", provider: :openai},
        mode: :stream,
        http_status: 200,
        finish_reason: :stop,
        usage: %{
          input_tokens: 1200,
          output_tokens: 300,
          input_cost: 0.0012,
          output_cost: 0.0024,
          total_cost: 0.0036
        },
        # ReqLLM adds these two only when raw payloads are switched on.
        request_payload: %{messages: [%{role: :user, content: "Ile zapłaciła Acme Sp. z o.o.?"}]},
        response_payload: %{text: "Acme Sp. z o.o. zapłaciła 1 230 zł."},
        extra_metadata: Keyword.fetch!(turn(), :extra_metadata)
      },
      extra
    )
  end

  defp measurements, do: %{duration: System.convert_time_unit(1500, :millisecond, :native)}

  test "a turn is marked with the user, the organization and its own trace" do
    first = turn()
    second = turn()

    assert %{
             user_id: @user_id,
             organization_id: @organization_id,
             conversation_id: @conversation_id
           } =
             first[:extra_metadata][:firmowid_assistant]

    assert first[:extra_metadata][:firmowid_assistant].trace_id !=
             second[:extra_metadata][:firmowid_assistant].trace_id
  end

  test "a finished model call becomes a generation of that user and organization" do
    metadata = metadata()
    context = metadata.extra_metadata.firmowid_assistant

    assert {@user_id, properties} = Telemetry.generation(:stop, measurements(), metadata)

    assert properties["$ai_trace_id"] == context.trace_id
    assert properties["$ai_session_id"] == @conversation_id
    assert properties["$ai_span_name"] == "assistant_turn"
    assert properties["$ai_provider"] == "openai"
    assert properties["$ai_model"] == "gpt-example"
    assert properties["$ai_input_tokens"] == 1200
    assert properties["$ai_output_tokens"] == 300
    assert properties["$ai_input_cost_usd"] == 0.0012
    assert properties["$ai_output_cost_usd"] == 0.0024
    assert properties["$ai_total_cost_usd"] == 0.0036
    assert properties["$ai_latency"] == 1.5
    assert properties["$ai_http_status"] == 200
    assert properties["$ai_stream"] == true
    assert properties["$ai_is_error"] == false
    assert properties["$groups"] == %{"organization" => @organization_id}
  end

  test "a generation never carries the conversation's content" do
    {_user_id, properties} = Telemetry.generation(:stop, measurements(), metadata())

    refute Map.has_key?(properties, "$ai_input")
    refute Map.has_key?(properties, "$ai_output_choices")
    refute inspect(properties) =~ "Acme"
  end

  test "a failed model call reports the kind of error, never its message" do
    error = %RuntimeError{message: "request for Acme Sp. z o.o. failed"}

    {_user_id, properties} =
      Telemetry.generation(
        :exception,
        measurements(),
        metadata(%{error: error, http_status: 500, finish_reason: :error, usage: nil})
      )

    assert properties["$ai_is_error"] == true
    assert properties["$ai_error"] == "RuntimeError"
    assert properties["$ai_http_status"] == 500
    refute Map.has_key?(properties, "$ai_input_tokens")
    refute inspect(properties) =~ "Acme"
  end

  test "model calls outside the assistant are not reported" do
    assert nil ==
             Telemetry.generation(:stop, measurements(), Map.delete(metadata(), :extra_metadata))

    assert nil ==
             Telemetry.generation(
               :stop,
               measurements(),
               metadata(%{extra_metadata: %{other: true}})
             )
  end

  test "the handler ignores events it cannot use instead of raising" do
    assert :ok == Telemetry.handle_event([:req_llm, :request, :stop], %{}, %{}, nil)

    assert :ok ==
             Telemetry.handle_event([:req_llm, :request, :stop], measurements(), metadata(), nil)
  end
end
