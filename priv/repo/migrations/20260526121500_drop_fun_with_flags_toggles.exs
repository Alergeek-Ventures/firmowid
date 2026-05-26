defmodule Firmowid.Repo.Migrations.DropFunWithFlagsToggles do
  use Ecto.Migration

  @moduledoc """
  Manual cleanup migration for the legacy `fun_with_flags_toggles` table.

  This table is not owned by any Ash resource anymore, so removing it through
  `mix ash.codegen` is not possible. We drop it directly as part of the
  PostHog feature-flag cutover.
  """

  def up do
    drop_if_exists table(:fun_with_flags_toggles)
  end

  def down do
    create table(:fun_with_flags_toggles, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :flag_name, :string, null: false
      add :gate_type, :string, null: false
      add :target, :string, null: false
      add :enabled, :boolean, null: false
    end

    create index(:fun_with_flags_toggles, [:flag_name],
             name: "fun_with_flags_toggles_flag_name_index"
           )

    create unique_index(:fun_with_flags_toggles, [:flag_name, :gate_type, :target],
             name: "fun_with_flags_toggles_flag_name_gate_type_target_index"
           )
  end
end
