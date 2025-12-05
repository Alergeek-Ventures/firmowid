defmodule Firmowid.Repo.Migrations.AddUserProfileDetailsFields do
  use Ecto.Migration

  def change do
    # Create enum type for employment contract types
    execute(
      "CREATE TYPE employment_contract_type AS ENUM ('umowa_o_prace', 'umowa_zlecenie', 'umowa_o_dzielo', 'b2b')",
      "DROP TYPE employment_contract_type"
    )

    alter table(:users) do
      # Contact information
      add :phone, :string
      add :slack_url, :string
      add :slack_id, :string

      # Personal information
      add :birthday, :date
      add :student_status_until, :date
      add :bank_account_number, :string
      add :position, :string

      # Employment information
      add :employment_contract_type, :employment_contract_type

      # Address information
      add :correspondence_street, :string
      add :correspondence_city, :string
      add :correspondence_code, :string
      add :residence_street, :string
      add :residence_city, :string
      add :residence_code, :string
    end
  end
end
