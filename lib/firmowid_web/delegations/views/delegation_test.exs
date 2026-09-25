defmodule FirmowidWeb.Delegations.Views.DelegationTest do
  @moduledoc false

  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Delegations.DelegationExpense
  alias Firmowid.Ash.Invoicing.Services.ReductoApiClientMock
  alias Firmowid.Ash.Scope

  test "renders an approved delegation settlement page", %{conn: conn} do
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
          blob_id: seed_blob(user).id,
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

  test "shows detected date change and requires its reason", %{conn: conn} do
    {user, delegation} = approved_delegation()
    expense = seed_expense(delegation, user)

    {:ok, view, html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    refute html =~ "Zmiana terminu delegacji"

    changed_expense_params = %{
      "expenses" => %{
        "0" => %{
          "_form_type" => "update",
          "id" => expense.id,
          "document_number" => "REZ/1",
          "expense_amount" => "250",
          "details" => %{
            "_union_type" => "accommodation",
            "locality" => "Kraków",
            "arrival_date" => "2026-08-10",
            "departure_date" => "2026-08-12"
          }
        }
      }
    }

    view
    |> form("#delegation-complete-form", %{delegation: changed_expense_params})
    |> render_change()

    html = render(view)

    assert html =~ "Zmiana terminu delegacji"
    assert html =~ "10-11.08.2026"
    assert html =~ "10-12.08.2026"
    assert html =~ "To pole jest wymagane"

    view
    |> form("#delegation-complete-form", %{delegation: changed_expense_params})
    |> render_submit()

    assert_push_event(view, "scroll-to-date-change", %{})

    view
    |> form("#delegation-complete-form", %{
      delegation: Map.put(changed_expense_params, "date_change_reason", "Zmiana biletu")
    })
    |> render_submit()

    assert {:ok, completed_delegation} =
             Delegations.get_delegation(delegation.id,
               scope: %Scope{actor: user, tenant: user.organization_id}
             )

    assert completed_delegation.date_change_reason == "Zmiana biletu"
    assert completed_delegation.detected_end_date == ~D[2026-08-12]
  end

  test "shows foreign currency controls when an expense currency changes", %{conn: conn} do
    {user, delegation} = approved_delegation()
    expense = seed_expense(delegation, user)
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    refute has_element?(view, "#foreign-currency-notice-#{expense.id}")
    assert has_element?(view, "#delegation-complete-form #expense-currency-#{expense.id}")
    refute has_element?(view, "#delegation-complete-form form")
    refute has_element?(view, "#delegation-complete-form button:not([type])")

    view
    |> form("#delegation-complete-form", %{
      "delegation" => %{},
      "expense_currencies" => %{expense.id => "EUR"}
    })
    |> render_change()

    assert has_element?(view, "#foreign-currency-notice-#{expense.id}", "Wykryto obcą walutę")
    assert has_element?(view, "#expense-currency-#{expense.id}.bg-turquoise-100")
    assert has_element?(view, "button", "Mam kwotę z wyciągu")
    assert has_element?(view, "button", "Przelicz wg kursu NBP")

    view |> element("button", "Mam kwotę z wyciągu") |> render_click()

    refute has_element?(view, "#foreign-currency-notice-#{expense.id}")
    assert has_element?(view, "label", "Wyciąg z rachunku")
    assert has_element?(view, "label", "Kwota w PLN")
    assert has_element?(view, "label", "Wgraj dokument")
    assert has_element?(view, "#settlement-currency-#{expense.id}", "PLN")
    refute has_element?(view, "form#settlement-currency-form-#{expense.id}")
    assert has_element?(view, "button", "Mam kwotę z wyciągu")

    view |> element("button", "Mam kwotę z wyciągu") |> render_click()

    assert has_element?(view, "#foreign-currency-notice-#{expense.id}", "Wykryto obcą walutę")
  end

  test "keeps foreign currency form values after uploading a statement", %{conn: conn} do
    {user, delegation} = approved_delegation()
    expense = seed_expense(delegation, user)
    upload_fixture = Path.expand("../../../test/fixtures/receipt.png", __DIR__)
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    params = %{
      "expenses" => %{
        "0" => %{
          "_form_type" => "update",
          "id" => expense.id,
          "document_number" => "REZ/1",
          "expense_amount" => "250",
          "details" => %{
            "_union_type" => "accommodation",
            "locality" => "Kraków",
            "arrival_date" => "2026-08-10",
            "departure_date" => "2026-08-12"
          }
        }
      }
    }

    view
    |> form("#delegation-complete-form", %{
      "delegation" => params,
      "expense_currencies" => %{expense.id => "EUR"}
    })
    |> render_change()

    view
    |> element("#foreign-currency-notice-#{expense.id} button", "Mam kwotę z wyciągu")
    |> render_click()

    view
    |> form("#delegation-complete-form", %{
      "delegation" => put_in(params, ["expenses", "0", "settlement_amount"], "321")
    })
    |> render_change()

    view
    |> file_input("#statement-document-upload-form", :statement_document, [
      %{name: "wyciag.png", content: File.read!(upload_fixture), type: "image/png"}
    ])
    |> render_upload("wyciag.png")

    assert render(view) =~ "321"
    assert has_element?(view, "#accommodation-departure-date-#{expense.id}[value='2026-08-12']")
  end

  test "keeps the settlement editable after sorting expenses", %{conn: conn} do
    {user, delegation} = approved_delegation()

    seed_transport_expense(delegation, user)

    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    view |> element("button", "Sortuj chronologicznie") |> render_click()

    assert has_element?(view, "#delegation-complete-form button[type='submit']", "Wyślij")
  end

  test "keeps both edited transport trip dates", %{conn: conn} do
    {user, delegation} = approved_delegation()

    expense = seed_transport_expense(delegation, user)

    trip = List.first(expense.details.value.trips)
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.id}")

    params = %{
      "expenses" => %{
        "0" => %{
          "_form_type" => "update",
          "id" => expense.id,
          "document_number" => "BIL/1",
          "expense_amount" => "100",
          "details" => %{
            "_union_type" => "transport",
            "transport_type" => "railway",
            "trips" => %{
              "0" => %{
                "_form_type" => "update",
                "id" => trip.id,
                "departure_city" => "Wrocław",
                "departure_date" => "2026-08-09",
                "departure_time" => "08:00",
                "arrival_city" => "Kraków",
                "arrival_date" => "2026-08-12",
                "arrival_time" => "10:00"
              }
            }
          }
        }
      }
    }

    view
    |> form("#delegation-complete-form", %{delegation: params})
    |> render_change()

    assert has_element?(view, "#trip-departure-date-#{trip.id}[value='2026-08-09']")
    assert has_element?(view, "#trip-arrival-date-#{trip.id}[value='2026-08-12']")

    view
    |> form("#delegation-complete-form", %{
      delegation: Map.put(params, "date_change_reason", "Zmiana biletu")
    })
    |> render_submit()

    refute has_element?(view, "#delegation-complete-form button[type='submit']")

    assert {:ok, completed_delegation} =
             Delegations.get_delegation(delegation.id,
               scope: %Scope{actor: user, tenant: user.organization_id},
               load: [:expenses]
             )

    completed_trip =
      completed_delegation.expenses
      |> List.first()
      |> then(& &1.details.value.trips)
      |> List.first()

    assert DateTime.to_date(completed_trip.departure_datetime) == ~D[2026-08-09]
    assert DateTime.to_date(completed_trip.arrival_datetime) == ~D[2026-08-12]
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

    refute has_element?(view, "#delegation-complete-form button[type='submit']")
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
        blob_id: seed_blob(user).id,
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

  defp seed_transport_expense(delegation, user) do
    Ash.Seed.seed!(
      DelegationExpense,
      %{
        delegation_id: delegation.id,
        organization_id: user.organization_id,
        blob_id: seed_blob(user).id,
        kind: :transport,
        original_filename: "bilet.pdf",
        document_number: "BIL/1",
        expense_amount: Money.new(:PLN, 100),
        details: %{
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
      tenant: user.organization_id
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)

  defp seed_blob(user) do
    Ash.Seed.seed!(Blob, %{
      blob_path: "/test/delegations/#{System.unique_integer([:positive])}.pdf",
      blob_checksum: "delegation-#{System.unique_integer([:positive])}",
      original_filename: "rachunek.pdf",
      organization_id: user.organization_id
    })
  end
end
