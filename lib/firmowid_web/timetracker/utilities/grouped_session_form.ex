defmodule FirmowidWeb.Timetracker.Utilities.GroupedSessionForm do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :title, :string
    field :project_id, :binary_id
    field :is_remote, :boolean

    embeds_many :start_end_times, SessionStartEndTime do
      field :date, :date
      field :end_date, :date
      field :start_time, :time
      field :end_time, :time
    end
  end

  def changeset(attrs \\ %{}) do
    changeset(%__MODULE__{}, attrs)
  end

  def changeset(form, attrs) do
    form
    |> cast(attrs, [:title, :project_id, :is_remote])
    |> cast_embed(:start_end_times, with: &start_end_time_changeset/2)
    |> validate_required([:title, :project_id])
    |> validate_length(:start_end_times, min: 1)
  end

  defp start_end_time_changeset(start_end_time, attrs) do
    start_end_time
    |> cast(attrs, [:id, :date, :start_time, :end_time, :end_date])
    |> validate_required([:id, :date, :start_time])
  end

  def from_sessions(sessions) do
    parent_session = hd(sessions)

    changeset(%{
      title: parent_session.title,
      project_id: parent_session.project_id,
      is_remote: parent_session.is_remote,
      start_end_times:
        sessions
        |> Enum.sort_by(& &1.start_datetime)
        |> Enum.map(fn session ->
          start_date = DateTime.to_date(session.start_datetime)
          end_date = session.end_datetime && DateTime.to_date(session.end_datetime)

          %{
            id: session.id,
            date: start_date,
            end_date: end_date || start_date,
            start_time: DateTime.to_time(session.start_datetime),
            end_time: session.end_datetime && DateTime.to_time(session.end_datetime)
          }
        end)
    })
  end
end
