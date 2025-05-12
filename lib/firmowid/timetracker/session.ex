defmodule Firmowid.Timetracker.Session do
  use Firmowid.Schema
  import Ecto.Changeset
  alias Firmowid.Timetracker
  alias Firmowid.Repo

  schema "sessions" do
    field :title, :string
    field :start_datetime, :utc_datetime, autogenerate: {DateTime, :utc_now}
    field :end_datetime, :utc_datetime

    belongs_to :user, Firmowid.Accounts.User
    belongs_to :project, Firmowid.Timetracker.Project
    belongs_to :organization, Firmowid.Accounts.Organization
    timestamps()
  end

  @doc false
  def changeset(session, attrs \\ %{}) do
    session
    |> cast(attrs, [:user_id, :title, :start_datetime, :end_datetime, :project_id])
    |> validate_required([:user_id, :title, :start_datetime, :project_id])
    |> validate_datetime_order()
    |> validate_user_has_access_to_project()
    |> put_change(:organization_id, Repo.get_org_id())
  end

  def maybe_put_start_datetime(changeset) do
    case get_change(changeset, :start_datetime) do
      nil -> put_change(changeset, :start_datetime, DateTime.utc_now())
      _ -> changeset
    end
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

  @spec validate_user_has_access_to_project(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_datetime_order(changeset) do
    start_datetime = get_field(changeset, :start_datetime)
    end_datetime = get_field(changeset, :end_datetime)

    if end_datetime && DateTime.compare(start_datetime, end_datetime) == :gt do
      add_error(changeset, :start_datetime, "Start datetime must be before end datetime")
    else
      changeset
    end
  end

  def put_duration(nil), do: nil

  def put_duration(session) do
    duration = calculate_session_duration(session)
    session |> Map.put(:duration, duration)
  end

  def calculate_session_duration(session) do
    end_datetime =
      case session.end_datetime do
        nil -> DateTime.now!("Europe/Warsaw")
        end_datetime -> end_datetime |> DateTime.shift_zone!("Europe/Warsaw")
      end

    start_datetime = session.start_datetime |> DateTime.shift_zone!("Europe/Warsaw")

    DateTime.diff(end_datetime, start_datetime, :second)
  end
end
