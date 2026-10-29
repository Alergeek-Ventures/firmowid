defmodule FirmowidWeb.Delegations.Views.DelegationTest do
  @moduledoc false

  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Blobs.Blob
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
          organization_id: user.member.organization_id,
          member_id: user.member.id,
          title: "Wyjazd służbowy",
          billing_month: ~D[2026-08-01],
          destination: "Kraków",
          transport_types: [:railway],
          purpose: "Spotkanie z klientem",
          expected_cost: Money.new(:PLN, 100),
          advance_amount: Money.new(:PLN, 50),
          start_date: ~D[2026-08-10],
          end_date: ~D[2026-08-11],
          status: :in_progress,
          reference: "UK-2026-08-1"
        },
        tenant: user.member.organization_id
      )

    {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

    assert html =~ "Rozliczenie delegacji"
    assert html =~ "Przejazdy"
    assert html =~ "Nocleg"
  end

  test "employees and administrators can view completed delegations without editing controls", %{
    conn: conn
  } do
    employee = user_fixture()
    admin = admin_fixture(%{organization_id: employee.member.organization_id})

    delegation =
      Ash.Seed.seed!(Delegation, %{
        id: Ash.UUIDv7.generate(),
        organization_id: employee.member.organization_id,
        member_id: employee.member.id,
        title: "Zakończony wyjazd służbowy",
        billing_month: ~D[2026-08-01],
        destination: "Kraków",
        transport_types: [:railway],
        purpose: "Spotkanie z klientem",
        expected_cost: Money.new(:PLN, 100),
        start_date: ~D[2026-08-10],
        end_date: ~D[2026-08-11],
        status: :complete,
        reference: "U-2026-08-1"
      })

    for user <- [employee, admin] do
      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

      assert has_element?(view, "#delegation-settlement-title", "Rozliczenie delegacji")
      refute has_element?(view, "form[id$='-upload-form']")
      refute has_element?(view, "button", "Sortuj chronologicznie")
      refute has_element?(view, "button[phx-click='submit']")
    end
  end

  test "renders an in-progress delegation with union-backed expense details", %{conn: conn} do
    user = user_fixture()
    admin = admin_fixture(%{organization_id: user.member.organization_id})
    scope = %Scope{actor: user, tenant: user.member.organization_id}
    signed_command_path = Briefly.create!(extname: ".pdf")
    File.write!(signed_command_path, "%PDF-1.4 signed command")

    delegation =
      Delegations.create_delegation!(
        %{
          title: "Wyjazd służbowy",
          billing_month: ~D[2026-08-01],
          destination: "Kraków",
          transport_types: [:railway],
          purpose: "Spotkanie z klientem",
          expected_cost: Money.new(:PLN, 100),
          start_date: ~D[2026-08-10],
          end_date: ~D[2026-08-11]
        },
        scope: scope
      )

    {:ok, delegation} =
      Delegations.approve_delegation(
        delegation.id,
        %{
          advance_amount: Money.new(:PLN, 0),
          signed_command_filename: "polecenie.pdf",
          upload_path: signed_command_path,
          content_type: "application/pdf"
        },
        scope: %Scope{actor: admin, tenant: user.member.organization_id}
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
          organization_id: user.member.organization_id,
          blob_id: seed_blob(user).id,
          kind: kind,
          original_filename: "rachunek.pdf",
          document_number: "FV/1",
          expense_amount: Money.new(:PLN, 100),
          details: details
        },
        tenant: user.member.organization_id
      )
    end

    {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

    assert html =~ "transport-transport-type-"
    assert html =~ "accommodation-locality-"
    assert html =~ "other-description-"
    assert html =~ "trip-departure-city-"
  end

  test "shows form errors instead of crashing when submitting an incomplete settlement", %{
    conn: conn
  } do
    {user, delegation} = approved_delegation()

    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

    html = view |> form("#delegation-complete-form", %{delegation: %{}}) |> render_submit()

    assert html =~ "Nie udało się wysłać ewidencji. Uzupełnij wymagane pola."
  end

  test "shows detected date change and requires its reason", %{conn: conn} do
    {user, delegation} = approved_delegation()
    expense = seed_expense(delegation, user)

    {:ok, view, html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

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
               scope: %Scope{actor: user, tenant: user.member.organization_id}
             )

    assert completed_delegation.date_change_reason == "Zmiana biletu"
    assert completed_delegation.detected_end_date == ~D[2026-08-12]
  end

  test "autosaves document fields and reads them back without completing the delegation", %{
    conn: conn
  } do
    {user, delegation} = approved_delegation()
    expense = seed_expense(delegation, user)
    conn = log_in_user(conn, user)
    path = ~p"/delegacje/#{delegation.reference}"
    {:ok, view, _html} = live(conn, path)

    view
    |> form("#delegation-complete-form", %{
      delegation: %{
        expenses: %{
          "0" => %{
            document_number: "HOTEL/POPRAWIONY",
            expense_amount: "345.67",
            details: %{locality: "Warszawa"}
          }
        }
      }
    })
    |> render_change()

    persisted =
      Delegations.get_delegation!(delegation.id,
        scope: %Scope{actor: user, tenant: user.member.organization_id},
        load: [:expenses]
      )

    assert persisted.status == :in_progress
    assert [saved] = persisted.expenses
    assert saved.document_number == "HOTEL/POPRAWIONY"
    assert Money.equal?(saved.expense_amount, Money.new(:PLN, "345.67"))
    assert saved.details.value.locality == "Warszawa"
    assert has_element?(view, "#delegation-save-status", "Zmiany zostały zapisane")

    {:ok, reopened, _html} = live(conn, path)
    assert has_element?(reopened, "#document-number-#{expense.id}[value='HOTEL/POPRAWIONY']")
    assert has_element?(reopened, "#accommodation-locality-#{expense.id}[value='Warszawa']")

    reopened
    |> form("#delegation-complete-form", %{
      delegation: %{expenses: %{"0" => %{expense_amount: ""}}}
    })
    |> render_change()

    assert has_element?(reopened, "#delegation-save-status", "Nie zapisano")
    assert has_element?(reopened, "#expense-amount-#{expense.id}:not([value])")

    assert Money.equal?(
             Delegations.get_expense!(expense.id,
               scope: %Scope{actor: user, tenant: user.member.organization_id}
             ).expense_amount,
             Money.new(:PLN, "345.67")
           )
  end

  test "keeps partial date and time drafts until both parts are valid, including after sorting",
       %{conn: conn} do
    {user, delegation} = approved_delegation()
    expense = seed_transport_expense(delegation, user, %{departure_datetime: nil})
    trip = hd(expense.details.value.trips)
    conn = log_in_user(conn, user)
    path = ~p"/delegacje/#{delegation.reference}"
    {:ok, view, _} = live(conn, path)
    scope = %Scope{actor: user, tenant: user.member.organization_id}

    change_trip(view, %{departure_date: "2026-03-", departure_time: ""})
    assert has_element?(view, "#trip-departure-date-#{trip.id}[value='2026-03-']")
    assert has_element?(view, "#trip-departure-hint-#{trip.id}", "Uzupełnij pełną datę")
    assert has_element?(view, "#delegation-save-status", "Nie zapisano")

    assert hd(Delegations.get_expense!(expense.id, scope: scope).details.value.trips).departure_local_datetime ==
             nil

    view |> element("button", "Sortuj chronologicznie") |> render_click()
    assert has_element?(view, "#trip-departure-date-#{trip.id}[value='2026-03-']")
    change_trip(view, %{departure_date: "2026-03-29"})
    assert has_element?(view, "#trip-departure-date-#{trip.id}[aria-invalid='false']")
    assert has_element?(view, "#trip-departure-time-#{trip.id}[aria-invalid='true']")
    change_trip(view, %{departure_time: "02:30"})

    assert hd(Delegations.get_expense!(expense.id, scope: scope).details.value.trips).departure_local_datetime ==
             ~N[2026-03-29 02:30:00]

    {:ok, view, _} = live(conn, path)
    assert has_element?(view, "#trip-departure-date-#{trip.id}[value='2026-03-29']")
    assert has_element?(view, "#trip-departure-time-#{trip.id}[value='02:30']")

    change_trip(view, %{departure_date: "", departure_time: ""})
    change_trip(view, %{departure_time: "02:45"})
    assert has_element?(view, "#trip-departure-time-#{trip.id}[value='02:45']")
    assert has_element?(view, "#delegation-save-status", "Nie zapisano")
    change_trip(view, %{departure_date: "2026-10-25"})
    {:ok, reopened, _} = live(conn, path)
    assert has_element?(reopened, "#trip-departure-time-#{trip.id}[value='02:45']")
    assert has_element?(reopened, "#trip-departure-date-#{trip.id}[value='2026-10-25']")
  end

  test "reports a rejected save and keeps the draft when a delegation is no longer editable", %{
    conn: conn
  } do
    {user, delegation} = approved_delegation()
    expense = seed_expense(delegation, user)
    {:ok, view, _} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")
    Ash.Seed.update!(delegation, %{status: :complete})

    view
    |> form("#delegation-complete-form", %{
      delegation: %{expenses: %{"0" => %{document_number: "NIEZAPISANY"}}}
    })
    |> render_change()

    assert has_element?(view, "#delegation-save-status", "Zapis nie powiódł się")
    refute has_element?(view, "#delegation-save-status", "Zmiany zostały zapisane")
    assert has_element?(view, "#document-number-#{expense.id}[value='NIEZAPISANY']")

    assert Delegations.get_expense!(expense.id,
             scope: %Scope{actor: user, tenant: user.member.organization_id}
           ).document_number == "REZ/1"
  end

  test "preserves both DST occurrences and legacy instants on unrelated edits and clears stale UTC on clock edits",
       %{conn: conn} do
    for {local, utc} <- [
          {~N[2026-10-25 02:30:00], ~U[2026-10-25 00:30:00Z]},
          {~N[2026-10-25 02:30:00], ~U[2026-10-25 01:30:00Z]},
          {nil, ~U[2026-10-25 01:30:00Z]}
        ] do
      {user, delegation} = approved_delegation()

      expense =
        seed_transport_expense(delegation, user, %{
          departure_local_datetime: local,
          departure_datetime: utc,
          arrival_local_datetime: ~N[2026-10-25 04:30:00],
          arrival_datetime: ~U[2026-10-25 03:30:00Z]
        })

      trip = hd(expense.details.value.trips)
      scope = %Scope{actor: user, tenant: user.member.organization_id}
      conn = log_in_user(conn, user)
      path = ~p"/delegacje/#{delegation.reference}"
      {:ok, view, _} = live(conn, path)

      view
      |> form("#delegation-complete-form", %{
        delegation: %{expenses: %{"0" => %{document_number: "BIL/2"}}}
      })
      |> render_change()

      stored = hd(Delegations.get_expense!(expense.id, scope: scope).details.value.trips)
      assert stored.departure_local_datetime == local
      assert stored.departure_datetime == utc

      change_trip(view, %{departure_time: "02:45"})
      stored = hd(Delegations.get_expense!(expense.id, scope: scope).details.value.trips)
      assert stored.departure_local_datetime == ~N[2026-10-25 02:45:00]
      assert stored.departure_datetime == nil
      {:ok, reopened, _} = live(conn, path)
      assert has_element?(reopened, "#trip-departure-time-#{trip.id}[value='02:45']")
    end
  end

  test "shows foreign currency controls when an expense currency changes", %{conn: conn} do
    {user, delegation} = approved_delegation()
    expense = seed_expense(delegation, user)
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

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
    assert has_element?(view, "#expense-currency-#{expense.id}.bg-teal-100")
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
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

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

  test "keeps rows in place while editing after an explicit sort", %{conn: conn} do
    {user, delegation} = approved_delegation()

    first = seed_transport_expense(delegation, user)

    second =
      seed_transport_expense(delegation, user, %{
        departure_datetime: ~U[2026-08-11 08:00:00Z],
        arrival_datetime: ~U[2026-08-11 10:00:00Z]
      })

    first_trip = hd(first.details.value.trips)
    second_trip = hd(second.details.value.trips)

    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

    view |> element("button", "Sortuj chronologicznie") |> render_click()

    assert has_element?(view, "#delegation-complete-form button[type='submit']", "Wyślij")
    change_trip(view, %{departure_date: "2026-08-12", arrival_date: "2026-08-12"})
    assert render(view) =~ ~r/transport-trip-#{first_trip.id}.*transport-trip-#{second_trip.id}/s
  end

  test "keeps both edited transport trip dates", %{conn: conn} do
    {user, delegation} = approved_delegation()

    expense = seed_transport_expense(delegation, user)

    trip = List.first(expense.details.value.trips)
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

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
               scope: %Scope{actor: user, tenant: user.member.organization_id},
               load: [:expenses]
             )

    completed_trip =
      completed_delegation.expenses
      |> List.first()
      |> then(& &1.details.value.trips)
      |> List.first()

    assert completed_trip.departure_local_datetime == ~N[2026-08-09 08:00:00]
    assert completed_trip.arrival_local_datetime == ~N[2026-08-12 10:00:00]
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
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

    for kind <- [:transport, :accommodation, :other] do
      view
      |> file_input("##{kind}-upload-form", kind, [
        %{name: "#{kind}.png", content: File.read!(upload_fixture), type: "image/png"}
      ])
      |> render_upload("#{kind}.png")

      if kind == :transport do
        change_trip(view, %{departure_date: "2026-08-", departure_time: "08:15"})
      end
    end

    html = render(view)

    assert html =~ "Wrocław"
    assert html =~ "Kraków"
    assert html =~ "Studencka 12, Kraków"
    assert html =~ "Polisa ubezpieczeniowa podróży służbowej"
    assert has_element?(view, "input[id^='trip-departure-date-'][value='2026-08-']")

    view
    |> element("button[phx-click='delete'][phx-value-kind='accommodation']")
    |> render_click()

    assert has_element?(view, "input[id^='trip-departure-date-'][value='2026-08-']")
    refute has_element?(view, "input[id^='accommodation-locality-']")
  end

  test "adds and removes a related expense document", %{conn: conn} do
    {user, delegation} = approved_delegation()
    expense = seed_expense(delegation, user)
    upload_fixture = Path.expand("../../../test/fixtures/receipt.png", __DIR__)
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

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

  test "does not persist client-supplied NBP values without a server calculation", %{conn: conn} do
    {user, delegation} = approved_delegation()
    expense = seed_expense(delegation, user)
    scope = %Scope{actor: user, tenant: user.member.organization_id}
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

    params = %{
      "delegation" => %{
        "expenses" => %{
          "0" => %{
            "_form_type" => "update",
            "id" => expense.id,
            "document_number" => "REZ/1",
            "expense_amount" => "10",
            "settlement_method" => "nbp",
            "settlement_amount" => "999",
            "settlement_currency" => "PLN",
            "nbp_rate" => "99.9",
            "nbp_rate_date" => "2026-08-10",
            "details" => %{
              "_union_type" => "accommodation",
              "locality" => "Kraków",
              "arrival_date" => "2026-08-10",
              "departure_date" => "2026-08-11"
            }
          }
        }
      },
      "expense_currencies" => %{expense.id => "EUR"}
    }

    render_submit(view, "submit", params)

    persisted = Delegations.get_delegation!(delegation.id, scope: scope, load: [:expenses])
    assert persisted.status == :in_progress
    assert [%{settlement_amount: nil, nbp_rate: nil, nbp_rate_date: nil}] = persisted.expenses

    previous_options = Application.get_env(:firmowid, :nbp_api_request_options)
    cache_key = {:nbp_rate, "EUR", Date.add(Date.utc_today(), -1)}
    Cachex.del(:currencies, cache_key)
    Application.put_env(:firmowid, :nbp_api_request_options, plug: {Req.Test, __MODULE__})

    on_exit(fn ->
      restore_env(:nbp_api_request_options, previous_options)
      Cachex.del(:currencies, cache_key)
    end)

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "rates" => [%{"effectiveDate" => "2026-08-10", "mid" => 4.0, "no" => "test-rate"}]
      })
    end)

    render_change(view, "validate", params)
    view |> element("button", "Przelicz wg kursu NBP") |> render_click()
    settled_draft = Delegations.get_expense!(expense.id, scope: scope)
    assert settled_draft.settlement_method == :nbp
    assert Money.equal?(settled_draft.settlement_amount, Money.new!(:PLN, 40))
    render_submit(view, "submit", params)

    completed = Delegations.get_delegation!(delegation.id, scope: scope, load: [:expenses])
    assert completed.status == :complete
    assert [settled] = completed.expenses
    assert Money.equal?(settled.settlement_amount, Money.new!(:PLN, 40))
    assert Decimal.eq?(settled.nbp_rate, Decimal.new(4))
  end

  test "binds an NBP calculation to the submitted amount and source currency", %{conn: conn} do
    previous_options = Application.get_env(:firmowid, :nbp_api_request_options)
    cache_key = {:nbp_rate, "EUR", Date.add(Date.utc_today(), -1)}
    Cachex.del(:currencies, cache_key)
    Application.put_env(:firmowid, :nbp_api_request_options, plug: {Req.Test, __MODULE__})

    on_exit(fn ->
      restore_env(:nbp_api_request_options, previous_options)
      Cachex.del(:currencies, cache_key)
    end)

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "rates" => [%{"effectiveDate" => "2026-08-10", "mid" => 4.0, "no" => "test-rate"}]
      })
    end)

    results =
      for submitted_currency <- ["EUR", "USD"] do
        {user, delegation} = approved_delegation()
        expense = seed_expense(delegation, user)
        scope = %Scope{actor: user, tenant: user.member.organization_id}

        {:ok, view, _html} =
          conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

        params = %{
          "delegation" => %{
            "expenses" => %{
              "0" => %{
                "_form_type" => "update",
                "id" => expense.id,
                "document_number" => "REZ/1",
                "expense_amount" => "100",
                "details" => %{
                  "_union_type" => "accommodation",
                  "locality" => "Kraków",
                  "arrival_date" => "2026-08-10",
                  "departure_date" => "2026-08-11"
                }
              }
            }
          },
          "expense_currencies" => %{expense.id => "EUR"}
        }

        view |> form("#delegation-complete-form", params) |> render_change()
        view |> element("button", "Przelicz wg kursu NBP") |> render_click()

        submitted =
          params
          |> put_in(["delegation", "expenses", "0", "expense_amount"], "10")
          |> put_in(["expense_currencies", expense.id], submitted_currency)

        view |> form("#delegation-complete-form", submitted) |> render_change()

        if submitted_currency == "USD" do
          {:ok, reopened, _} =
            conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

          assert has_element?(reopened, "#foreign-currency-notice-#{expense.id}")
          saved = Delegations.get_expense!(expense.id, scope: scope)
          assert saved.settlement_method == nil
          assert saved.nbp_rate == nil
          assert saved.nbp_rate_date == nil
        end

        view |> form("#delegation-complete-form", submitted) |> render_submit()

        persisted = Delegations.get_delegation!(delegation.id, scope: scope, load: [:expenses])
        [expense] = persisted.expenses

        amount =
          if expense.settlement_amount do
            expense.settlement_amount
            |> Money.to_decimal()
            |> Decimal.normalize()
            |> Decimal.to_string(:normal)
          end

        {persisted.status, amount}
      end

    assert results == [{:complete, "40"}, {:in_progress, nil}]
  end

  test "completes a seeded valid settlement", %{conn: conn} do
    {user, delegation} = approved_delegation()
    seed_expense(delegation, user)
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/delegacje/#{delegation.reference}")

    view |> form("#delegation-complete-form") |> render_submit()

    refute has_element?(view, "#delegation-complete-form button[type='submit']")
    assert render(view) =~ "REZ/1"
  end

  defp approved_delegation do
    user = user_fixture()
    admin = admin_fixture(%{organization_id: user.member.organization_id})
    scope = %Scope{actor: user, tenant: user.member.organization_id}
    signed_command_path = Briefly.create!(extname: ".pdf")
    File.write!(signed_command_path, "%PDF-1.4 signed command")

    delegation =
      Delegations.create_delegation!(
        %{
          title: "Wyjazd służbowy",
          billing_month: ~D[2026-08-01],
          destination: "Kraków",
          transport_types: [:railway],
          purpose: "Spotkanie z klientem",
          expected_cost: Money.new(:PLN, 100),
          start_date: ~D[2026-08-10],
          end_date: ~D[2026-08-11]
        },
        scope: scope
      )

    {:ok, delegation} =
      Delegations.approve_delegation(
        delegation.id,
        %{
          signed_command_filename: "polecenie.pdf",
          upload_path: signed_command_path,
          content_type: "application/pdf"
        },
        scope: %Scope{actor: admin, tenant: user.member.organization_id}
      )

    {user, delegation}
  end

  defp seed_expense(delegation, user) do
    Ash.Seed.seed!(
      DelegationExpense,
      %{
        delegation_id: delegation.id,
        organization_id: user.member.organization_id,
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
      tenant: user.member.organization_id
    )
  end

  defp change_trip(view, fields) do
    view
    |> form("#delegation-complete-form", %{
      delegation: %{expenses: %{"0" => %{details: %{trips: %{"0" => fields}}}}}
    })
    |> render_change()
  end

  defp seed_transport_expense(delegation, user, trip_attributes \\ %{}) do
    Ash.Seed.seed!(
      DelegationExpense,
      %{
        delegation_id: delegation.id,
        organization_id: user.member.organization_id,
        blob_id: seed_blob(user).id,
        kind: :transport,
        original_filename: "bilet.pdf",
        document_number: "BIL/1",
        expense_amount: Money.new(:PLN, 100),
        details: %{
          type: "transport",
          transport_type: :railway,
          trips: [
            Map.merge(
              %{
                departure_city: "Wrocław",
                departure_datetime: ~U[2026-08-10 08:00:00Z],
                arrival_city: "Kraków",
                arrival_datetime: ~U[2026-08-10 10:00:00Z]
              },
              trip_attributes
            )
          ]
        }
      },
      tenant: user.member.organization_id
    )
  end

  defp restore_env(key, nil), do: Application.delete_env(:firmowid, key)
  defp restore_env(key, value), do: Application.put_env(:firmowid, key, value)

  defp seed_blob(user) do
    Ash.Seed.seed!(Blob, %{
      blob_path: "/test/delegations/#{System.unique_integer([:positive])}.pdf",
      blob_checksum: "delegation-#{System.unique_integer([:positive])}",
      original_filename: "rachunek.pdf",
      organization_id: user.member.organization_id
    })
  end
end
