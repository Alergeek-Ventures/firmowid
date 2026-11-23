defmodule Firmowid.Analysis.CategoryReviewTest do
  @moduledoc "Regression coverage for joining a counterparty's name variants in the analysis review."
  use Firmowid.DataCase, async: true

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Firmowid.Analysis
  alias Firmowid.Analysis.CategoryReview
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.CostInvoiceTransaction
  alias Firmowid.Scope

  @bank_name "ACME UL DLUGA 1 KRAKOW"

  test "joins a transfer without NIP to the counterparty whose paired transfer has its name" do
    review =
      CategoryReview.build(
        [
          entry("Acme Sp. z o.o.", nip: "PL 123-456-78-90", transfer_names: [@bank_name]),
          entry(@bank_name)
        ],
        [],
        :gastronomy
      )

    assert [%{count: 2, names: names}] = review.groups
    assert Enum.sort(names) == Enum.sort(["Acme Sp. z o.o.", @bank_name])
  end

  test "keeps different purchases from one NIP apart" do
    review =
      CategoryReview.build(
        [
          entry("Acme Sp. z o.o.", nip: "1234567890", classified: :goods),
          entry("ACME", nip: "1234567890", classified: :premises, transfer_names: [@bank_name]),
          entry(@bank_name, classified: :premises)
        ],
        [],
        :gastronomy
      )

    assert [
             %{suggestion: :goods, count: 1, key: key},
             %{suggestion: :premises, count: 2, key: key}
           ] =
             Enum.sort_by(review.groups, & &1.suggestion)
  end

  test "joins no counterparty with a bank name another NIP claims" do
    review =
      CategoryReview.build(
        [
          entry("Acme", nip: "1234567890", transfer_names: ["PAYMENT OPERATOR"]),
          entry("Beta", nip: "9876543210", transfer_names: ["PAYMENT OPERATOR", "Gamma"]),
          entry("Gamma", nip: "5555555555"),
          entry("PAYMENT OPERATOR")
        ],
        [],
        :gastronomy
      )

    assert review.groups |> Enum.map(& &1.key) |> Enum.sort() == [
             "acme",
             "beta",
             "gamma",
             "payment operator"
           ]
  end

  test "joins nothing by a paired name without a valid NIP" do
    for nip <- [nil, "12-3"] do
      review =
        CategoryReview.build(
          [entry("Acme Sp. z o.o.", nip: nip, transfer_names: [@bank_name]), entry(@bank_name)],
          [],
          :gastronomy
        )

      assert review.groups |> Enum.map(& &1.key) |> Enum.sort() == [
               "acme",
               CategoryReview.key(@bank_name)
             ]
    end
  end

  test "joins by transfers paired in the organization only" do
    user = admin_fixture()
    other_user = admin_fixture()

    paid_invoice(user, @bank_name)
    skipped_transfer(user)
    paid_invoice(other_user, nil)
    skipped_transfer(other_user)

    assert [%{count: 2}] = expense_groups(user)
    assert [%{count: 1}, %{count: 1}] = expense_groups(other_user)
  end

  defp entry(name, attrs \\ []) do
    Map.merge(
      %{
        side: :expenses,
        month: ~D[2026-10-01],
        name: name,
        amount: Decimal.new("100.00"),
        lines: [],
        nip: nil,
        transfer_names: [],
        salary_user_id: nil,
        certain: nil,
        classified: nil,
        probability: nil
      },
      Map.new(attrs)
    )
  end

  defp expense_groups(user) do
    scope = %Scope{actor: user, tenant: user.member.organization_id}

    ~D[2026-10-01]
    |> Date.range(~D[2026-10-31])
    |> Analysis.get_category_review(scope)
    |> Map.fetch!(:groups)
    |> Enum.filter(&(&1.side == :expenses))
  end

  defp paid_invoice(user, bank_name) do
    tenant = user.member.organization_id

    invoice =
      Ash.Seed.seed!(
        CostInvoice,
        %{
          seller: "Acme Sp. z o.o.",
          seller_display_name: "Acme Sp. z o.o.",
          seller_nip: "1234567890",
          sale_date: ~D[2026-10-01],
          issue_date: ~D[2026-10-01],
          due_date: ~D[2026-10-15],
          amount: Money.new!(:PLN, "-100.00"),
          invoice_identifier: "FV/1/10/2026"
        },
        tenant: tenant
      )

    transfer = transfer(user, %{creditor_name: bank_name, skip_invoicing: false})

    Ash.Seed.seed!(CostInvoiceTransaction, %{
      cost_invoice_id: invoice.id,
      transaction_id: transfer.id,
      organization_id: tenant
    })
  end

  defp skipped_transfer(user), do: transfer(user, %{creditor_name: @bank_name, skip_invoicing: true})

  defp transfer(user, attrs) do
    Ash.Seed.seed!(
      Transaction,
      Map.merge(
        %{
          bank_account_id: bank_account_fixture!(user).id,
          amount: Money.new!(:PLN, "-50.00"),
          booking_date: ~D[2026-10-12],
          value_date: ~D[2026-10-12]
        },
        attrs
      ),
      tenant: user.member.organization_id
    )
  end
end
