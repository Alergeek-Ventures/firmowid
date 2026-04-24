defmodule Firmowid.Test.Support.OpenAIEnrichmentTestHelpers do
  @moduledoc """
  Shared helpers for stubbing OpenAI HTTP requests.
  """

  @spec stub_openai_enrichment_request() :: :ok
  def stub_openai_enrichment_request do
    Req.Test.stub(:openai_enrichment, fn conn ->
      Req.Test.json(conn, openai_responses_body())
    end)

    :ok
  end

  @spec start_openai_ex_http_stub() :: {:ok, String.t()}
  def start_openai_ex_http_stub do
    start_http_stub(__MODULE__.OpenAIExHttpStub, "/v1")
  end

  @spec start_reducto_http_stub() :: {:ok, String.t()}
  def start_reducto_http_stub do
    start_http_stub(__MODULE__.ReductoHttpStub, "")
  end

  defp start_http_stub(plug, path_suffix) do
    {:ok, pid} = Bandit.start_link(plug: plug, ip: {0, 0, 0, 0}, port: 0, startup_log: false)

    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    Process.unlink(pid)

    ExUnit.Callbacks.on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :normal)
    end)

    {:ok, "http://localhost:#{port}#{path_suffix}"}
  end

  defp openai_responses_body do
    %{
      "id" => "resp-test",
      "object" => "response",
      "created" => 1_745_000_000,
      "model" => "gpt-5-nano",
      "status" => "completed",
      "output" => [
        %{
          "id" => "msg-test",
          "type" => "message",
          "role" => "assistant",
          "content" => [
            %{"type" => "output_text", "text" => "Zakup testowy"}
          ]
        }
      ],
      "usage" => %{
        "input_tokens" => 10,
        "output_tokens" => 2,
        "total_tokens" => 12
      }
    }
  end

  @spec openai_responses_json() :: String.t()
  def openai_responses_json do
    Jason.encode!(openai_responses_body())
  end
end

defmodule Firmowid.Test.Support.OpenAIEnrichmentTestHelpers.OpenAIExHttpStub do
  @moduledoc """
  Local HTTP stub for OpenaiEx calls.
  """

  import Plug.Conn

  alias Firmowid.Test.Support.OpenAIEnrichmentTestHelpers

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%Plug.Conn{method: "POST", request_path: "/v1/chat/completions"} = conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      200,
      Jason.encode!(%{
        "id" => "chatcmpl-test",
        "object" => "chat.completion",
        "created" => 1_745_000_000,
        "model" => "gpt-5-nano",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{"role" => "assistant", "content" => "Upload Supplier Sp. z o.o."},
            "finish_reason" => "stop"
          }
        ]
      })
    )
  end

  def call(%Plug.Conn{method: "POST", request_path: "/v1/responses"} = conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, OpenAIEnrichmentTestHelpers.openai_responses_json())
  end

  def call(conn, _opts) do
    send_resp(conn, 404, "not found")
  end
end

defmodule Firmowid.Test.Support.OpenAIEnrichmentTestHelpers.ReductoHttpStub do
  @moduledoc """
  Local HTTP stub for Reducto calls.
  """

  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%Plug.Conn{method: "POST", request_path: "/upload"} = conn, _opts) do
    json(conn, %{"file_id" => "test-file-id"})
  end

  def call(%Plug.Conn{method: "POST", request_path: "/extract"} = conn, _opts) do
    case Application.fetch_env!(:firmowid, :reducto_extract_result) do
      {:ok, result} ->
        json(conn, %{"result" => result})

      {:error, reason} ->
        json(conn, %{"error" => inspect(reason)})
    end
  end

  def call(conn, _opts) do
    send_resp(conn, 404, "not found")
  end

  defp json(conn, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(body))
  end
end
