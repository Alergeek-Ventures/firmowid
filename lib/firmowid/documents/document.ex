defmodule Firmowid.Documents.Document do
  use Ecto.Schema
  use Waffle.Ecto.Schema

  import Ecto.Changeset

  schema "documents" do
    field :seller, :string

    field :sale_date, :date
    field :issue_date, :date
    field :due_date, :date

    field :total_amount, :float
    field :currency, :string

    field :file, FirmowidWeb.Uploaders.DocumentUploader.Type

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(document, attrs \\ %{}) do
    document
    |> cast(attrs, [:issue_date])
    |> cast_attachments(attrs, [:file])
    |> validate_required([:issue_date])
  end
end
