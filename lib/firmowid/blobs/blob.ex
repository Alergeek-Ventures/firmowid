defmodule Firmowid.Blobs.Blob do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "blobs" do
    field :blob_path, :string
    field :blob_checksum, :string
    field :original_filename, :string

    has_one :cost_invoice, Firmowid.CostInvoices.CostInvoice

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  def changeset(blob, attrs \\ %{}) do
    blob
    |> cast(attrs, [:blob_path, :blob_checksum, :original_filename, :organization_id])
    |> validate_required([:blob_path, :blob_checksum, :original_filename, :organization_id])
    |> unique_constraint([:blob_checksum, :organization_id])
  end
end
