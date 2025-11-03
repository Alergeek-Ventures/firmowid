defmodule Firmowid.Repo.Migrations.AddInboundEmailSupport do
  use Ecto.Migration

  def change do
    # Add allowed sender emails to organizations
    alter table(:organizations) do
      add :allowed_sender_emails, {:array, :text}, default: []
    end

    # Create inbound_emails table
    create table(:inbound_emails, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :organization_id, references(:organizations, type: :uuid, on_delete: :delete_all),
        null: false

      add :resend_email_id, :string, null: false
      add :sender_email, :string, null: false
      add :subject, :text
      add :body, :text
      add :received_at, :utc_datetime, null: false
      add :processed_at, :utc_datetime
      add :failure_reason, :string

      timestamps()
    end

    create unique_index(:inbound_emails, [:resend_email_id])
    create index(:inbound_emails, [:organization_id])

    # Add relationship from cost_invoices to inbound_emails
    alter table(:cost_invoices) do
      add :inbound_email_id, references(:inbound_emails, type: :uuid, on_delete: :nilify_all)
    end

    create index(:cost_invoices, [:inbound_email_id])
  end
end
