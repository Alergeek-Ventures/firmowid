defmodule Firmowid.Repo.Migrations.RenameIdentificationNumberToNip do
  use Ecto.Migration

  def change do
    rename table(:organizations), :identification_number, to: :nip
  end
end
