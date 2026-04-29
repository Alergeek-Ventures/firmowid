# credo:disable-for-this-file ExDNA.Credo
# This setup/assertion pattern is intentionally duplicated across feature-level
# integration tests; deduplicating would require shared test helper APIs and
# broader test-structure changes.
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

    test "redirects to company settings with success toast for pending requisition", %{
      conn: conn,
      user: user
    } do
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
                 actor: user
               )

      assert requisition.status == :pending

      # When user returns from GoCardless, they get redirected to company settings
      {:error,
       {:live_redirect,
        %{
          to: "/ustawienia/firma",
          flash: %{"success" => "Konto bankowe zostało poprawnie połączone."}
        }}} =
        live(conn, "/ustawienia/bank/dodaj?ref=#{requisition_id}")

      # The AshOban trigger on Requisition will automatically poll for status changes.
      # No manual job insertion needed.
    end
  end

  describe "institution_selected" do
    setup %{conn: conn} do
      user = Firmowid.AccountsFixtures.admin_fixture()

      Req.Test.stub(:bank_data_institutions, fn conn ->
        Req.Test.json(conn, [
          %{
            id: "N26",
            name: "N26 Bank",
            logo: "https://example.test/n26.svg",
            dominant_color_rgb: "255 255 255",
            transaction_total_days: 90
          }
        ])
      end)

      %{conn: log_in_user(conn, user), user: user}
    end

    test "shows GoCardless confirmation link and persists pending requisition", %{
      conn: conn,
      user: user
    } do
      requisition_id = Ecto.UUID.generate()
      requisition_link = "https://bankaccountdata.gocardless.com/link/#{requisition_id}"

      stub_calls = :counters.new(1, [])

      Req.Test.stub(:bank_data_requisition, fn conn ->
        :counters.add(stub_calls, 1, 1)

        case :counters.get(stub_calls, 1) do
          1 ->
            Req.Test.json(conn, %{id: "agreement-1"})

          2 ->
            Req.Test.json(conn, %{id: requisition_id, link: requisition_link})
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/ustawienia/bank/dodaj")

      view
      |> element("#institution-N26")
      |> render_submit()

      assert has_element?(
               view,
               "a[href='#{requisition_link}']",
               "Kliknij, aby potwierdzić połączenie"
             )

      assert {:ok, requisition} =
               Ash.get(Requisition, requisition_id,
                 tenant: user.organization_id,
                 actor: user
               )

      assert requisition.status == :pending
      assert requisition.id == requisition_id
      assert :counters.get(stub_calls, 1) == 2
    end
  end
end
