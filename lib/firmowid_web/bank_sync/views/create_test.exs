defmodule FirmowidWeb.BankSync.Views.CreateTest do
  @moduledoc """
  Tests for the bank connection creation LiveView.

  Note: AshOban automatically schedules the check_status trigger when a
  requisition is created. We verify the requisition exists with pending status
  rather than checking internal job structure.
  """
  use FirmowidWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Finances.Requisition

  describe "handle_params with ref" do
    setup %{conn: conn} do
      user = Firmowid.AccountsFixtures.admin_fixture()

      # Stub institutions API for mount
      Req.Test.stub(:bank_data_institutions, fn conn ->
        Req.Test.json(conn, [])
      end)

      %{conn: log_in_user(conn, user), user: user}
    end

    test "redirects to bank accounts with success toast for pending requisition", %{conn: conn, user: user} do
      requisition_id = Ecto.UUID.generate()

      # Pre-create the requisition as pending (simulating what happens after GoCardless redirect)
      # In production, the requisition is created during the institution_selection event
      # and the redirect back from GoCardless includes the ref param
      {:ok, _requisition} =
        Requisition
        |> Ash.Changeset.for_create(:persist, %{id: requisition_id},
          tenant: user.organization_id,
          actor: user,
          authorize?: false
        )
        |> Ash.create(tenant: user.organization_id, actor: user, authorize?: false)

      # Verify requisition exists with pending status
      assert {:ok, requisition} =
               Ash.get(Requisition, requisition_id,
                 tenant: user.organization_id,
                 actor: user,
                 authorize?: false
               )

      assert requisition.status == :pending

      # When user returns from GoCardless, they get redirected to bank accounts
      {:error,
       {:live_redirect,
        %{to: "/ustawienia/konta-bankowe", flash: %{"success" => "Konto bankowe zostało poprawnie połączone."}}}} =
        live(conn, "/ustawienia/bank/dodaj?ref=#{requisition_id}")

      # The AshOban trigger on Requisition will automatically poll for status changes.
      # No manual job insertion needed.
    end
  end
end
