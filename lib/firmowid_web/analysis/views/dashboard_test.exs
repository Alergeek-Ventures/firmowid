defmodule FirmowidWeb.Analysis.Views.DashboardTest do
  # Flags are application config in tests, so this module runs alone.
  use FirmowidWeb.ConnCase, async: false

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Analysis.CounterpartyCategory
  alias Firmowid.Analysis.EntryCategory
  alias Firmowid.Finances.Transaction

  @path "/analiza?od=2026-10-01&do=2026-10-01"

  setup do
    Application.put_env(:firmowid, :enabled_feature_flags, [:analysis_dashboard])
    on_exit(fn -> Application.delete_env(:firmowid, :enabled_feature_flags) end)
  end

  describe "the owner's first review" do
    test "goes through the uncertain counterparties and stores only the owner's choice", %{
      conn: conn
    } do
      admin = admin_fixture()
      # Uncertain counterparties come by amount; an almost sure one is not asked about.
      classified(admin, "Biuro Rachunkowe Nowak", "-9000.00", %{services: 0.9, software: 0.1})
      classified(admin, "Klient Kowalski", "2000.00", %{sales: 0.6, other_income: 0.4})

      classified(admin, "Acme Software", "-5000.00", %{
        software: 0.4,
        marketing: 0.35,
        services: 0.25
      })

      {:ok, view, _html} = conn |> log_in_user(admin) |> live(@path)

      assert has_element?(view, "#analysis-first-review-intro")

      view |> element("#analysis-first-review-start") |> render_click()
      assert has_element?(view, "#analysis-first-review-step-0", "Acme Software")
      assert has_element?(view, "#analysis-first-review-option-marketing")

      view |> element("#analysis-first-review-skip") |> render_click()
      assert has_element?(view, "#analysis-first-review-step-1", "Klient Kowalski")

      view |> element("#analysis-first-review-back") |> render_click()
      assert has_element?(view, "#analysis-first-review-step-0", "Acme Software")
      assert rules(admin) == []

      # Choosing a compartment stores the owner's rule and keeps the counterparty in view.
      view |> element("#analysis-first-review-step-0-marketing") |> render_click()
      assert has_element?(view, "#analysis-first-review-step-0-marketing[aria-pressed=true]")

      assert [
               %{
                 counterparty_name: "Acme Software",
                 category: :marketing,
                 suggested_category: :software
               }
             ] =
               rules(admin)

      view |> element("#analysis-first-review-next") |> render_click()
      assert has_element?(view, "#analysis-first-review-step-1", "Klient Kowalski")

      # Closing keeps the place: the button resumes the review where it was left.
      view |> element("#analysis-first-review-later") |> render_click()
      refute has_element?(view, "#analysis-first-review")

      view |> element("#analysis-first-review-open") |> render_click()
      assert has_element?(view, "#analysis-first-review-step-1", "Klient Kowalski")

      view |> element("#analysis-first-review-back") |> render_click()
      assert has_element?(view, "#analysis-first-review-step-0-marketing[aria-pressed=true]")

      # After the owner's first choice the analysis no longer opens with the review.
      {:ok, view, _html} = conn |> log_in_user(admin) |> live(@path)
      refute has_element?(view, "#analysis-first-review")
    end

    test "is neither offered nor started for members who cannot confirm categories", %{conn: conn} do
      admin = admin_fixture()
      org_id = admin.member.organization_id
      classified(admin, "Acme Software", "-500.00", %{software: 0.4, marketing: 0.35})
      member = user_in_org_fixture(org_id, %{role: :invoicing})

      {:ok, view, _html} = conn |> log_in_user(member) |> live(@path)

      refute has_element?(view, "#analysis-first-review")
      refute has_element?(view, "#analysis-first-review-open")

      render_click(view, "first-review-open", %{})
      refute has_element?(view, "#analysis-first-review")
    end
  end

  # A standalone transfer of the period with the classifier's probability of each category; it
  # chose the likeliest one.
  defp classified(user, counterparty, amount, probabilities) do
    {category, probability} = Enum.max_by(probabilities, &elem(&1, 1))
    org_id = user.member.organization_id
    name = if String.starts_with?(amount, "-"), do: :creditor_name, else: :debtor_name

    transaction =
      Ash.Seed.seed!(
        Transaction,
        Map.put(
          %{
            bank_account_id: bank_account_fixture!(user).id,
            amount: Money.new!(:PLN, amount),
            booking_date: ~D[2026-10-12],
            value_date: ~D[2026-10-12],
            skip_invoicing: true
          },
          name,
          counterparty
        ),
        tenant: org_id
      )

    Ash.Seed.seed!(
      EntryCategory,
      %{
        organization_id: org_id,
        entity_type: :transaction,
        resource_id: transaction.id,
        category: category,
        probability: probability,
        probabilities: Map.new(probabilities, fn {name, p} -> {Atom.to_string(name), p} end)
      },
      tenant: org_id
    )
  end

  defp rules(user),
    do: CounterpartyCategory.list!(scope: %Firmowid.Scope{actor: user, tenant: user.member.organization_id})
end
