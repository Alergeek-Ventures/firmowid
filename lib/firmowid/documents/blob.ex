defmodule Firmowid.Documents.Blob do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "blobs" do
    field :blob_path, :string
    field :original_filename, :string

    has_one :cost_invoice, Firmowid.Documents.CostInvoice

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  def changeset(blob, attrs \\ %{}) do
    blob
    |> cast(attrs, [:blob_path, :original_filename, :organization_id])
    |> validate_required([:blob_path, :original_filename, :organization_id])
  end
end
