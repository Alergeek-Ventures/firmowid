defmodule :"Elixir.Firmowid.Repo.Migrations.Add isRemote to sessions" do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :is_remote, :boolean, default: false
    end
  end
end
