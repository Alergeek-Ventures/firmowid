defmodule Firmowid.Billing.Limits do
  @moduledoc """
  Schema for organization usage limits.

  Tracks monthly usage of cost/sales invoices and total bank connections.
  Invoice counts are reset by a cron job on the 1st of each month.
  """
  use Firmowid.Schema

  import Ecto.Changeset

  alias Firmowid.Accounts.Organization

  @type t :: %__MODULE__{}

  schema "organization_limits" do
    belongs_to :organization, Organization

    field :cost_invoices_used, :integer, default: 0
    field :cost_invoices_limit, :integer, default: 100
    field :sales_invoices_used, :integer, default: 0
    field :sales_invoices_limit, :integer, default: 100
    field :bank_connections_used, :integer, default: 0
    field :bank_connections_limit, :integer, default: 5

    timestamps()
  end

  @doc false
  def changeset(limits, attrs \\ %{}) do
    limits
    |> cast(attrs, [
      :organization_id,
      :cost_invoices_used,
      :cost_invoices_limit,
      :sales_invoices_used,
      :sales_invoices_limit,
      :bank_connections_used,
      :bank_connections_limit
    ])
    |> validate_required([:organization_id])
    |> validate_number(:cost_invoices_used, greater_than_or_equal_to: 0)
    |> validate_number(:cost_invoices_limit, greater_than_or_equal_to: 0)
    |> validate_number(:sales_invoices_used, greater_than_or_equal_to: 0)
    |> validate_number(:sales_invoices_limit, greater_than_or_equal_to: 0)
    |> validate_number(:bank_connections_used, greater_than_or_equal_to: 0)
    |> validate_number(:bank_connections_limit, greater_than_or_equal_to: 0)
    |> unique_constraint(:organization_id)
    |> foreign_key_constraint(:organization_id)
  end
end
