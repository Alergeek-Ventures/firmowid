defmodule Firmowid.Documents.Document do
  use Ecto.Schema
  import Ecto.Changeset

  schema "documents" do
    field :seller, :string

    field :sale_date, :date
    field :issue_date, :date
    field :due_date, :date

    field :total_amount, :float
    field :currency, :string

    field :file_name, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(document, attrs \\ %{}) do
    document
    |> cast(attrs, [
      :seller,
      :sale_date,
      :issue_date,
      :due_date,
      :total_amount,
      :currency,
      :file_name
    ])
  end
end
