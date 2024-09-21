defmodule Firmowid.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents) do
      add :seller, :string

      add :sale_date, :date
      add :issue_date, :date
      add :due_date, :date

      add :total_amount, :float
      add :currency, :string

      add :description, :string

      add :file_name, :string

      add :skip_invoicing, :boolean, default: false

      timestamps(type: :utc_datetime)
    end
  end
end
