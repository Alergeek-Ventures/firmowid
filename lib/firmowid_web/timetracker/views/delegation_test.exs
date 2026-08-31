defmodule FirmowidWeb.Timetracker.Views.DelegationTest do
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker

  test "renders an approved delegation settlement page", %{conn: conn} do
    {_view, html, _delegation, _scope} = approved_delegation_view(conn)

    assert html =~ "Rozliczenie delegacji"
    assert html =~ "100,00"
  end

  test "adds an expense after its file upload completes", %{conn: conn} do
    {view, _html, delegation, scope} = approved_delegation_view(conn)

    upload =
      file_input(view, "#transport-upload-form", :transport, [
        %{name: "bilet.pdf", content: "PDF content", type: "application/pdf"}
      ])

    render_upload(upload, "bilet.pdf")

    Firmowid.Repo.query!("SET CONSTRAINTS delegation_expense_transport_requires_trip IMMEDIATE")

    assert has_element?(view, "article", "bilet.pdf")

    {:ok, delegation} =
      Timetracker.get_delegation(delegation.id,
        scope: scope,
        load: [transport_expenses: [:trips]]
      )

    assert [%{trips: [%{departure_city: "-", arrival_city: "-"}]}] = delegation.transport_expenses
  end

  test "shows a pending expense while its file uploads", %{conn: conn} do
    {view, _html, _delegation, _scope} = approved_delegation_view(conn)

    view
    |> file_input("#transport-upload-form", :transport, [
      %{name: "bilet.pdf", content: "PDF content", type: "application/pdf"}
    ])
    |> render_upload("bilet.pdf", 50)

    assert has_element?(view, "[id^='transport-pending-expense-']", "bilet.pdf")
  end

  test "removes an existing transport expense", %{conn: conn} do
    user = user_fixture()
    admin = admin_fixture(%{organization_id: user.organization_id})
    scope = %Scope{actor: user, tenant: user.organization_id}

    {:ok, delegation} =
      Timetracker.create_delegation(
        %{
          title: "Wyjazd służbowy",
          billing_month: ~D[2026-08-01],
          purpose: "Spotkanie z klientem",
          advance_payment_amount: Money.new(:PLN, 100),
          start_date: ~D[2026-08-10],
          end_date: ~D[2026-08-11]
        },
        scope: scope
      )

    {:ok, delegation} =
      Timetracker.approve_delegation(delegation.id,
        scope: %Scope{actor: admin, tenant: user.organization_id}
      )

    {:ok, _expense} =
      Timetracker.create_transport_expense(
        %{delegation_id: delegation.id, original_filename: "bilet.pdf", document_number: "-"},
        scope: scope
      )

    {:ok, view, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/delegacje/#{delegation.id}")

    view
    |> element("button[aria-label='Usuń dokument']")
    |> render_click()

    refute has_element?(view, "article", "bilet.pdf")
    refute has_element?(view, "[role='alert']", "Nie udało się usunąć dokumentu.")
  end

  defp approved_delegation_view(conn) do
    user = user_fixture()
    admin = admin_fixture(%{organization_id: user.organization_id})
    scope = %Scope{actor: user, tenant: user.organization_id}

    {:ok, delegation} =
      Timetracker.create_delegation(
        %{
          title: "Wyjazd służbowy",
          billing_month: ~D[2026-08-01],
          purpose: "Spotkanie z klientem",
          advance_payment_amount: Money.new(:PLN, 100),
          start_date: ~D[2026-08-10],
          end_date: ~D[2026-08-11]
        },
        scope: scope
      )

    {:ok, delegation} =
      Timetracker.approve_delegation(delegation.id,
        scope: %Scope{actor: admin, tenant: user.organization_id}
      )

    {:ok, view, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/delegacje/#{delegation.id}")

    {view, html, delegation, scope}
  end
end
