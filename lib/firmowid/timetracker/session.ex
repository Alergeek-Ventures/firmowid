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
  defp validate_user_has_access_to_project(changeset) do
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

  def put_duration(nil), do: nil

  def put_duration(session) do
    duration = calculate_session_duration(session)
    session |> Map.put(:duration, duration)
  end

  def calculate_session_duration(session) do
    end_time =
      case session.end_time do
        nil -> DateTime.now!("Europe/Warsaw")
        end_time -> end_time |> DateTime.shift_zone!("Europe/Warsaw")
      end

    start_time = session.start_time |> DateTime.shift_zone!("Europe/Warsaw")

    DateTime.diff(end_time, start_time, :minute)
  end
end
