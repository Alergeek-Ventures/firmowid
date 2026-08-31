defmodule FirmowidWeb.Delegations.Views.DelegationTest do
  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Scope

  defmodule ReductoClient do
    @moduledoc false

    def extract_file(_path, _schema, _options),
      do: {:ok, %{"document_number" => "FV/2026/001", "expense_amount" => 123.45}}
  end

  setup do
    previous_client = Application.get_env(:firmowid, :reducto_api_client_module)
    previous_enabled = Application.get_env(:firmowid, :delegation_expense_extraction_enabled)
    Application.put_env(:firmowid, :reducto_api_client_module, ReductoClient)
    Application.put_env(:firmowid, :delegation_expense_extraction_enabled, true)

    on_exit(fn ->
      restore_env(:reducto_api_client_module, previous_client)
      restore_env(:delegation_expense_extraction_enabled, previous_enabled)
    end)
  end

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
      Delegations.get_delegation(delegation.id,
        scope: scope,
        load: [transport_expenses: [:trips]]
      )

    assert [%{document_number: "FV/2026/001", expense_amount: expense_amount, trips: [trip]}] =
             delegation.transport_expenses

    assert Money.equal?(expense_amount, Money.new(:PLN, "123.45"))
    assert trip.departure_city == ""
    assert trip.arrival_city == ""
    assert is_nil(trip.departure_datetime)
    assert is_nil(trip.arrival_datetime)
  end

  test "updates a transport trip", %{conn: conn} do
    {view, _html, delegation, scope} = approved_delegation_view(conn)

    upload =
      file_input(view, "#transport-upload-form", :transport, [
        %{name: "bilet.pdf", content: "PDF content", type: "application/pdf"}
      ])

    render_upload(upload, "bilet.pdf")

    {:ok, delegation} =
      Delegations.get_delegation(delegation.id,
        scope: scope,
        load: [transport_expenses: [:trips]]
      )

    [trip] = List.first(delegation.transport_expenses).trips

    assert has_element?(view, "#transport-trip-#{trip.id} th", "Miejscowość")
    assert has_element?(view, "#transport-trip-#{trip.id} th", "Data")
    assert has_element?(view, "#transport-trip-#{trip.id} th", "Godzina")
    refute has_element?(view, "#transport-trip-#{trip.id}", "Trasa")

    view
    |> element("#transport-trip-#{trip.id} button", "Dodaj opis")
    |> render_click()

    assert has_element?(view, "#trip-description-#{trip.id}")

    view
    |> element("#transport-trip-#{trip.id}")
    |> render_change(%{
      "departure_city" => "Warszawa",
      "departure_date" => "2026-08-10",
      "departure_time" => "10:00",
      "arrival_city" => "Gdańsk",
      "arrival_date" => "2026-08-10",
      "arrival_time" => "13:00"
    })

    {:ok, trip} = Delegations.get_delegation_trip(trip.id, scope: scope)

    assert trip.departure_city == "Warszawa"
    assert trip.arrival_city == "Gdańsk"
    assert trip.departure_datetime
    assert trip.arrival_datetime
  end

  test "orders expense fields by document type and keeps the currency next to the amount", %{
    conn: conn
  } do
    {view, _html, _delegation, _scope} = approved_delegation_view(conn)

    for {kind, filename} <- [
          transport: "bilet.pdf",
          accommodation: "nocleg.pdf",
          other: "inne.pdf"
        ] do
      view
      |> file_input("##{kind}-upload-form", kind, [
        %{name: filename, content: "PDF content", type: "application/pdf"}
      ])
      |> render_upload(filename)
    end

    html = render(view)

    assert html =~ ~r/id="transport-transport-type-[^"]+"[\s\S]*id="document-number-[^"]+"/
    assert html =~ ~r/id="accommodation-locality-[^"]+"[\s\S]*id="document-number-[^"]+"/

    assert html =~
             ~r/id="expense-amount-[^"]+"[\s\S]*id="expense-amount-currency-[^"]+"[^>]*class="[^"]*whitespace-nowrap/
  end

  test "leaves unextracted accommodation and other fields blank", %{conn: conn} do
    {view, _html, delegation, scope} = approved_delegation_view(conn)

    view
    |> file_input("#accommodation-upload-form", :accommodation, [
      %{name: "nocleg.pdf", content: "PDF content", type: "application/pdf"}
    ])
    |> render_upload("nocleg.pdf")

    view
    |> file_input("#other-upload-form", :other, [
      %{name: "inne.pdf", content: "PDF content", type: "application/pdf"}
    ])
    |> render_upload("inne.pdf")

    {:ok, delegation} =
      Delegations.get_delegation(delegation.id,
        scope: scope,
        load: [:accommodation_expenses, :other_expenses]
      )

    assert [
             %{
               document_number: "FV/2026/001",
               locality: "",
               arrival_date: nil,
               departure_date: nil
             }
           ] =
             delegation.accommodation_expenses

    assert [%{document_number: "FV/2026/001", description: ""}] = delegation.other_expenses
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
      Delegations.create_delegation(
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
      Delegations.approve_delegation(delegation.id,
        scope: %Scope{actor: admin, tenant: user.organization_id}
      )

    {:ok, _expense} =
      Delegations.create_transport_expense(
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
      Delegations.create_delegation(
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
      Delegations.approve_delegation(delegation.id,
        scope: %Scope{actor: admin, tenant: user.organization_id}
      )

    {:ok, view, html} =
      conn
      |> log_in_user(user)
      |> live(~p"/delegacje/#{delegation.id}")

    {view, html, delegation, scope}
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)
end
