defmodule Firmowid.InvoiceMatcherTest do
  use Firmowid.DataCase

  alias Firmowid.InvoiceMatcher

  describe "compare_date_then_creditor_then_amount/2" do
    test "sorts properly by name" do
      {a, b} = prep_documents(%{}, %{})

      sorted_list =
        [a, b]
        |> Enum.sort(&InvoiceMatcher.compare_date_then_creditor_then_amount/2)

      assert sorted_list == [a, b]
    end

    test "sorts properly by date" do
      {a, b} = prep_documents(%{issue_date: ~D[2022-02-01]}, %{issue_date: ~D[2022-01-01]})

      {c, d} =
        prep_documents(%{id: 3, issue_date: ~D[2022-04-01]}, %{id: 4, issue_date: ~D[2022-03-01]})

      sorted_list =
        [b, c, a, d]
        |> Enum.sort(&InvoiceMatcher.compare_date_then_creditor_then_amount/2)

      sorted_list_viewable =
        sorted_list
        |> Enum.map(
          &%{
            id: &1.id,
            issue_date:
              &1.issue_date
              |> Date.to_iso8601()
          }
        )

      assert sorted_list == [c, d, a, b]
    end

    test "sorts properly by amount" do
      {a, b} =
        prep_documents(
          %{total_amount: Decimal.from_float(200.0)},
          %{seller: "a", total_amount: Decimal.from_float(100.0)}
        )

      sorted_list =
        [a, b]
        |> Enum.sort(&InvoiceMatcher.compare_date_then_creditor_then_amount/2)

      assert sorted_list == [a, b]
    end
  end

  defp prep_documents(override_a, override_b) do
    a =
      InvoiceMatcher.from_document(
        Map.merge(
          %{
            id: 1,
            documents: [],
            imported_transactions: [],
            total_amount: Decimal.from_float(100.0),
            currency: "PLN",
            seller: "a",
            issue_date: ~D[2022-01-01],
            due_date: ~D[2022-01-31],
            sale_date: ~D[2022-01-01],
            file_url: "/doc.pdf",
            skip_invoicing: false
          },
          override_a
        )
      )

    b =
      InvoiceMatcher.from_document(
        Map.merge(
          %{
            id: 2,
            documents: [],
            imported_transactions: [],
            total_amount: Decimal.from_float(100.0),
            currency: "PLN",
            seller: "b",
            issue_date: ~D[2022-01-01],
            due_date: ~D[2022-01-31],
            sale_date: ~D[2022-01-01],
            file_url: "/doc.pdf",
            skip_invoicing: false
          },
          override_b
        )
      )

    {a, b}
  end
end
