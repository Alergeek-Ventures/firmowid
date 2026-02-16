defmodule Firmowid.Timetracker.Session do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  alias Firmowid.Repo
  alias Firmowid.Timetracker

  require Ecto.Query

  schema "sessions" do
    field :title, :string
    field :start_datetime, :utc_datetime, autogenerate: {DateTime, :utc_now}
    field :end_datetime, :utc_datetime
    field :is_remote, :boolean, default: false

    field :lockdown, :boolean, virtual: true

    belongs_to :user, Firmowid.Accounts.User
    belongs_to :project, Firmowid.Timetracker.Project
    belongs_to :organization, Firmowid.Accounts.Organization
    timestamps()
  end

  @doc false
  def changeset(session, attrs \\ %{}) do
    session
    |> cast(attrs, [:user_id, :title, :start_datetime, :end_datetime, :project_id, :is_remote])
    |> validate_required([:user_id, :title, :start_datetime, :project_id, :is_remote])
    |> validate_datetime_order()
    |> prepare_changes(&ensure_user_has_access_to_project/1)
    |> put_change(:organization_id, Repo.get_org_id())
  end

  defp ensure_user_has_access_to_project(changeset) do
    user_id = get_field(changeset, :user_id)
    project_id = get_change(changeset, :project_id)

    if project_id == nil do
      changeset
    else
      Ecto.Query.from(pu in Timetracker.ProjectUser,
        where: pu.user_id == ^user_id and pu.project_id == ^project_id,
        join: p in Timetracker.Project,
        on: p.id == pu.project_id and is_nil(p.archived_at)
      )
      |> Repo.exists?()
      |> case do
        true -> changeset
        false -> add_error(changeset, :project_id, "User does not have access to this project")
      end
    end
  end

  defp validate_datetime_order(changeset) do
    start_datetime = get_field(changeset, :start_datetime)
    end_datetime = get_field(changeset, :end_datetime)

    if end_datetime && DateTime.after?(start_datetime, end_datetime) do
      add_error(changeset, :start_datetime, "Start datetime must be before end datetime")
    else
      changeset
    end
  end

  def put_duration(nil), do: nil

  def put_duration(session) do
    duration = calculate_session_duration(session)
    Map.put(session, :duration, duration)
  end

  def calculate_session_duration(session) do
    end_datetime = session.end_datetime || DateTime.utc_now()

    DateTime.diff(end_datetime, session.start_datetime, :second)
  end

  def put_lockdown(nil), do: nil

  def put_lockdown(session) do
    is_lockdown = Timetracker.submitted_hours_record?(session.user_id, session.start_datetime)
    Map.put(session, :lockdown, is_lockdown)
  end

  def put_lockdowns(nil), do: nil
  def put_lockdowns([]), do: []

  def put_lockdowns(sessions) when is_list(sessions) do
    user_id = Enum.at(sessions, 0).user_id
    dates = Enum.map(sessions, & &1.start_datetime)

    user_id
    |> Timetracker.submitted_hours_records_multiple_dates?(dates)
    |> Enum.zip(sessions)
    |> Enum.map(fn {is_lockdown, session} ->
      Map.put(session, :lockdown, is_lockdown)
    end)
  end
end
