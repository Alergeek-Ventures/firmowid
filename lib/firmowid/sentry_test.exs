defmodule Firmowid.SentryTest do
  @moduledoc false

  use ExUnit.Case, async: true

  # The integration test constructs SDK events directly to verify privacy filtering.
  # credo:disable-for-next-line Checks.RejectDirectSentrySdk
  alias Elixir.Sentry, as: SentrySDK
  # The request struct is an SDK value required to exercise request sanitization.
  # credo:disable-for-next-line Checks.RejectDirectSentrySdk
  alias Elixir.Sentry.Interfaces.Request
  alias Firmowid.Sentry

  test "drops unapproved extra and context fields" do
    event = %SentrySDK.Event{
      event_id: String.duplicate("a", 32),
      timestamp: DateTime.utc_now(),
      extra: %{
        operation: "sync",
        organization_id: "org-1",
        blob_id: "blob-1",
        company: "Acme",
        company_name: "Acme",
        arbitrary: "private"
      },
      contexts: %{
        runtime: %{
          name: "Elixir",
          version: "1.19",
          company: "Acme",
          company_name: "Acme",
          arbitrary: "private"
        },
        business: %{company: "Acme", company_name: "Acme", arbitrary: "private"}
      },
      request: %Request{
        url: "https://alice:secret@firmowid.pl/faktura/secret-share-token/pdf?lang=pl",
        method: "GET",
        data: %{company: "Acme"},
        cookies: %{session: "private"},
        headers: %{
          "user-agent" => "browser",
          "content-type" => ~s(text/plain; filename="private.txt"),
          "authorization" => "private"
        },
        env: %{
          "REMOTE_ADDR" => "127.0.0.1",
          "REQUEST_ID" => "request-1",
          "private" => "private"
        }
      }
    }

    scrubbed = Sentry.before_send(event)

    assert scrubbed.extra == %{operation: "sync", organization_id: "org-1"}
    assert scrubbed.contexts == %{runtime: %{name: "Elixir", version: "1.19"}}

    assert scrubbed.request == %Request{
             url: "https://firmowid.pl/faktura/[REDACTED_TOKEN]/pdf",
             method: "GET",
             query_string: nil,
             data: nil,
             cookies: nil,
             headers: %{"user-agent" => "browser"},
             env: %{"REMOTE_ADDR" => "127.0.0.1", "REQUEST_ID" => "request-1"}
           }

    assert Sentry.before_send(%{event | request: %{"url" => "private"}}).request == nil

    assert Sentry.before_send(%{
             event
             | source: :logger,
               extra: %{logger_metadata: %{sentry_live_view_captured: true}}
           }) == nil
  end

  test "keeps only scalar structured log attributes" do
    event = %SentrySDK.LogEvent{
      level: :error,
      body: "private body",
      timestamp: 0.0,
      template: "private template %{secret}",
      parameters: ["private parameter"],
      attributes: %{
        mfa: {Sentry, :before_send, 1},
        operation: %{opaque: "private"},
        status: "error",
        content_type: ~s(text/plain; filename="private.txt"),
        bytes: 42,
        arbitrary: %{company: "Acme"}
      }
    }

    assert %{body: "Log captured", template: nil, parameters: nil, attributes: attributes} =
             Sentry.before_send_log(event)

    assert attributes == %{mfa: {Sentry, :before_send, 1}, status: "error", bytes: 42}
  end

  test "removes all source content from backend stacktrace frames" do
    frame = %SentrySDK.Interfaces.Stacktrace.Frame{
      module: Sentry,
      function: "before_send/1",
      filename: "/app/lib/firmowid/sentry.ex",
      lineno: 184,
      colno: 7,
      in_app: true,
      vars: %{secret: "private"},
      context_line: "send_private_data()",
      pre_context: ["private_before()"],
      post_context: ["private_after()"]
    }

    event = %SentrySDK.Event{
      event_id: String.duplicate("b", 32),
      timestamp: DateTime.utc_now(),
      exception: [
        %SentrySDK.Interfaces.Exception{
          type: "RuntimeError",
          value: "private error",
          stacktrace: %SentrySDK.Interfaces.Stacktrace{frames: [frame]}
        }
      ]
    }

    assert %SentrySDK.Event{exception: [%{stacktrace: %{frames: [scrubbed_frame]}}]} =
             Sentry.before_send(event)

    assert scrubbed_frame.module == Sentry
    assert scrubbed_frame.function == "before_send/1"
    assert scrubbed_frame.lineno == 184
    assert scrubbed_frame.colno == 7
    assert scrubbed_frame.in_app
    assert scrubbed_frame.filename == nil
    assert scrubbed_frame.vars == nil
    assert scrubbed_frame.context_line == nil
    assert scrubbed_frame.pre_context == []
    assert scrubbed_frame.post_context == []
  end
end
