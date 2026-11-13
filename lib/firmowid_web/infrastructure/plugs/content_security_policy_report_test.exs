defmodule FirmowidWeb.Infrastructure.Plugs.ContentSecurityPolicyReportTest do
  use FirmowidWeb.ConnCase, async: true

  import ExUnit.CaptureLog

  alias FirmowidWeb.Infrastructure.Plugs.ContentSecurityPolicyReport

  # The test configuration logs errors only; the reports are warnings.
  setup do
    Logger.put_module_level(ContentSecurityPolicyReport, :warning)
    on_exit(fn -> Logger.delete_module_level(ContentSecurityPolicyReport) end)
  end

  defp post_report(content_type, report) do
    build_conn()
    |> put_req_header("content-type", content_type)
    |> post(ContentSecurityPolicyReport.path(), Jason.encode!(report))
  end

  test "logs a report in either format without query strings" do
    logs =
      capture_log([level: :warning], fn ->
        conn =
          post_report("application/csp-report", %{
            "csp-report" => %{
              "document-uri" => "https://firmowid.example/faktury?szukaj=Acme",
              "violated-directive" => "script-src-elem",
              "blocked-uri" => "https://cdn.example.com/widget.js?key=abc",
              "source-file" => "https://firmowid.example/assets/app.js?v=1",
              "line-number" => 12
            }
          })

        assert conn.status == 204

        conn =
          post_report("application/reports+json", [
            %{
              "type" => "csp-violation",
              "body" => %{
                "documentURL" => "https://firmowid.example/kosztowe/01a1d27d-0f3d-7698-8fb6-a715bbf775a5?token=xyz",
                "effectiveDirective" => "img-src",
                "blockedURL" => "https://images.example.com/a.png?sig=abc",
                "lineNumber" => 3
              }
            }
          ])

        assert conn.status == 204
      end)

    assert logs =~ "csp_directive=script-src-elem"
    assert logs =~ "csp_blocked=https://cdn.example.com "
    assert logs =~ "csp_document=/faktury "
    assert logs =~ "csp_source=https://firmowid.example/assets/app.js "
    assert logs =~ "csp_directive=img-src"
    assert logs =~ "csp_document=/kosztowe/[ID] "

    for dropped <- ["szukaj", "key=abc", "token=xyz", "sig=abc", "v=1"] do
      refute logs =~ dropped
    end
  end

  test "keeps a path's token and forged text out of the log" do
    logs =
      capture_log([level: :warning], fn ->
        post_report("application/csp-report", %{
          "csp-report" => %{
            "document-uri" => "https://firmowid.example/%72esetuj-haslo/made-up-token",
            "violated-directive" => "script-src-elem",
            "blocked-uri" => "inline",
            "source-file" => "https://firmowid.example/resetuj-haslo/made-up-token"
          }
        })

        post_report("application/csp-report", %{
          "csp-report" => %{
            "document-uri" => "someone wrote this user_id=42",
            "violated-directive" => "img-src\n12:00:00.000 [error] forged line",
            "blocked-uri" => "https://a.example user_id=7"
          }
        })
      end)

    # The router matches a percent-encoded path too.
    assert logs =~ "csp_document=/resetuj-haslo/[REDACTED_TOKEN] "
    assert logs =~ "csp_source=https://firmowid.example/resetuj-haslo/[REDACTED_TOKEN] "

    for dropped <- ["made-up-token", "forged line", "user_id=42", "user_id=7"] do
      refute logs =~ dropped
    end
  end

  test "drops reports caused by browser extensions" do
    logs =
      capture_log([level: :warning], fn ->
        conn =
          post_report("application/csp-report", %{
            "csp-report" => %{
              "document-uri" => "https://firmowid.example/faktury",
              "violated-directive" => "script-src-elem",
              "blocked-uri" => "moz-extension://0a1b2c/content.js"
            }
          })

        assert conn.status == 204
      end)

    refute logs =~ "Content Security Policy violation"
  end
end
