defmodule Firmowid.Repo.Migrations.ChangePaymentMethodToEnum do
  use Ecto.Migration

  def up do
    # Create the enum type
    execute """
    CREATE TYPE payment_method_type AS ENUM (
      'cash', 'card', 'voucher', 'check', 'credit', 'transfer', 'mobile'
    )
    """

    # Add temporary column with enum type
    alter table(:sales_invoices) do
      add :payment_method_new, :payment_method_type
    end

    # Migrate data: "Przelew" → 'transfer'
    execute """
    UPDATE sales_invoices
    SET payment_method_new = 'transfer'
    WHERE payment_method = 'Przelew'
    """

    # Drop old column
    alter table(:sales_invoices) do
      remove :payment_method
    end

    # Rename new column to original name
    rename table(:sales_invoices), :payment_method_new, to: :payment_method
  end

  def down do
    # Add back string column
    alter table(:sales_invoices) do
      add :payment_method_old, :string
    end

    # Convert enum values back to strings
    execute """
    UPDATE sales_invoices
    SET payment_method_old = 'Przelew'
    WHERE payment_method = 'transfer'
    """

    # Drop enum column
    alter table(:sales_invoices) do
      remove :payment_method
    end

    # Rename old column back
    rename table(:sales_invoices), :payment_method_old, to: :payment_method

    # Drop enum type
    execute "DROP TYPE payment_method_type"
  end
end
