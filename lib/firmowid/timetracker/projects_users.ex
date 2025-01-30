defmodule Firmowid.Timetracker.ProjectUser do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "projects_users" do
    belongs_to :project, Firmowid.Timetracker.Project
    belongs_to :user, Firmowid.Accounts.User

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(project_user, attrs \\ %{}) do
    project_user
    |> cast(attrs, [
      :project_id,
      :user_id
    ])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:user_id)
    |> put_change(:organization_id, Repo.get_org_id())
  end
end
