defmodule Firmowid.Taxes.Forecast.DetectionTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Firmowid.Core
  alias Firmowid.Finances.Transaction
  alias Firmowid.InvoicingFixtures
  alias Firmowid.Scope
  alias Firmowid.Taxes

  # Made-up accounts: the NBP part of a payer's ZUS account and of its tax micro-account after the
  # check digits.
  @zus_account "PL12" <> "60000002026" <> "2000123456789"
  @tax_account "PL12" <> "10100071222" <> "2000123456789"

  setup do
    admin = admin_fixture()
    org_id = admin.member.organization_id
    accountant = user_in_org_fixture(org_id, %{role: :accountant})

    %{
      admin: admin,
      org_id: org_id,
      scope: %Scope{actor: admin, tenant: org_id},
      accountant_scope: %Scope{actor: accountant, tenant: org_id},
      bank_account: bank_account_fixture_for_organization!(org_id)
    }
  end

  defp save_year(scope, admin, legal_form, owner) do
    scope.tenant
    |> Core.get_organization!(scope: scope)
    |> Core.update_organization!(%{legal_form: legal_form, is_vat_payer: false}, scope: scope)

    partners =
      if legal_form == :limited_company,
        do: [],
        else: [
          Map.merge(
            %{member_id: admin.member.id, profit_share: 100, voluntary_sickness: false},
            owner
          )
        ]

    company =
      if legal_form == :limited_company,
        do: %{cit_rate: :reduced, cit_advances: :monthly},
        else: %{}

    Taxes.create_tax_year!(Map.merge(%{year: 2026, partners: partners}, company), scope: scope)
  end

  defp owner(income_tax, social_insurance, extra \\ %{}) do
    Map.merge(
      %{
        income_tax: income_tax,
        pit_advances: :monthly,
        social_insurance: social_insurance
      },
      extra
    )
  end

  # Net revenue of 10 000 zł in each of the given months of 2026.
  defp seed_revenue(scope, months) do
    for month <- months do
      date = Date.new!(2026, month, 10)

      InvoicingFixtures.seed_sales_invoice!(
        %{
          invoice_type: :poland,
          invoice_number: "FV/#{month}/2026",
          sale_date: date,
          issue_date: date,
          due_date: Date.add(date, 14),
          payment_method: :transfer,
          currency: "PLN",
          seller_nip: "1234567890",
          seller_display_name: "Acme Sp. z o.o.",
          seller_address: "ul. Testowa 1, 00-001 Warszawa",
          buyer_type: :company,
          buyer_id: "1234567890",
          buyer_full_name: "Buyer Sp. z o.o.",
          buyer_address: "ul. Testowa 2, 00-002 Warszawa",
          buyer_country: "PL",
          ksef_invoice_kind: :vat,
          sales_invoice_items: [
            %{
              name: "Programming service",
              quantity: Decimal.new(1),
              unit: "szt.",
              unit_price: Decimal.new(10_000)
            }
          ]
        },
        scope: scope
      )
    end
  end

  # Synced after the year was saved, which the timestamps tell to the second.
  defp seed_transfer(context, creditor_account, amount, booking_date, title \\ nil) do
    Ash.Seed.seed!(Transaction, %{
      inserted_at: DateTime.shift(DateTime.utc_now(), hour: 1),
      organization_id: context.org_id,
      bank_account_id: context.bank_account.id,
      creditor_account: creditor_account,
      remittance_information_unstructured: title,
      amount: Money.new(:PLN, amount),
      booking_date: booking_date,
      value_date: booking_date
    })
  end

  defp suggestions(scope), do: Map.new(Taxes.suggest_tax_settings!(2026, scope: scope), &{&1.setting, &1})

  test "suggests the ZUS settings whose contributions the payments equal", context do
    %{admin: admin, scope: scope, accountant_scope: accountant_scope} = context
    tax_year = save_year(scope, admin, :sole_proprietorship, owner(:tax_scale, :none))
    seed_revenue(scope, 1..4)

    # Full contributions with sickness: 1 926.76 zł of social ones (pension, disability, accident,
    # sickness, Labour Fund of a 5 652 zł base) and 9% of the previous month's 10 000 zł income less
    # the 1 788.29 zł of social contributions it deducts. The payment of a month pays the month before.
    for date <- [~D[2026-03-16], ~D[2026-04-16], ~D[2026-05-15]],
        do: seed_transfer(context, @zus_account, "-2665.81", date)

    # Read as an accountant, who may not save the year but sees what the forecast sees.
    suggestions = suggestions(accountant_scope)

    assert %{
             social_insurance: %{value: :full, transfers: 3, year: 2026},
             voluntary_sickness: %{value: true}
           } =
             suggestions

    organization = Core.get_organization!(scope.tenant, scope: scope)
    tax_year = Ash.load!(tax_year, :partners, scope: scope)

    assert [:social_insurance, :voluntary_sickness] ==
             suggestions
             |> Map.values()
             |> Taxes.pending_suggestions(tax_year, organization)
             |> Enum.map(& &1.setting)
             |> Enum.sort()
  end

  test "suggests the lump sum rate whose advances the payments equal", context do
    %{admin: admin, scope: scope, accountant_scope: accountant_scope} = context

    tax_year =
      save_year(
        scope,
        admin,
        :sole_proprietorship,
        owner(:lump_sum, :none, %{lump_sum_rate: Decimal.new("12.5")})
      )

    seed_revenue(scope, 1..4)

    # At 12%: 10 000 zł of revenue less half of the 498.35 zł health contribution, rounded to a full
    # złoty, taxed and rounded again gives 1 170 zł; the later advances add the same each month.
    for {number, date} <- [{1, ~D[2026-02-20]}, {2, ~D[2026-03-20]}, {3, ~D[2026-04-20]}],
        do: seed_transfer(context, @tax_account, "-1170", date, "1234567890 26M0#{number} PPE")

    suggestions = suggestions(accountant_scope)

    assert %{lump_sum_rate: %{value: rate, transfers: 3}} = suggestions
    assert Decimal.eq?(rate, 12)

    # The rate is a decimal: 12.5 is saved, so 12 contradicts it.
    organization = Core.get_organization!(scope.tenant, scope: scope)
    tax_year = Ash.load!(tax_year, :partners, scope: scope)

    assert [:lump_sum_rate] ==
             for(
               %{setting: setting} <-
                 Taxes.pending_suggestions(Map.values(suggestions), tax_year, organization),
               do: setting
             )
  end

  test "suggests nothing for payments that match no candidate", context do
    %{admin: admin, scope: scope} = context

    save_year(
      scope,
      admin,
      :sole_proprietorship,
      owner(:lump_sum, :none, %{lump_sum_rate: Decimal.new("12.5")})
    )

    seed_revenue(scope, 1..4)

    for {number, date} <- [{1, ~D[2026-02-20]}, {2, ~D[2026-03-20]}, {3, ~D[2026-04-20]}] do
      seed_transfer(context, @zus_account, "-2500", date)
      seed_transfer(context, @tax_account, "-1000", date, "1234567890 26M0#{number} PPE")
    end

    assert scope |> suggestions() |> Map.keys() |> Enum.sort() == [:income_tax, :pit_advances]
  end

  test "suggests no owner's settings to a limited company", context do
    %{admin: admin, scope: scope} = context
    save_year(scope, admin, :limited_company, %{})
    seed_revenue(scope, 1..4)

    for date <- [~D[2026-03-16], ~D[2026-04-16], ~D[2026-05-15]],
        do: seed_transfer(context, @zus_account, "-2665.81", date)

    refute Enum.any?(
             Taxes.suggest_tax_settings!(2026, scope: scope),
             &(&1.setting in [:social_insurance, :voluntary_sickness, :lump_sum_rate])
           )
  end
end
