defmodule FirmowidWeb.TimetrackerLive.SessionForm do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  embedded_schema do
    field :title, :string
    field :date, :date
    field :start_time, :time
    field :end_time, :time
    field :is_remote, :boolean, default: false
    field :project_id, :binary_id
  end

  def changeset(attrs \\ %{}) do
    changeset(%__MODULE__{}, attrs)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:title, :date, :start_time, :end_time, :is_remote, :project_id])
    |> validate_required([:title, :project_id])
  end

  def attributes(changeset, user_id, timezone) do
    changeset
    |> maybe_put(:date, timezone |> DateTime.now!() |> DateTime.to_date())
    |> maybe_put(:start_time, timezone |> DateTime.now!() |> DateTime.to_time())
    |> apply_action(:create)
    |> case do
      {:ok, form} ->
        {:ok, form |> Map.from_struct() |> convert_times(timezone) |> Map.put(:user_id, user_id)}

      other ->
        other
    end
  end

  defp maybe_put(changeset, field, default) do
    case get_change(changeset, field) do
      nil -> put_change(changeset, field, default)
      _ -> changeset
    end
  end

  defp convert_times(attributes, timezone) do
    {start_datetime, end_datetime} = times_to_datetimes(attributes, timezone)

    attributes
    |> Map.put(:start_datetime, start_datetime)
    |> Map.put(:end_datetime, end_datetime)
    |> Map.drop([:start_time, :end_time, :date])
  end

  def times_to_datetimes(%{start_time: start_time, end_time: end_time, date: date}, timezone) do
    start_datetime = date_to_datetime(date, start_time, timezone)

    # This allows for adding sessions which cross midnight
    end_datetime =
      if end_time && Time.before?(end_time, start_time) do
        date_to_datetime(Date.add(date, 1), end_time, timezone)
      else
        date_to_datetime(date, end_time, timezone)
      end

    {start_datetime, end_datetime}
  end

  defp date_to_datetime(_, nil, _), do: nil

  defp date_to_datetime(date, time, timezone),
    do: date |> DateTime.new!(time, timezone) |> DateTime.shift_zone!("Etc/UTC")
end
