defmodule FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEventsTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Firmowid.Test.Support.PosthogClient
  alias FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents
  alias Phoenix.LiveView.Socket

  test "captures authenticated business events with a stable ID and organization group regardless of consent" do
    PosthogClient.enable()

    for consent <- [false, nil] do
      socket = socket(%{analytics_consent_accepted: consent})
      assert PosthogBusinessEvents.capture(socket, :invoice_created) == socket

      assert_receive {:posthog_capture, "invoice_created", "user-id",
                      %{"$groups" => %{"organization" => "organization-id"}}}
    end

    assert PosthogBusinessEvents.capture(socket(%{}), :payroll_rates_updated, %{
             changed_employee_count: 2
           }) ==
             socket(%{})

    assert_receive {:posthog_capture, "payroll_rates_updated", "user-id", %{"changed_employee_count" => 2}}

    PosthogBusinessEvents.capture(socket(%{}), :invoice_created, %{email: "private@example.com"})
    refute_receive {:posthog_capture, _, _, _}
  end

  test "does not capture without a user or organization or when analytics is disabled" do
    PosthogClient.enable()
    PosthogBusinessEvents.capture(socket(%{current_user: nil}), :invoice_created)
    PosthogBusinessEvents.capture(socket(%{current_org: nil}), :invoice_created)
    refute_receive {:posthog_capture, _, _, _}

    PosthogClient.disable()
    PosthogBusinessEvents.capture(socket(%{}), :invoice_created)
    refute_receive {:posthog_capture, _, _, _}
  end

  defp socket(assigns) do
    %Socket{
      assigns:
        Map.merge(
          %{current_user: %{id: "user-id"}, current_org: %{id: "organization-id"}},
          assigns
        )
    }
  end
end
