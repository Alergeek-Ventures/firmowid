defmodule Firmowid.Finances.FinancesTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Firmowid.Finances
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.CostInvoiceTransaction
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Scope
  alias Firmowid.SystemActor

  setup do
    # Admin user required — transactions are not accessible to :employee role
    user = admin_fixture()
    org_id = user.member.organization_id
    seed_opts = [tenant: org_id]
    bank_account = bank_account_fixture!(user)
    bank_account_id = bank_account.id

    # Pending: no invoices, not skipped
    pending_tx =
      Ash.Seed.seed!(
        Transaction,
        %{
          debtor_name: "Pending Debtor",
          creditor_name: "Pending Creditor",
          remittance_information_unstructured: "pending payment",
          amount: Money.new!("PLN", Decimal.new("100.00")),
          booking_date: ~D[2024-01-10],
          value_date: ~D[2024-01-10],
          bank_account_id: bank_account_id,
          skip_invoicing: false
        },
        seed_opts
      )

    # Skipped: no invoices, skip_invoicing = true
    skipped_tx =
      Ash.Seed.seed!(
        Transaction,
        %{
          debtor_name: "Skipped Debtor",
          creditor_name: "Skipped Creditor",
          remittance_information_unstructured: "skipped payment",
          amount: Money.new!("PLN", Decimal.new("200.00")),
          booking_date: ~D[2024-01-11],
          value_date: ~D[2024-01-11],
          bank_account_id: bank_account_id,
          skip_invoicing: true
        },
        seed_opts
      )

    # Matched: linked to a cost invoice
    matched_tx =
      Ash.Seed.seed!(
        Transaction,
        %{
          debtor_name: "Matched Debtor",
          creditor_name: "Matched Creditor",
          remittance_information_unstructured: "matched payment",
          amount: Money.new!("PLN", Decimal.new("-100.00")),
          booking_date: ~D[2024-01-12],
          value_date: ~D[2024-01-12],
          bank_account_id: bank_account_id,
          skip_invoicing: false
        },
        seed_opts
      )

    cost_invoice =
      Ash.Seed.seed!(
        CostInvoice,
        %{
          seller: "Test Vendor",
          seller_display_name: "Test Vendor",
          sale_date: ~D[2024-01-01],
          issue_date: ~D[2024-01-01],
          due_date: ~D[2024-02-01],
          amount: Money.new!("PLN", Decimal.new("-100.00")),
          invoice_identifier: "CI-TEST-001",
          description: "Test invoice"
        },
        seed_opts
      )

    Ash.Seed.seed!(CostInvoiceTransaction, %{
      cost_invoice_id: cost_invoice.id,
      transaction_id: matched_tx.id,
      organization_id: org_id
    })

    %{
      user: user,
      org_id: org_id,
      bank_account: bank_account,
      pending_tx: pending_tx,
      skipped_tx: skipped_tx,
      matched_tx: matched_tx
    }
  end

  for invoice_resource <- [CostInvoice, SalesInvoice] do
    @tag capture_log: true
    test "does not reconcile a salary transfer twice while connecting #{inspect(invoice_resource)}" do
      resource = unquote(invoice_resource)
      parent = self()

      Sandbox.unboxed_run(Repo, fn ->
        admin = admin_fixture()
        scope = Scope.new!(admin, admin.member.organization_id)
        accountant = user_fixture(%{organization_id: scope.tenant, role: :accountant})
        accountant_scope = Scope.new!(accountant, scope.tenant)
        bank_account = bank_account_fixture!(admin)

        on_exit(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            assert {:ok, :ok} =
                     Repo.transaction(fn ->
                       :ok = Firmowid.Core.destroy_user_in_transaction(admin, actor: admin)
                       Firmowid.Core.User.destroy!(accountant, authorize?: false)
                     end)
          end)
        end)

        Ash.Seed.seed!(Firmowid.Payroll.UserSalary, %{
          organization_id: scope.tenant,
          member_id: admin.member.id,
          hourly_rate: Decimal.new(100),
          starts_at: ~U[2025-01-01 00:00:00Z]
        })

        project =
          Ash.Seed.seed!(Firmowid.Timetracker.Project, %{
            name: "Salary hours",
            organization_id: scope.tenant
          })

        Ash.Seed.seed!(Firmowid.Timetracker.Session, %{
          organization_id: scope.tenant,
          member_id: admin.member.id,
          project_id: project.id,
          title: "Salary hours",
          start_datetime: ~U[2025-12-01 09:00:00Z],
          end_datetime: ~U[2025-12-01 10:00:00Z]
        })

        transaction =
          Ash.Seed.seed!(Transaction, %{
            organization_id: scope.tenant,
            bank_account_id: bank_account.id,
            debtor_account: bank_account.iban,
            creditor_account: "PL999",
            amount: Money.new!(:PLN, -100),
            booking_date: ~D[2026-01-10],
            value_date: ~D[2026-01-10]
          })

        invoice_attrs = %{
          organization_id: scope.tenant,
          issue_date: ~D[2026-01-01],
          sale_date: ~D[2026-01-01],
          due_date: ~D[2026-01-20]
        }

        invoice = Ash.Seed.seed!(resource, concurrency_invoice_attrs(resource, invoice_attrs))

        connecting =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              invoice
              |> Ash.Changeset.for_update(
                :connect_transactions,
                %{transaction_ids: [transaction.id]},
                scope: accountant_scope
              )
              |> Ash.Changeset.before_action(fn changeset ->
                %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
                send(parent, {:invoice_eligible, self(), backend_pid})

                receive do
                  :continue -> changeset
                after
                  10_000 -> raise "invoice connection barrier timed out"
                end
              end)
              |> Ash.update(scope: accountant_scope)
            end)
          end)

        assert_receive {:invoice_eligible, connecting_pid, invoice_backend}, 10_000

        salary =
          Task.async(fn ->
            Sandbox.unboxed_run(Repo, fn ->
              %{rows: [[backend_pid]]} = Repo.query!("SELECT pg_backend_pid()")
              send(parent, {:salary_backend, backend_pid})

              Finances.connect_transaction_salary(
                transaction,
                %{salary_user_id: admin.id, salary_month: ~D[2025-12-01]},
                scope: scope
              )
            end)
          end)

        assert_receive {:salary_backend, backend_pid}, 10_000
        refute backend_pid == invoice_backend
        salary_state = await_salary_assignment(salary, backend_pid, 2_000)
        send(connecting_pid, :continue)
        assert {:ok, _invoice} = Task.await(connecting, 10_000)

        salary_result =
          case salary_state do
            :blocked -> Task.await(salary, 10_000)
            {:completed, result} -> result
          end

        persisted =
          Finances.get_transaction!(transaction.id,
            load: [:cost_invoices, :sales_invoices],
            scope: scope
          )

        assert length(persisted.cost_invoices) + length(persisted.sales_invoices) == 1
        assert is_nil(persisted.salary_user_id)
        assert {:error, _} = salary_result
      end)
    end
  end

  defp concurrency_invoice_attrs(CostInvoice, attrs), do: Map.put(attrs, :amount, Money.new!(:PLN, -100))

  defp concurrency_invoice_attrs(SalesInvoice, attrs), do: attrs

  defp await_salary_assignment(_task, _backend_pid, 0), do: flunk("salary assignment did not complete or reach its lock")

  defp await_salary_assignment(task, backend_pid, attempts) do
    case Task.yield(task, 0) do
      {:ok, result} ->
        {:completed, result}

      nil ->
        %{rows: [[blocked]]} =
          Repo.query!("SELECT cardinality(pg_blocking_pids($1)) > 0", [backend_pid])

        if blocked, do: :blocked, else: await_salary_assignment(task, backend_pid, attempts - 1)
    end
  end

  describe "reconciliation filtering" do
    test "reconciliation: :pending returns only unmatched, non-skipped transactions", ctx do
      ids =
        %{reconciliation: :pending}
        |> Finances.list_transactions!(
          actor: ctx.user,
          tenant: ctx.org_id
        )
        |> Enum.map(& &1.id)

      assert ctx.pending_tx.id in ids
      refute ctx.skipped_tx.id in ids
      refute ctx.matched_tx.id in ids
    end

    test "reconciliation: :skipped returns only skipped transactions", ctx do
      ids =
        %{reconciliation: :skipped}
        |> Finances.list_transactions!(
          actor: ctx.user,
          tenant: ctx.org_id
        )
        |> Enum.map(& &1.id)

      assert ctx.skipped_tx.id in ids
      refute ctx.pending_tx.id in ids
      refute ctx.matched_tx.id in ids
    end

    test "reconciliation: :matched returns only transactions linked to invoices", ctx do
      ids =
        %{reconciliation: :matched}
        |> Finances.list_transactions!(
          actor: ctx.user,
          tenant: ctx.org_id
        )
        |> Enum.map(& &1.id)

      assert ctx.matched_tx.id in ids
      refute ctx.pending_tx.id in ids
      refute ctx.skipped_tx.id in ids
    end
  end

  describe "BM25 search" do
    test "returns matching transactions", ctx do
      results =
        Finances.list_transactions!(%{query: "pending payment"},
          actor: ctx.user,
          tenant: ctx.org_id
        )

      ids = Enum.map(results, & &1.id)
      assert ctx.pending_tx.id in ids
    end

    test "returns empty list when no matches found", ctx do
      results =
        Finances.list_transactions!(%{query: "NonExistentXyzzy"},
          actor: ctx.user,
          tenant: ctx.org_id
        )

      assert results == []
    end

    test "does not find transactions across organizations", ctx do
      user2 = user_fixture()
      org2_id = user2.member.organization_id
      other_org_bank_account_id = bank_account_fixture!(user2).id

      Ash.Seed.seed!(
        Transaction,
        %{
          debtor_name: "Other Org Debtor",
          creditor_name: "Other Org Creditor",
          remittance_information_unstructured: "other org payment",
          amount: Money.new!("PLN", Decimal.new("300.00")),
          booking_date: ~D[2024-01-13],
          value_date: ~D[2024-01-13],
          bank_account_id: other_org_bank_account_id
        },
        tenant: org2_id
      )

      org1_ids =
        %{}
        |> Finances.list_transactions!(actor: ctx.user, tenant: ctx.org_id)
        |> Enum.map(& &1.id)

      assert ctx.pending_tx.id in org1_ids
      assert ctx.skipped_tx.id in org1_ids
      assert ctx.matched_tx.id in org1_ids
    end
  end

  describe "transaction calculations" do
    test "calculation chain uses account ownership before amount sign", ctx do
      transaction =
        Ash.Seed.seed!(
          Transaction,
          %{
            creditor_account: "PL00999999999999999999999999",
            debtor_account: ctx.bank_account.iban,
            creditor_name: "Creditor counterparty",
            debtor_name: "Firmowid",
            amount: Money.new!("PLN", Decimal.new("100.00")),
            booking_date: ~D[2024-02-01],
            value_date: ~D[2024-02-01],
            bank_account_id: ctx.bank_account.id
          },
          tenant: ctx.org_id
        )

      loaded =
        Ash.load!(
          transaction,
          [
            :direction,
            :signed_amount,
            :counterparty_name,
            :counterparty_display_name,
            :groupable?
          ],
          scope: scope_for(ctx.user)
        )

      assert loaded.direction == :expense
      assert loaded.signed_amount == Money.new!("PLN", Decimal.new("-100.00"))
      assert loaded.counterparty_name == "Creditor counterparty"
      assert loaded.counterparty_display_name == "Creditor counterparty"
      assert loaded.groupable?
    end

    test "falls back to amount sign without an account match", ctx do
      transaction =
        Ash.Seed.seed!(
          Transaction,
          %{
            creditor_account: "PL00111111111111111111111111",
            debtor_account: "PL00222222222222222222222222",
            amount: Money.new!("PLN", Decimal.new("100.00")),
            booking_date: ~D[2024-02-02],
            value_date: ~D[2024-02-02],
            bank_account_id: ctx.bank_account.id
          },
          tenant: ctx.org_id
        )

      loaded = Ash.load!(transaction, [:direction, :signed_amount], scope: scope_for(ctx.user))

      assert loaded.direction == :income
      assert loaded.signed_amount == Money.new!("PLN", Decimal.new("100.00"))
    end

    test "missing and N/A counterparties fall back for display and cannot group", ctx do
      transaction =
        Ash.Seed.seed!(
          Transaction,
          %{
            creditor_name: "N/A",
            debtor_name: nil,
            amount: Money.new!("PLN", Decimal.new("-10.00")),
            booking_date: ~D[2024-02-03],
            value_date: ~D[2024-02-03],
            bank_account_id: ctx.bank_account.id
          },
          tenant: ctx.org_id
        )

      loaded =
        Ash.load!(transaction, [:counterparty_name, :counterparty_display_name, :groupable?], scope: scope_for(ctx.user))

      assert loaded.counterparty_name == "N/A"
      assert loaded.counterparty_display_name == "Transakcja bankowa"
      refute loaded.groupable?
    end

    test "skipped and matched transactions cannot group", ctx do
      loaded =
        Ash.load!([ctx.skipped_tx, ctx.matched_tx], :groupable?, scope: scope_for(ctx.user))

      assert Enum.all?(loaded, &(not &1.groupable?))
    end
  end

  describe "system actor authorization" do
    test "unrelated system actors cannot read transactions", ctx do
      scope = %Scope{
        actor: %SystemActor{org_id: ctx.org_id, role: :avatar_cleanup},
        tenant: ctx.org_id
      }

      assert {:error, _} = Finances.list_transactions(%{}, scope: scope)
    end

    test "analysis readers can read transactions in their organization", ctx do
      scope = %Scope{
        actor: %SystemActor{org_id: ctx.org_id, role: :analysis_reader},
        tenant: ctx.org_id
      }

      assert {:ok, transactions} = Finances.list_transactions(%{}, scope: scope)
      assert ctx.pending_tx.id in Enum.map(transactions, & &1.id)
    end
  end

  defp scope_for(user), do: %Scope{actor: user, tenant: user.member.organization_id}
end
