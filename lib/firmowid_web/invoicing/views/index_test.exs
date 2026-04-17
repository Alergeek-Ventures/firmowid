defmodule FirmowidWeb.Invoicing.Views.IndexTest do
  @moduledoc """
  Tests for the Invoicing Index LiveView PubSub notifications.

  Uses Ash integration test approach - creates actual requisitions,
  performs state transitions, and lets Ash.Notifier.PubSub broadcast
  naturally to the LiveView.
  """
  use FirmowidWeb.ConnCase

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Finances.Requisition

  describe "requisition status PubSub notifications" do
    setup do
      user = admin_fixture()

      # Stub GoCardless API calls
      Req.Test.stub(:bank_data_requisition, fn conn ->
        Req.Test.json(conn, %{
          "id" => "test-req-id",
          "status" => "LN",
          "accounts" => ["account-123"]
        })
      end)

      Req.Test.stub(:bank_data_account, fn conn ->
        Req.Test.json(conn, %{
          "id" => "account-123",
          "iban" => "GL123456789",
          "name" => "Test Account",
          "currency" => "EUR",
          "ownerName" => "Test Owner"
        })
      end)

      Req.Test.stub(:bank_data_institution, fn conn ->
        Req.Test.json(conn, %{
          "id" => "test-institution",
          "name" => "Test Bank",
          "bic" => "TESTBIC"
        })
      end)

      Req.Test.stub(:bank_data_transactions, fn conn ->
        Req.Test.json(conn, %{
          "transactions" => %{"booked" => []}
        })
      end)

      %{user: user}
    end

    test "handles accept notification without crashing", %{conn: conn, user: user} do
      requisition_id = Ecto.UUID.generate()

      {:ok, requisition} = create_requisition(user, requisition_id)

      # Mount the LiveView (subscribes to PubSub topics)
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/fakturowanie")

      # Accept the requisition - triggers Ash.Notifier.PubSub broadcast
      # This will call GoCardless API (stubbed above) and broadcast :linked
      {:ok, _accepted} =
        requisition
        |> Ash.Changeset.for_update(:accept, %{},
          tenant: user.organization_id,
          actor: user,
          authorize?: false
        )
        |> Ash.update(tenant: user.organization_id, actor: user, authorize?: false)

      # Give PubSub a moment to deliver
      Process.sleep(50)

      # Verify LiveView is still alive and responsive
      assert render(view) =~ "Fakturowanie"
    end

    test "handles reject notification without crashing", %{conn: conn, user: user} do
      requisition_id = Ecto.UUID.generate()

      {:ok, requisition} = create_requisition(user, requisition_id)

      # Mount the LiveView
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/fakturowanie")

      # Reject the requisition - triggers Ash.Notifier.PubSub broadcast
      {:ok, _rejected} =
        requisition
        |> Ash.Changeset.for_update(:reject, %{},
          tenant: user.organization_id,
          actor: user,
          authorize?: false
        )
        |> Ash.update(tenant: user.organization_id, actor: user, authorize?: false)

      # Give PubSub a moment to deliver
      Process.sleep(50)

      # Verify LiveView is still alive and responsive
      assert render(view) =~ "Fakturowanie"
    end
  end

  defp create_requisition(user, requisition_id) do
    Requisition
    |> Ash.Changeset.for_create(:persist, %{id: requisition_id},
      tenant: user.organization_id,
      actor: user,
      authorize?: false
    )
    |> Ash.create(tenant: user.organization_id, actor: user, authorize?: false)
  end
end
