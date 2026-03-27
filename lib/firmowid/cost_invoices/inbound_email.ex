defmodule Firmowid.CostInvoices.InboundEmail do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  schema "inbound_emails" do
    belongs_to :organization, Firmowid.Accounts.Organization
    has_many :cost_invoices, Firmowid.CostInvoices.CostInvoice

    field :resend_email_id, :string
    field :sender_email, :string
    field :subject, :string
    field :body, :string
    field :received_at, :utc_datetime
    field :processed_at, :utc_datetime

    field :failure_reason, Ecto.Enum, values: [:unexpected_sender, :no_attachment, :processing_failed]

    timestamps()
  end

  @doc false
  def changeset(inbound_email, attrs \\ %{}) do
    inbound_email
    |> cast(attrs, [
      :organization_id,
      :resend_email_id,
      :sender_email,
      :subject,
      :body,
      :received_at,
      :processed_at,
      :failure_reason
    ])
    |> validate_required([
      :organization_id,
      :resend_email_id,
      :sender_email,
      :received_at
    ])
    |> unique_constraint(:resend_email_id)
    |> foreign_key_constraint(:organization_id)
  end
end
