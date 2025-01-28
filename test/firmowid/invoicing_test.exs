defmodule Firmowid.InvoicingTest do
  alias Firmowid.Accounts.User
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Invoicing
  alias Firmowid.Blobs.Blob
  alias Firmowid.CostInvoices.CostInvoice

  describe "order_entries_for_display/2" do
    test "sorts properly by name" do
      %User{organization_id: organization_id} = user_fixture()

      {a, b} = prep_entries(%{}, %{}, organization_id)

      sorted_list =
        [a, b]
        |> Invoicing.order_entries_for_display()

      assert sorted_list == [a, b]
    end

    test "sorts properly by date" do
      %User{organization_id: organization_id} = user_fixture()

      {a, b} =
        prep_entries(
          %{issue_date: ~D[2022-02-01]},
          %{issue_date: ~D[2022-01-01]},
          organization_id
        )

      {c, d} =
        prep_entries(
          %{id: 3, issue_date: ~D[2022-04-01]},
          %{id: 4, issue_date: ~D[2022-03-01]},
          organization_id
        )

      sorted_list =
        [b, c, a, d]
        |> Invoicing.order_entries_for_display()

      assert sorted_list == [c, d, a, b]
    end

    test "sorts properly by amount" do
      %User{organization_id: organization_id} = user_fixture()

      {a, b} =
        prep_entries(
          %{total_amount: Decimal.from_float(200.0)},
          %{seller: "a", total_amount: Decimal.from_float(100.0)},
          organization_id
        )

      sorted_list =
        [a, b]
        |> Invoicing.order_entries_for_display()

      assert sorted_list == [a, b]
    end
  end

  defp prep_entries(override_a, override_b, organization_id) do
    a_blob =
      %Blob{
        blob_checksum: UUIDv7.generate(),
        blob_path: "a.pdf",
        original_filename: "a.pdf",
        organization_id: organization_id
      }
      |> Repo.insert!()

    a =
      CostInvoice.changeset(
        %CostInvoice{},
        Map.merge(
          %{
            id: 1,
            invoice_identifier: "a",
            description: "a",
            total_amount: Decimal.from_float(100.0),
            currency: "PLN",
            seller: "a",
            seller_display_name: "a",
            issue_date: ~D[2022-01-01],
            due_date: ~D[2022-01-31],
            sale_date: ~D[2022-01-01],
            file_url: "/doc.pdf",
            skip_invoicing: false,
            inserted_at: ~D[2022-01-01],
            organization_id: organization_id,
            blob_id: a_blob.id
          },
          override_a
        )
      )
      |> Repo.insert!()

    b_blob =
      %Blob{
        blob_checksum: UUIDv7.generate(),
        blob_path: "b.pdf",
        original_filename: "b.pdf",
        organization_id: organization_id
      }
      |> Repo.insert!()

    b =
      CostInvoice.changeset(
        %CostInvoice{},
        Map.merge(
          %{
            id: 2,
            invoice_identifier: "b",
            description: "b",
            total_amount: Decimal.from_float(100.0),
            currency: "PLN",
            seller: "b",
            seller_display_name: "b",
            issue_date: ~D[2022-01-01],
            due_date: ~D[2022-01-31],
            sale_date: ~D[2022-01-01],
            file_url: "/doc.pdf",
            skip_invoicing: false,
            inserted_at: ~D[2022-01-01],
            organization_id: organization_id,
            blob_id: b_blob.id
          },
          override_b
        )
      )
      |> Repo.insert!()

    {a, b}
  end
end
