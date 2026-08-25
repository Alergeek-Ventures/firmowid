defmodule Firmowid.Ash.Finances.BankAccountTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Ash.Error.Changes.Required
  alias Ash.Error.Invalid
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.BankAccount
  alias Firmowid.Ash.Finances.Requisition
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  describe "AshOban queue routing" do
    test "keeps sync_transactions on bank_data queue" do
      assert :bank_data ==
               AshOban.Info.oban_trigger(BankAccount, :sync_transactions).queue
    end
  end

  describe "bank account identity" do
    test "sync action creates distinct accounts for the same IBAN in distinct currencies" do
      admin = admin_fixture()
      scope = %Scope{actor: admin, tenant: admin.organization_id}
      iban = "PL44 1140 2004 0000 3002 0135 5361"

      assert {:ok, first} =
               sync_bank_account(scope, %{
                 iban: iban,
                 currency: "PLN",
                 gocardless_id: "account-pln"
               })

      assert {:ok, second} =
               sync_bank_account(scope, %{
                 iban: iban,
                 currency: "EUR",
                 gocardless_id: "account-eur"
               })

      refute first.id == second.id
      assert first.iban == second.iban
      assert first.currency != second.currency
    end

    test "reconnect upserts provider metadata without replacing the local account" do
      admin = admin_fixture()
      scope = %Scope{actor: admin, tenant: admin.organization_id}
      iban = "PL44 1140 2004 0000 3002 0135 5362"

      assert {:ok, account} =
               Finances.create_manual_bank_account(
                 %{iban: iban, currency: "pln", name: "Local account"},
                 scope: scope
               )

      requisition_id = Ecto.UUID.generate()
      Ash.Seed.seed!(Requisition, %{id: requisition_id}, tenant: scope.tenant)

      assert {:ok, reconnected} =
               sync_bank_account(scope, %{
                 iban: " pl44 1140 2004 0000 3002 0135 5362 ",
                 currency: " PLN ",
                 name: "Remote name",
                 gocardless_id: "new-account-id",
                 requisition_id: requisition_id,
                 institution_id: "new-institution",
                 institution_name: "New bank"
               })

      assert reconnected.id == account.id
      assert reconnected.iban == "PL44114020040000300201355362"
      assert reconnected.currency == "PLN"
      assert reconnected.name == "Local account"
      assert reconnected.gocardless_id == "new-account-id"
      assert reconnected.institution_id == "new-institution"
      assert reconnected.institution_name == "New bank"
    end

    test "normalizes IBAN and currency on manual creation" do
      admin = admin_fixture()
      scope = %Scope{actor: admin, tenant: admin.organization_id}

      assert {:ok, account} =
               Finances.create_manual_bank_account(
                 %{iban: " pl44 1140\t2004 0000 3002 0135 5363 ", currency: " eur "},
                 scope: scope
               )

      assert account.iban == "PL44114020040000300201355363"
      assert account.currency == "EUR"
    end

    test "rejects missing and empty currency and IBAN" do
      admin = admin_fixture()
      scope = %Scope{actor: admin, tenant: admin.organization_id}

      assert {:error, %Invalid{errors: errors}} =
               Finances.create_manual_bank_account(%{iban: "PL123", currency: ""}, scope: scope)

      assert Enum.any?(errors, &match?(%Required{field: :currency}, &1))

      assert {:error, %Invalid{errors: errors}} =
               Finances.create_manual_bank_account(%{iban: "PL123"}, scope: scope)

      assert Enum.any?(errors, &match?(%Required{field: :currency}, &1))

      assert {:error, %Invalid{errors: errors}} =
               Finances.create_manual_bank_account(%{iban: "", currency: "PLN"}, scope: scope)

      assert Enum.any?(errors, &match?(%Required{field: :iban}, &1))
    end
  end

  defp sync_bank_account(scope, attrs) do
    actor = %SystemActor{org_id: scope.tenant, role: :bank_sync}
    Finances.sync_bank_account(attrs, tenant: scope.tenant, actor: actor)
  end
end
