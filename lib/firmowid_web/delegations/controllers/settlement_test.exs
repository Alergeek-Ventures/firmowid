defmodule FirmowidWeb.Delegations.Controllers.SettlementTest do
  @moduledoc false

  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures

  alias Firmowid.Delegations.Delegation
  alias Firmowid.Test.Support.FakeSettlementPdfRenderer

  setup do
    previous_renderer = Application.get_env(:firmowid, :settlement_pdf_renderer)
    Application.put_env(:firmowid, :settlement_pdf_renderer, FakeSettlementPdfRenderer)

    on_exit(fn ->
      if previous_renderer,
        do: Application.put_env(:firmowid, :settlement_pdf_renderer, previous_renderer),
        else: Application.delete_env(:firmowid, :settlement_pdf_renderer)
    end)

    :ok
  end

  test "downloads the prepared settlement PDF for its employee", %{conn: conn} do
    employee = user_fixture()
    delegation = prepared_delegation(employee)

    conn =
      conn
      |> log_in_user(employee)
      |> get("/delegacje/#{delegation.reference}/rozliczenie/pobierz")

    assert response(conn, 200) == "%PDF-1.4 test settlement"
    assert get_resp_header(conn, "content-type") == ["application/pdf"]

    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "Rozliczenie_delegacji_1-2026.pdf"
  end

  test "does not reveal another employee's settlement", %{conn: conn} do
    employee = user_fixture()
    other_employee = user_in_org_fixture(employee.member.organization_id)
    delegation = prepared_delegation(employee)

    conn =
      conn
      |> log_in_user(other_employee)
      |> get("/delegacje/#{delegation.reference}/rozliczenie/pobierz")

    assert response(conn, 404) == "Nie znaleziono rozliczenia."
  end

  defp prepared_delegation(employee) do
    Ash.Seed.seed!(Delegation, %{
      organization_id: employee.member.organization_id,
      member_id: employee.member.id,
      title: "Wyjazd służbowy",
      billing_month: ~D[2026-08-01],
      destination: "Kraków",
      transport_types: [:railway],
      purpose: "Spotkanie z klientem",
      expected_cost: Money.new(:PLN, 100),
      advance_amount: Money.new(:PLN, 50),
      start_date: ~D[2026-08-10],
      end_date: ~D[2026-08-11],
      status: :awaiting_signature,
      settlement_sequence: 1,
      settlement_year: 2026,
      settlement_prepared_at: ~U[2026-08-12 09:00:00Z],
      reference: "PDF-2026-08-1"
    })
  end
end
