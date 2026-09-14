defmodule FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEventsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents
  alias Phoenix.LiveView.Socket

  test "does not capture without analytics consent" do
    socket = socket(%{analytics_consent_accepted: false})

    assert PosthogBusinessEvents.capture(socket, :invoice_created) == socket
  end

  test "does not capture when PostHog is disabled" do
    socket = socket(%{analytics_consent_accepted: true})

    assert PosthogBusinessEvents.capture(socket, :invoice_created) == socket
  end

  test "account creation capture is gated by the consent cookie" do
    conn = Plug.Test.conn(:get, "/")

    result = PosthogBusinessEvents.capture_account_created(conn, %{id: "user-id"})

    assert result.cookies == %{}
  end

  test "account creation capture does not require an organization" do
    conn = Plug.Test.conn(:get, "/")
    conn = Plug.Conn.put_req_cookie(conn, "cookie_consent", "accepted")

    result = PosthogBusinessEvents.capture_account_created(conn, %{id: "user-id"})

    assert result.cookies["cookie_consent"] == "accepted"
  end

  defp socket(assigns) do
    %Socket{
      assigns:
        Map.merge(
          %{
            current_user: %{id: "user-id"},
            current_org: %{id: "organization-id"}
          },
          assigns
        )
    }
  end
end
