defmodule FirmowidWeb.TimetrackerLive.GroupedSessionForm do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias FirmowidWeb.TimetrackerLive.SessionForm

  @primary_key false
  embedded_schema do
    field :title, :string
    field :project_id, :binary_id

    embeds_many :start_end_times, SessionStartEndTime do
      field :date, :date
      field :start_time, :time
      field :end_time, :time
    end
  end

  def changeset(attrs \\ %{}) do
    changeset(%__MODULE__{}, attrs)
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [:title, :project_id])
    |> cast_embed(:start_end_times, with: &start_end_time_changeset/2)
    |> validate_required([:title, :project_id])
    |> validate_length(:start_end_times, min: 1)
  end

  defp start_end_time_changeset(start_end_time, attrs) do
    start_end_time
    |> cast(attrs, [:id, :date, :start_time, :end_time])
    |> validate_required([:id, :date, :start_time])
  end

  def from_sessions(sessions) do
    parent_session = hd(sessions)

    changeset(%{
      title: parent_session.title,
      project_id: parent_session.project_id,
      start_end_times:
        Enum.map(sessions, fn session ->
          %{
            id: session.id,
            date: DateTime.to_date(session.start_datetime),
            start_time: DateTime.to_time(session.start_datetime),
            end_time: session.end_datetime && DateTime.to_time(session.end_datetime)
          }
        end)
    })
  end

  def from_changesets(changesets, %{start_end_times: start_end_times} = form, timezone) do
    Enum.map(changesets, fn changeset ->
      {start_datetime, end_datetime} =
        start_end_times
        |> Enum.find(fn s -> s.id == changeset.data.id end)
        |> SessionForm.times_to_datetimes(timezone)

      changeset
      |> put_change(:title, form.title)
      |> put_change(:project_id, form.project_id)
      |> put_change(:start_datetime, start_datetime)
      |> put_change(:end_datetime, end_datetime)
    end)
  end
end
