defmodule Firmowid.Timetracker.Project do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "projects" do
    field :name, :string

    many_to_many :users,
                 Firmowid.Accounts.User,
                 join_through: "projects_users"

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :organization_id])
    |> validate_required([:name, :organization_id])
  end
end
