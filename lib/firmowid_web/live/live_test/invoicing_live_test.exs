defmodule FirmowidWeb.InvoicingLiveTest do
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  describe "requisition status updates" do
    setup do
      user = admin_fixture()
      %{user: user}
    end

    test "handles requisition status updates without errors", %{conn: conn, user: user} do
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/")

      # Test that all status updates are handled without crashing
      statuses = [:linked, :processing, :rejected, :expired, :timeout, :error]

      for status <- statuses do
        send(view.pid, {:requisition_status_update, %{status: status}})
        # Just verify the LiveView is still alive and responsive
        assert render(view) =~ "Fakturowanie"
      end
    end
  end
end
