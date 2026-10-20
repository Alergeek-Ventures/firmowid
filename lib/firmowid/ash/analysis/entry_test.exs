defmodule Firmowid.Ash.Analysis.EntryTest do
  @moduledoc "Regression coverage for analysis entry access and organization isolation."
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Ash.Error.Forbidden
  alias Firmowid.Ash.Analysis.Entry
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Scope
  alias FirmowidWeb.Infrastructure.Flags

  setup do
    posthog_enabled = Application.fetch_env!(:posthog, :enable)
    Application.put_env(:posthog, :enable, false)
    on_exit(fn -> Application.put_env(:posthog, :enable, posthog_enabled) end)
    :ok
  end

  test "lists only the caller's financial entries when the dashboard flag is disabled" do
    user = admin_fixture()
    other_user = admin_fixture()
    own_transaction = skipped_transaction(user)
    skipped_transaction(other_user)

    refute Flags.evaluate_for_user(user).analysis_dashboard

    assert {:ok, %{month: ~D[2026-10-01], entries: [entry]}} =
             Entry.list(~D[2026-10-12], scope: %Scope{actor: user, tenant: user.organization_id})

    assert entry.id == own_transaction.id
    assert entry.entity_type == :transaction
    assert Decimal.equal?(entry.amount, Decimal.new("123.45"))
  end

  test "rejects an administrator's mismatched organization scope" do
    user = admin_fixture()
    other_user = admin_fixture()

    assert {:error, %Forbidden{}} =
             Entry.list(~D[2026-10-01],
               scope: %Scope{actor: user, tenant: other_user.organization_id}
             )
  end

  test "rejects employees even within their organization" do
    user = user_fixture()

    assert {:error, %Forbidden{}} =
             Entry.list(~D[2026-10-01], scope: %Scope{actor: user, tenant: user.organization_id})
  end

  defp skipped_transaction(user) do
    bank_account = bank_account_fixture!(user)

    Ash.Seed.seed!(
      Transaction,
      %{
        bank_account_id: bank_account.id,
        amount: Money.new!(:PLN, "123.45"),
        booking_date: ~D[2026-10-12],
        value_date: ~D[2026-10-12],
        skip_invoicing: true
      },
      tenant: user.organization_id
    )
  end
end
