defmodule Firmowid.TaxesTest do
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Ash.Error.Invalid
  alias Firmowid.Core
  alias Firmowid.Finances.Transaction
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

      assert {:error, %Ash.Error.Forbidden{}} =
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
