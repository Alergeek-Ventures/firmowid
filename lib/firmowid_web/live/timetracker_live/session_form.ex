defmodule FirmowidWeb.TimetrackerLive.SessionForm do
  use Firmowid.Schema

  import Ecto.Changeset

  embedded_schema do
    field :title, :string
    field :date, :date
    field :start_time, :time
    field :end_time, :time
    field :project_id, :binary_id
  end

  def changeset(attrs \\ %{}) do
    changeset(%__MODULE__{}, attrs)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:title, :date, :start_time, :end_time, :project_id])
    |> validate_required([:title, :project_id])
    |> maybe_put(:date, DateTime.now!("Europe/Warsaw") |> DateTime.to_date())
    |> maybe_put(:start_time, DateTime.now!("Europe/Warsaw") |> DateTime.to_time())
    |> validate_end_time_after_start_time()
  end

  def attributes(changeset, user_id) do
    form = changeset |> apply_action(:create)

    case form do
      {:ok, form} ->
        {:ok, form |> Map.from_struct() |> convert_times() |> Map.put(:user_id, user_id)}

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

  defp convert_times(%{start_time: start_time, end_time: end_time, date: date} = attributes) do
    start_time = date_to_datetime(date, start_time)

    # This allows for adding sessions which cross midnight
    end_time =
      if end_time && Time.before?(end_time, start_time) do
        date_to_datetime(Date.add(date, 1), end_time)
      else
        date_to_datetime(date, end_time)
      end

    Map.put(attributes, :start_datetime, start_time)
    |> Map.put(:end_datetime, end_time)
    |> Map.drop([:start_time, :end_time, :date])
  end

  defp date_to_datetime(_, nil), do: nil

  defp date_to_datetime(nil, _), do: nil

  defp date_to_datetime(date, time) do
    NaiveDateTime.new!(date, time)
    |> DateTime.from_naive!("Europe/Warsaw")
  end

  defp validate_end_time_after_start_time(changeset) do
    start_time = get_change(changeset, :start_time)
    end_time = get_change(changeset, :end_time)

    case {start_time, end_time} do
      {nil, _} ->
        changeset

      {_, nil} ->
        changeset

      {start_time, end_time} when start_time > end_time ->
        add_error(changeset, :end_time, "End time must be after start time")

      _ ->
        changeset
    end
  end
end
