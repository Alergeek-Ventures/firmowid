defmodule FirmowidWeb.BankSyncCreateLiveTest do
  use FirmowidWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest

  describe "handle_params with ref enqueues job and redirects" do
    setup %{conn: conn} do
      user = Firmowid.AccountsFixtures.admin_fixture()

      # Stub institutions API for mount
      Req.Test.stub(:bank_data_institutions, fn conn ->
        Req.Test.json(conn, [])
      end)

      %{conn: log_in_user(conn, user), user: user}
    end

    test "enqueues check_requisition_status job", %{conn: conn, user: user} do
      requisition_id = Ecto.UUID.generate()

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:error, {:live_redirect, %{to: "/", flash: %{}}}} =
          live(conn, "/ustawienia/bank/dodaj?ref=#{requisition_id}")

        # assert job was inserted into oban with proper args
        Firmowid.Repo.put_org_id(user.organization_id)

        try do
          job =
            Firmowid.Repo.one(
              from(j in Oban.Job,
                where:
                  fragment("(args->>'name') = ?", "check_requisition_status") and
                    fragment("(args->>'requisition_id') = ?", ^requisition_id),
                select: j
              ),
              oban_jobs: true
            )

          assert job
        after
          Firmowid.Repo.drop_org_id()
        end
      end)
    end
  end
end
