defmodule FirmowidWeb.Delegations.Views.DelegationTest do
  @moduledoc false

  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Delegations.Delegation
  alias Firmowid.Ash.Delegations.DelegationExpense
  alias Firmowid.Ash.Invoicing.Services.ReductoApiClientMock
  alias Firmowid.Ash.Scope

  test "renders an approved delegation settlement page", %{conn: conn} do
    user = user_fixture()

    delegation =
      Ash.Seed.seed!(
        Delegation,
        %{
          organization_id: user.organization_id,
          user_id: user.id,
          title: "Wyjazd służbowy",
          billing_month: ~D[2026-08-01],
          destination: "Kraków",
          transport_types: [:railway],
          purpose: "Spotkanie z klientem",
          expected_cost: Money.new(:PLN, 100),
          advance_amount: Money.new(:PLN, 50),
          start_date: ~D[2026-08-10],
          end_date: ~D[2026-08-11],
          status: :in_progress
        },
        tenant: user.organization_id
      )

    {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    assert html =~ "Rozliczenie delegacji"
    assert html =~ "Przejazdy"
    assert html =~ "Nocleg"
  end

  test "renders an in-progress delegation with union-backed expense details", %{conn: conn} do
    user = user_fixture()
    admin = admin_fixture(%{organization_id: user.organization_id})
    scope = %Scope{actor: user, tenant: user.organization_id}

    delegation =
      Delegations.create_delegation!(
        %{
          title: "Wyjazd służbowy",
          billing_month: ~D[2026-08-01],
          destination: "Kraków",
          transport_types: [:railway],
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

    for {kind, details} <- [
          {
            :transport,
            %{
              type: "transport",
              transport_type: :railway,
              trips: [
                %{
                  departure_city: "Wrocław",
                  departure_datetime: ~U[2026-08-10 08:00:00Z],
                  arrival_city: "Kraków",
                  arrival_datetime: ~U[2026-08-10 10:00:00Z]
                }
              ]
            }
          },
          {:accommodation, %{type: "accommodation", locality: "Kraków"}},
          {:other, %{type: "other", description: "Parking"}}
        ] do
      Ash.Seed.seed!(
        DelegationExpense,
        %{
          delegation_id: delegation.id,
          organization_id: user.organization_id,
          kind: kind,
          original_filename: "rachunek.pdf",
          document_number: "FV/1",
          expense_amount: Money.new(:PLN, 100),
          details: details
        },
        tenant: user.organization_id
      )
    end

    {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    assert html =~ "transport-transport-type-"
    assert html =~ "accommodation-locality-"
    assert html =~ "other-description-"
    assert html =~ "trip-departure-city-"
  end

  test "shows form errors instead of crashing when submitting an incomplete settlement", %{
    conn: conn
  } do
    {user, delegation} = approved_delegation()

    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    html = view |> form("#delegation-complete-form", %{delegation: %{}}) |> render_submit()

    assert html =~ "Nie udało się wysłać ewidencji. Uzupełnij wymagane pola."
  end

  test "prefills category-specific expense details from the Reducto mock", %{conn: conn} do
    previous_reducto_config = Application.get_env(:firmowid, :reducto_api_client)

    Application.put_env(
      :firmowid,
      :reducto_api_client,
      upload: [plug: ReductoApiClientMock],
      extract: [plug: ReductoApiClientMock]
    )

    on_exit(fn -> restore_env(:reducto_api_client, previous_reducto_config) end)

    {user, delegation} = approved_delegation()
    upload_fixture = Path.expand("../../../test/fixtures/receipt.png", __DIR__)
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    for kind <- [:transport, :accommodation, :other] do
      view
      |> file_input("##{kind}-upload-form", kind, [
        %{name: "#{kind}.png", content: File.read!(upload_fixture), type: "image/png"}
      ])
      |> render_upload("#{kind}.png")
    end

    html = render(view)

    assert html =~ "Wrocław"
    assert html =~ "Kraków"
    assert html =~ "Studencka 12, Kraków"
    assert html =~ "Polisa ubezpieczeniowa podróży służbowej"
  end

  test "adds and removes a related expense document", %{conn: conn} do
    {user, delegation} = approved_delegation()
    expense = seed_expense(delegation, user)
    upload_fixture = Path.expand("../../../test/fixtures/receipt.png", __DIR__)
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    view |> element("#add-related-document-#{expense.id}") |> render_click()

    view
    |> file_input("#related-document-upload-form", :related_document, [
      %{name: "potwierdzenie.png", content: File.read!(upload_fixture), type: "image/png"}
    ])
    |> render_upload("potwierdzenie.png")

    assert has_element?(view, "a", "potwierdzenie.png")

    view
    |> element("button[aria-label='Usuń potwierdzenie.png']")
    |> render_click()

    refute has_element?(view, "a", "potwierdzenie.png")
  end

  test "completes a seeded valid settlement", %{conn: conn} do
    {user, delegation} = approved_delegation()
    seed_expense(delegation, user)
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    view |> form("#delegation-complete-form") |> render_submit()

    refute has_element?(view, "#delegation-complete-form")
    assert render(view) =~ "REZ/1"
  end

  defp approved_delegation do
    user = user_fixture()
    admin = admin_fixture(%{organization_id: user.organization_id})
    scope = %Scope{actor: user, tenant: user.organization_id}

    delegation =
      Delegations.create_delegation!(
        %{
          title: "Wyjazd służbowy",
          billing_month: ~D[2026-08-01],
          destination: "Kraków",
          transport_types: [:railway],
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

    {user, delegation}
  end

  defp seed_expense(delegation, user) do
    Ash.Seed.seed!(
      DelegationExpense,
      %{
        delegation_id: delegation.id,
        organization_id: user.organization_id,
        kind: :accommodation,
        original_filename: "rezerwacja.pdf",
        document_number: "REZ/1",
        expense_amount: Money.new(:PLN, 250),
        details: %{
          type: "accommodation",
          locality: "Kraków",
          arrival_date: ~D[2026-08-10],
          departure_date: ~D[2026-08-11]
        }
      },
      tenant: user.organization_id
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)
end
