defmodule Firmowid.Timetracker.Session do
  use Firmowid.Schema
  import Ecto.Changeset
  alias Firmowid.Timetracker
  alias Firmowid.Repo
  require Ecto.Query

  schema "sessions" do
    field :title, :string
    field :start_datetime, :utc_datetime, autogenerate: {DateTime, :utc_now}
    field :end_datetime, :utc_datetime

    field :lockdown, :boolean, virtual: true

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

  # this should be called in transaction if we are creating or updating session - race condition
  @spec validate_user_has_access_to_project(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_user_has_access_to_project(changeset) do
    user_id = get_field(changeset, :user_id)
    project_id = get_change(changeset, :project_id)

    if project_id == nil do
      changeset
    else
      Ecto.Query.from(pu in Timetracker.ProjectUser,
        where: pu.user_id == ^user_id and pu.project_id == ^project_id
      )
      |> Repo.exists?()
      |> case do
        true -> changeset
        false -> changeset |> add_error(:project_id, "User does not have access to this project")
      end
    end
  end

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
