defmodule Firmowid.InvoicingTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures

  alias Firmowid.Accounts.User
  alias Firmowid.Ash.Invoicing.CostInvoice, as: AshCostInvoice
  alias Firmowid.Blobs.Blob
  alias Firmowid.CostInvoices.CostInvoice
  alias Firmowid.Invoicing

  # TODO: replace authorize?: false + actor: %{} with system actor once available
  @bridge_opts [authorize?: false, actor: %{}]

  describe "order_entries_for_display/2" do
    test "sorts properly by name" do
      %User{organization_id: organization_id} = user_fixture()

      {a, b} = prep_entries(%{}, %{}, organization_id)

      sorted_list = Invoicing.order_entries_for_display([a, b])

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
          %{issue_date: ~D[2022-04-01]},
          %{issue_date: ~D[2022-03-01]},
          organization_id
        )

      sorted_list = Invoicing.order_entries_for_display([b, c, a, d])

      assert sorted_list == [c, d, a, b]
    end

    test "sorts properly by amount" do
      %User{organization_id: organization_id} = user_fixture()

      {a, b} =
        prep_entries(
          %{total_amount: Decimal.from_float(-200.0)},
          %{seller: "a", total_amount: Decimal.from_float(-100.0)},
          organization_id
        )

      sorted_list = Invoicing.order_entries_for_display([a, b])

      assert sorted_list == [a, b]
    end
  end

  # Inserts cost invoices via Ecto, then re-fetches as Ash structs so that
  # `order_entries_for_display/1` pattern matches work correctly.
  defp prep_entries(override_a, override_b, organization_id) do
    a_blob =
      Repo.insert!(%Blob{
        blob_checksum: UUIDv7.generate(),
        blob_path: "a.pdf",
        original_filename: "a.pdf",
        organization_id: organization_id
      })

    ecto_a =
      %CostInvoice{
        invoice_identifier: "a",
        description: "a",
        total_amount: Decimal.from_float(-100.0),
        currency: "PLN",
        seller: "a",
        seller_display_name: "a",
        issue_date: ~D[2022-01-01],
        due_date: ~D[2022-01-31],
        sale_date: ~D[2022-01-01],
        skip_invoicing: false,
        organization_id: organization_id,
        blob_id: a_blob.id,
        transactions: []
      }
      |> Map.merge(override_a)
      |> Repo.insert!()

    b_blob =
      Repo.insert!(%Blob{
        blob_checksum: UUIDv7.generate(),
        blob_path: "b.pdf",
        original_filename: "b.pdf",
        organization_id: organization_id
      })

    ecto_b =
      %CostInvoice{
        invoice_identifier: "b",
        description: "b",
        total_amount: Decimal.from_float(-100.0),
        currency: "PLN",
        seller: "b",
        seller_display_name: "b",
        issue_date: ~D[2022-01-01],
        due_date: ~D[2022-01-31],
        sale_date: ~D[2022-01-01],
        skip_invoicing: false,
        organization_id: organization_id,
        blob_id: b_blob.id,
        transactions: []
      }
      |> Map.merge(override_b)
      |> Repo.insert!()

    # Re-fetch as Ash structs with transactions loaded
    ash_opts = [tenant: organization_id, load: [:transactions]] ++ @bridge_opts
    a = AshCostInvoice.by_id!(ecto_a.id, ash_opts)
    b = AshCostInvoice.by_id!(ecto_b.id, ash_opts)

    {a, b}
  end
end
