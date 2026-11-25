defmodule Firmowid.TaxesTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Ash.Error.Forbidden
  alias Ash.Error.Invalid
  alias Firmowid.Analysis.EntryCategory
  alias Firmowid.Core
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.InvoicingFixtures
  alias Firmowid.Taxes
  alias Firmowid.Taxes.Partner
  alias Firmowid.Taxes.TaxYear

  # A made-up tax micro-account: the NBP part 10100071222 after the check digits.
  @tax_account "PL12101000712222000123456789"

  setup do
    admin = admin_fixture()
    org_id = admin.member.organization_id
    scope = %Firmowid.Scope{actor: admin, tenant: org_id}

    %{admin: admin, org_id: org_id, scope: scope}
  end

  defp set_legal_form(scope, legal_form, is_vat_payer \\ true) do
    scope.tenant
    |> Core.get_organization!(scope: scope)
    |> Core.update_organization!(%{legal_form: legal_form, is_vat_payer: is_vat_payer},
      scope: scope
    )
  end

  defp partner(member_id, profit_share) do
    %{
      member_id: member_id,
      profit_share: profit_share,
      income_tax: :flat_tax,
      pit_advances: :monthly,
      social_insurance: :full,
      voluntary_sickness: false
    }
  end

  describe "saving a tax year" do
    test "only an admin saves it", %{admin: admin, org_id: org_id, scope: scope} do
      set_legal_form(scope, :sole_proprietorship)
      accountant = user_in_org_fixture(org_id, %{role: :accountant})
      accountant_scope = %Firmowid.Scope{actor: accountant, tenant: org_id}

      assert {:error, %Forbidden{}} =
               Taxes.create_tax_year(
                 %{year: 2026, vat_period: :monthly, partners: [partner(admin.member.id, 100)]},
                 scope: accountant_scope
               )

      assert {:ok, _tax_year} =
               Taxes.create_tax_year(
                 %{year: 2026, vat_period: :monthly, partners: [partner(admin.member.id, 100)]},
                 scope: scope
               )
    end

    test "rejects a partner from another organization", %{scope: scope} do
      set_legal_form(scope, :sole_proprietorship)
      outsider = admin_fixture()

      assert {:error, %Invalid{}} =
               Taxes.create_tax_year(
                 %{
                   year: 2026,
                   vat_period: :monthly,
                   partners: [partner(outsider.member.id, 100)]
                 },
                 scope: scope
               )

      assert Taxes.list_tax_years!(%{}, scope: scope) == []
    end

    test "requires the partners of the legal form to share the whole profit", %{
      admin: admin,
      org_id: org_id,
      scope: scope
    } do
      set_legal_form(scope, :civil_partnership)
      other = user_in_org_fixture(org_id)

      assert {:error, %Invalid{} = error} =
               Taxes.create_tax_year(
                 %{
                   year: 2026,
                   vat_period: :monthly,
                   partners: [partner(admin.member.id, 60), partner(other.member.id, 30)]
                 },
                 scope: scope
               )

      assert Exception.message(error) =~ "add up to 100%"

      assert {:error, %Invalid{}} =
               Taxes.create_tax_year(
                 %{year: 2026, vat_period: :monthly, partners: [partner(admin.member.id, 100)]},
                 scope: scope
               )

      # The failed saves leave neither the year nor its partners behind.
      assert Taxes.list_tax_years!(%{}, scope: scope) == []
      assert Partner.read!(scope: scope) == []

      assert {:ok, _tax_year} =
               Taxes.create_tax_year(
                 %{
                   year: 2026,
                   vat_period: :monthly,
                   partners: [partner(admin.member.id, 60), partner(other.member.id, 40)]
                 },
                 scope: scope
               )
    end
  end

  describe "suggest_tax_settings/2" do
    test "reads the period and form of the transfers to the tax micro-account", %{
      org_id: org_id,
      scope: scope
    } do
      bank_account = bank_account_fixture_for_organization!(org_id)

      transfer = fn creditor_account, title ->
        Ash.Seed.seed!(Transaction, %{
          organization_id: org_id,
          bank_account_id: bank_account.id,
          creditor_account: creditor_account,
          remittance_information_unstructured: title,
          amount: Money.new(:PLN, "-500"),
          booking_date: ~D[2026-03-20],
          value_date: ~D[2026-03-20]
        })
      end

      transfer.(@tax_account, "1234567890 26M01 PPE")
      transfer.(@tax_account, "/TI/N1234567890/OKR/26M02/SFP/PPE/")
      transfer.(@tax_account, "1234567890 26K01 VAT-7K")
      # The company's withholding for its employees, not the owner's income tax.
      transfer.(@tax_account, "PIT-4 26M02")
      # Not the tax micro-account.
      transfer.("PL61109010140000071219812874", "1234567890 26M02 PPL")

      suggestions = Map.new(Taxes.suggest_tax_settings!(2026, scope: scope), &{&1.setting, &1})

      assert %{
               vat_period: %{value: :quarterly},
               income_tax: %{value: :lump_sum, transfers: 2},
               pit_advances: %{value: :monthly}
             } = suggestions

      refute Map.has_key?(suggestions, :cit_advances)
    end

    test "reads periods that banks write out in the title", %{org_id: org_id, scope: scope} do
      bank_account = bank_account_fixture_for_organization!(org_id)

      for title <- [
            "CIT-8 K 02 2026",
            "CIT-8 K 03 2026",
            "VAT M 09 2026",
            "PIT-4 M 09 2026",
            "urząd skarbowy, CIT-8 04 K - NIP 1234567890 - Kwartał 2025"
          ] do
        Ash.Seed.seed!(Transaction, %{
          organization_id: org_id,
          bank_account_id: bank_account.id,
          creditor_account: @tax_account,
          remittance_information_unstructured: title,
          amount: Money.new(:PLN, "-500"),
          booking_date: ~D[2026-10-20],
          value_date: ~D[2026-10-20]
        })
      end

      assert [
               %{setting: :vat_period, value: :monthly, year: 2026, transfers: 1},
               %{setting: :cit_advances, value: :quarterly, year: 2026, transfers: 2}
             ] =
               Enum.sort_by(
                 Taxes.suggest_tax_settings!(2026, scope: scope),
                 &(&1.setting != :vat_period)
               )

      assert [%{setting: :cit_advances, value: :quarterly, year: 2025, transfers: 1}] =
               Taxes.suggest_tax_settings!(2025, scope: scope)
    end
  end

  describe "forecast_taxes/2" do
    defp seed_sales(scope, attrs, unit_price) do
      InvoicingFixtures.seed_sales_invoice!(
        Map.merge(
          %{
            invoice_type: :poland,
            invoice_number: "FV/#{System.unique_integer([:positive])}",
            sale_date: ~D[2026-01-10],
            issue_date: ~D[2026-01-10],
            due_date: ~D[2026-01-24],
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
                unit_price: unit_price
              }
            ]
          },
          attrs
        ),
        scope: scope
      )
    end

    defp create_company_tax_year(scope) do
      set_legal_form(scope, :limited_company)

      Taxes.create_tax_year!(
        %{
          year: 2026,
          vat_period: :monthly,
          cit_rate: :reduced,
          cit_advances: :quarterly,
          partners: []
        },
        scope: scope
      )
    end

    test "counts invoices, corrections and cost invoices in their months, per organization", %{
      scope: scope
    } do
      create_company_tax_year(scope)

      invoice = seed_sales(scope, %{}, Decimal.new("1000"))

      seed_sales(
        scope,
        %{
          ksef_invoice_kind: :kor,
          corrected_invoice_id: invoice.id,
          sale_date: ~D[2026-02-10],
          issue_date: ~D[2026-02-10]
        },
        Decimal.new("600")
      )

      Ash.Seed.seed!(
        CostInvoice,
        %{
          seller: "Supplier Sp. z o.o.",
          seller_display_name: "Supplier Sp. z o.o.",
          sale_date: ~D[2026-01-12],
          issue_date: ~D[2026-01-12],
          due_date: ~D[2026-01-26],
          amount: Money.new!(:PLN, "-123.00"),
          vat_amount: Decimal.new("23"),
          description: "Services",
          invoice_identifier: "FV/1/2026",
          organization_id: scope.tenant
        },
        tenant: scope.tenant
      )

      # Another organization's invoice must not change this forecast.
      other = admin_fixture()
      other_scope = %Firmowid.Scope{actor: other, tenant: other.member.organization_id}
      seed_sales(other_scope, %{}, Decimal.new("5000"))

      assert {:ok, forecasts} = Taxes.forecast_taxes(2026, scope: scope)
      vat = Enum.filter(forecasts, &(&1.kind == :vat))
      assert length(vat) == 12

      [january, february | _] = vat

      # 1000 net at 23% less 23 of input VAT.
      assert %{kind: :vat, period: "2026-01", due_date: ~D[2026-02-25]} = january
      assert Decimal.equal?(january.amount, 207)
      assert Decimal.equal?(january.details.output_vat, 230)
      assert Decimal.equal?(january.details.input_vat, 23)

      # The correction lowers the VAT from 230 to 138 in the month it is issued: 92 less.
      assert %{kind: :vat, period: "2026-02", due_date: ~D[2026-03-25]} = february
      assert Decimal.equal?(february.amount, 0)
      assert Decimal.equal?(february.details.output_vat, -92)
      assert Decimal.equal?(february.details.input_vat, 0)
    end

    test "forecasts the CIT advance of a limited company from net revenue and costs", %{
      scope: scope
    } do
      create_company_tax_year(scope)

      seed_sales(scope, %{}, Decimal.new("10000"))

      Ash.Seed.seed!(
        CostInvoice,
        %{
          seller: "Supplier Sp. z o.o.",
          seller_display_name: "Supplier Sp. z o.o.",
          sale_date: ~D[2026-01-12],
          issue_date: ~D[2026-01-12],
          due_date: ~D[2026-01-26],
          amount: Money.new!(:PLN, "-1230.00"),
          vat_amount: Decimal.new("230"),
          description: "Services",
          invoice_identifier: "FV/2/2026",
          organization_id: scope.tenant
        },
        tenant: scope.tenant
      )

      assert {:ok, forecasts} = Taxes.forecast_taxes(2026, scope: scope)
      assert [first_quarter | _] = cit = Enum.filter(forecasts, &(&1.kind == :cit))
      assert length(cit) == 4

      # 10 000 of revenue less 1 000 of costs is taxed at 9%.
      assert %{period: "2026-Q1", due_date: ~D[2026-04-20]} = first_quarter
      assert Decimal.equal?(first_quarter.amount, 810)
      assert Decimal.equal?(first_quarter.details.income, 9000)
      assert first_quarter.details.cost_invoices_without_vat == 0
    end

    test "counts a skipped outgoing transfer as a CIT cost only when the analysis categorized it",
         %{
           org_id: org_id,
           scope: scope
         } do
      create_company_tax_year(scope)
      seed_sales(scope, %{}, Decimal.new("10000"))
      bank_account = bank_account_fixture_for_organization!(org_id)

      transfer = fn name ->
        Ash.Seed.seed!(Transaction, %{
          organization_id: org_id,
          bank_account_id: bank_account.id,
          creditor_name: name,
          remittance_information_unstructured: "Payment",
          amount: Money.new!(:PLN, "-1000"),
          booking_date: ~D[2026-01-15],
          value_date: ~D[2026-01-15],
          skip_invoicing: true
        })
      end

      first_quarter = fn ->
        {:ok, forecasts} = Taxes.forecast_taxes(2026, scope: scope)
        Enum.find(forecasts, &(&1.kind == :cit and &1.period == "2026-Q1"))
      end

      classified = transfer.("Acme Hosting")
      transfer.("Acme Exchange")

      # Neither transfer is classified: no costs.
      assert Decimal.equal?(first_quarter.().details.costs, 0)

      Ash.Seed.seed!(
        EntryCategory,
        %{
          organization_id: org_id,
          entity_type: :transaction,
          resource_id: classified.id,
          category: :software,
          probability: 0.9,
          probabilities: %{"software" => 0.9}
        },
        tenant: org_id
      )

      # Only the classified one lowers the income: 9% of 9 000.
      forecast = first_quarter.()
      assert Decimal.equal?(forecast.details.costs, 1000)
      assert Decimal.equal?(forecast.amount, 810)
    end

    test "forecasts the owner's PIT advances and ZUS, and nothing of the kind for a limited company",
         %{
           admin: admin,
           scope: scope
         } do
      set_legal_form(scope, :sole_proprietorship)

      Taxes.create_tax_year!(
        %{
          year: 2026,
          vat_period: :monthly,
          partners: [
            Map.put(
              %{partner(admin.member.id, 100) | income_tax: :tax_scale},
              :voluntary_sickness,
              true
            )
          ]
        },
        scope: scope
      )

      seed_sales(scope, %{}, Decimal.new("1000"))

      assert {:ok, forecasts} = Taxes.forecast_taxes(2026, scope: scope)
      assert [:vat, :pit, :zus] = forecasts |> Enum.map(& &1.kind) |> Enum.uniq()

      pit = Enum.filter(forecasts, &(&1.kind == :pit))
      zus = Enum.filter(forecasts, &(&1.kind == :zus))
      assert length(pit) == 12
      assert length(zus) == 12
      assert Enum.all?(pit ++ zus, &(&1.member_id == admin.member.id))

      # 1 926,76 of social contributions with sickness and the Labour Fund, and the January minimum
      # of health, as December had no income.
      assert %{period: "2026-01", due_date: ~D[2026-02-20]} = january = hd(zus)
      assert Decimal.equal?(january.amount, "2241.72")

      # The contributions exceed the income, so no tax is due.
      assert Decimal.equal?(hd(pit).details.revenue, 1000)
      assert Decimal.equal?(hd(pit).amount, 0)

      other = admin_fixture()
      other_scope = %Firmowid.Scope{actor: other, tenant: other.member.organization_id}
      create_company_tax_year(other_scope)

      assert {:ok, company_forecasts} = Taxes.forecast_taxes(2026, scope: other_scope)
      assert Enum.all?(company_forecasts, &(&1.kind in [:vat, :cit]))
    end

    test "is for accountants and above, and empty for a year that was not saved", %{
      org_id: org_id,
      scope: scope
    } do
      create_company_tax_year(scope)
      invoicing = user_in_org_fixture(org_id, %{role: :invoicing})

      assert {:error, %Forbidden{}} =
               Taxes.forecast_taxes(2026,
                 scope: %Firmowid.Scope{actor: invoicing, tenant: org_id}
               )

      assert {:ok, []} = Taxes.forecast_taxes(2025, scope: scope)
    end
  end

  describe "pending_suggestions/3" do
    test "asks again only when transfers synced after the save contradict it" do
      organization = %Core.Organization{legal_form: :sole_proprietorship, is_vat_payer: true}
      saved_at = ~U[2026-05-01 12:00:00Z]

      tax_year = %TaxYear{
        vat_period: :monthly,
        updated_at: saved_at,
        partners: [%Partner{income_tax: :flat_tax, pit_advances: :monthly}]
      }

      suggestion = fn setting, value, synced_at ->
        %{setting: setting, value: value, year: 2026, transfers: 3, latest_transfer_at: synced_at}
      end

      before_save = DateTime.shift(saved_at, day: -1)
      after_save = DateTime.shift(saved_at, day: 1)

      # The admin saved a different form than older transfers suggest.
      assert Taxes.pending_suggestions(
               [suggestion.(:income_tax, :lump_sum, before_save)],
               tax_year,
               organization
             ) ==
               []

      assert [%{setting: :income_tax}] =
               Taxes.pending_suggestions(
                 [suggestion.(:income_tax, :lump_sum, after_save)],
                 tax_year,
                 organization
               )

      # What agrees with the saved year, or does not apply to the legal form, waits for nothing.
      assert Taxes.pending_suggestions(
               [
                 suggestion.(:vat_period, :monthly, after_save),
                 suggestion.(:cit_advances, :quarterly, after_save)
               ],
               tax_year,
               organization
             ) == []

      # A year not saved yet takes every suggestion that applies.
      assert [%{setting: :vat_period}] =
               Taxes.pending_suggestions(
                 [suggestion.(:vat_period, :quarterly, before_save)],
                 nil,
                 organization
               )
    end
  end
end
