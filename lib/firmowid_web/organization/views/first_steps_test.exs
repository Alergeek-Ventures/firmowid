defmodule FirmowidWeb.Organization.Views.FirstStepsTest do
  use FirmowidWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    Cachex.clear!(:institutions)

    Req.Test.stub(:bank_data_institutions, fn conn ->
      Req.Test.json(conn, [
        %{
          id: "N26",
          name: "N26 Bank",
          logo: "https://example.test/n26.svg",
          transaction_total_days: 90
        }
      ])
    end)

    %{conn: log_in_user(conn, Firmowid.AccountsFixtures.admin_fixture())}
  end

  test "keeps the bank step usable when GoCardless cannot create the requisition", %{conn: conn} do
    Req.Test.stub(:bank_data_requisition, &Plug.Conn.send_resp(&1, 500, ""))

    {:ok, view, _html} = live(conn, ~p"/pierwsze-kroki?krok=bank")

    {rendered, _log} =
      ExUnit.CaptureLog.with_log(fn -> view |> element("#institution-N26") |> render_click() end)

    assert rendered =~ "Wystąpił błąd podczas łączenia konta bankowego. Spróbuj ponownie."
    assert has_element?(view, "#institution-N26")
  end
end
