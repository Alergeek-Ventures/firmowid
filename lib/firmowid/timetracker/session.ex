defmodule Firmowid.Timetracker.Session do
  use Firmowid.Schema
  import Ecto.Changeset
  alias Firmowid.Timetracker
  alias Firmowid.Repo

  schema "sessions" do
    field :title, :string
    field :start_time, :utc_datetime, autogenerate: {DateTime, :utc_now}
    field :end_time, :utc_datetime

    belongs_to :user, Firmowid.Accounts.User
    belongs_to :project, Firmowid.Timetracker.Project
    belongs_to :organization, Firmowid.Accounts.Organization
    timestamps()
  end

  @doc false
  def changeset(session, attrs \\ %{}) do
    session
    |> cast(attrs, [:user_id, :title, :start_time, :end_time, :project_id])
    |> validate_required([:user_id, :title, :start_time, :project_id])
    |> validate_user_has_access_to_project()
    |> put_change(:organization_id, Repo.get_org_id())
  end

  @spec validate_user_has_access_to_project(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_user_has_access_to_project(changeset) do
    project_id = get_field(changeset, :project_id)
    user_id = get_field(changeset, :user_id)

    user_projects =
      case user_id do
        nil -> []
        _ -> Timetracker.list_user_projects(user_id)
      end

    case Enum.find(user_projects, &(&1.id == project_id)) do
      nil -> add_error(changeset, :project_id, "User does not have access to this project")
      _ -> changeset
    end
  end
end
