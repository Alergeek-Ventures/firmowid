defmodule FirmowidWeb.Delegations.Views.DelegationFormTest do
  @moduledoc false
  use FirmowidWeb.ConnCase, async: true

  import Firmowid.AccountsFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Delegations
  alias Firmowid.Ash.Payroll
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  test "renders and validates a delegation", %{conn: conn} do
    employee = user_fixture()
    create_employment_contract(employee)
    {:ok, view, html} = conn |> log_in_user(employee) |> live(~p"/delegacje/dodaj")

    assert html =~ "Planowanie delegacji"
    assert html =~ "Gdy zostanie zaakceptowany otrzymasz maila z potwierdzeniem."
    assert html =~ "Software Developer"
    assert html =~ to_string(employee.email)
    assert html =~ "px-0 pb-12 sm:px-32"
    assert html =~ "grid-cols-1 gap-y-2 sm:grid-cols-[auto_1fr]"
    assert html =~ "flex flex-wrap items-start gap-2"
    assert html =~ ">od</span>"
    assert html =~ ">do</span>"

    invalid_html =
      render_change(view, "validate", %{
        "delegation" =>
          delegation_params(%{
            "end_date" => delegation_start_date() |> Date.add(-1) |> Date.to_iso8601()
          })
      })

    assert invalid_html =~ "nie może być wcześniejsza niż data wyjazdu"
  end

  for transport_type <- ["railway", "airplane", "bus", "public_transport", "other"] do
    test "submits a delegation with #{transport_type}", %{conn: conn} do
      employee = user_fixture()
      scope = %Scope{actor: employee, tenant: employee.organization_id}
      {:ok, view, _html} = conn |> log_in_user(employee) |> live(~p"/delegacje/dodaj")

      view
      |> form("#delegation-form",
        delegation: delegation_params(%{"transport_types" => [unquote(transport_type)]})
      )
      |> render_submit()

      assert_redirect(view, ~p"/ustawienia/profil")

      [delegation] = Delegations.list_delegations_for_user!(employee.id, scope: scope)
      assert delegation.transport_types == [String.to_existing_atom(unquote(transport_type))]
    end
  end

  test "keeps the form live when the billing month is malformed", %{conn: conn} do
    employee = user_fixture()
    {:ok, view, _html} = conn |> log_in_user(employee) |> live(~p"/delegacje/dodaj")

    assert render_hook(view, "change-month", %{"month" => "not-a-date"}) =~
             "Wybierz poprawny miesiąc rozliczeniowy."

    assert render(view) =~ "Planowanie delegacji"
  end

  test "renders without an employment contract", %{conn: conn} do
    employee = user_fixture()
    {:ok, _view, html} = conn |> log_in_user(employee) |> live(~p"/delegacje/dodaj")

    assert html =~ "Stanowisko"
    assert html =~ "—"
  end

  test "adds and removes transport type selects", %{conn: conn} do
    employee = user_fixture()
    {:ok, view, html} = conn |> log_in_user(employee) |> live(~p"/delegacje/dodaj")

    assert html =~ "Miejsce podróży"
    assert html =~ "Środek lokomocji"
    assert html =~ "Wybierz z listy"
    assert html =~ ~r/<option[^>]*value=""[^>]*disabled[^>]*hidden[^>]*>\s*Wybierz z listy/
    assert html =~ "Autobus (z wyłączeniem komunikacji miejskiej)"
    assert html =~ "Komunikacja miejska"
    assert html =~ "+ Dodaj kolejny"

    html = render_click(view, "add_transport_type")
    assert html =~ "delegation_transport_types_1"
    assert html =~ "Usuń środek lokomocji"

    refute render_click(view, "remove_transport_type", %{"index" => "0"}) =~
             "delegation_transport_types_1"
  end

  defp delegation_params(overrides) do
    billing_month = current_billing_month()

    Map.merge(
      %{
        "billing_month" => Date.to_iso8601(billing_month),
        "destination" => "Kraków",
        "transport_types" => ["railway", "bus"],
        "purpose" => "Spotkanie z klientem",
        "advance_payment_amount" => "123.45",
        "start_date" => Date.to_iso8601(delegation_start_date()),
        "end_date" => delegation_start_date() |> Date.add(1) |> Date.to_iso8601()
      },
      overrides
    )
  end

  defp current_billing_month do
    Date.beginning_of_month(Date.utc_today())
  end

  defp delegation_start_date, do: Date.add(Date.utc_today(), 9)

  defp create_employment_contract(employee) do
    blob =
      Ash.Seed.seed!(Blob, %{
        blob_path: "/test/contracts/#{System.unique_integer([:positive])}.pdf",
        blob_checksum: "contract-#{System.unique_integer([:positive])}",
        original_filename: "contract.pdf",
        organization_id: employee.organization_id
      })

    Payroll.create_employment_contract!(
      %{
        starts_at: ~D[2026-01-01],
        salary: Money.new(:PLN, "10000"),
        user_id: employee.id,
        blob_id: blob.id,
        position: "Software Developer"
      },
      scope: %Scope{
        actor: %SystemActor{org_id: employee.organization_id, role: :document_blob_processor},
        tenant: employee.organization_id
      }
    )
  end
end
