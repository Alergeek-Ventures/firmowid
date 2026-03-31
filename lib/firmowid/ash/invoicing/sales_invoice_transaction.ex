defmodule Firmowid.Ash.Invoicing.SalesInvoiceTransaction do
  @moduledoc """
  Join resource linking sales invoices to bank transactions.

  Replaces the `create_sales_invoices_transactions_connection/3` and
  `delete_sales_invoices_transactions_connections/1` functions from the
  legacy `SalesInvoices` context.
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Invoicing,
    data_layer: AshPostgres.DataLayer

  alias Firmowid.Ash.Resource
  alias Firmowid.SalesInvoices.SalesInvoicesTransactions

  require Resource

  postgres do
    table "sales_invoices_transactions"
    repo Firmowid.Repo
    migrate? false
  end

  code_interface do
    define :create_connections, args: [:invoice_ids, :transaction_ids, :organization_id]
    define :delete_for_invoice, args: [:invoice_id]
  end

  actions do
    defaults []

    action :create_connections, :term do
      argument :invoice_ids, {:array, :uuid}, allow_nil?: false
      argument :transaction_ids, {:array, :uuid}, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false

      run fn input, _context ->
        invoice_ids = input.arguments.invoice_ids
        transaction_ids = input.arguments.transaction_ids
        organization_id = input.arguments.organization_id

        changesets =
          for invoice_id <- invoice_ids, transaction_id <- transaction_ids do
            SalesInvoicesTransactions.changeset(%{
              sales_invoice_id: invoice_id,
              transaction_id: transaction_id,
              organization_id: organization_id
            })
          end

        result =
          changesets
          |> Enum.reduce(Ecto.Multi.new(), fn %{changes: data} = changeset, acc ->
            Ecto.Multi.insert(acc, {data.sales_invoice_id, data.transaction_id}, changeset)
          end)
          |> Firmowid.Repo.transaction()

        case result do
          {:ok, _} -> {:ok, :connected}
          {:error, _, changeset, _} -> {:error, changeset}
        end
      end
    end

    action :delete_for_invoice, :term do
      argument :invoice_id, :uuid, allow_nil?: false

      run fn input, _context ->
        import Ecto.Query

        query =
          from(c in SalesInvoicesTransactions,
            where: c.sales_invoice_id == ^input.arguments.invoice_id
          )

        Firmowid.Repo.delete_all(query)
        {:ok, :deleted}
      end
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :sales_invoice_id, :uuid, allow_nil?: false, public?: true
    attribute :transaction_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false

    Resource.firmowid_timestamps()
  end
end
