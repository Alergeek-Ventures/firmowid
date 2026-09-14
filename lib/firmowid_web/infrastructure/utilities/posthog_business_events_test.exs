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
