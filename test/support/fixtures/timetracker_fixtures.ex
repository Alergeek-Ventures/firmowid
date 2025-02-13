defmodule Firmowid.TimetrackerFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Firmowid.Timetracker` context.
  """

  alias Firmowid.Timetracker

  def unique_project_name, do: "project_#{System.unique_integer()}"

  def project_fixture(attrs \\ %{}) do
    {:ok, project} =
      attrs
      |> Enum.into(%{
        name: unique_project_name(),
        description: "some description"
      })
      |> Timetracker.create_project()

    project
  end

  def session_fixture(attrs \\ %{}) do
    {:ok, session} =
      attrs
      |> Enum.into(%{
        title: "Test Session",
        project_id: attrs[:project_id] || project_fixture().id,
        user_id: attrs[:user_id],
        start_datetime: attrs[:start_datetime] || DateTime.utc_now()
      })
      |> Timetracker.start_session()

    # If end_datetime is provided, end the session
    if attrs[:end_datetime] do
      {:ok, session} = Timetracker.end_session(session.id)
      session
    else
      session
    end
  end

  def user_project_fixture(user_id, project_id) do
    {:ok, _project} = Timetracker.add_user_to_project(user_id, project_id)
  end

  @doc """
  Generate a hours_record.
  """
  def hours_record_fixture(attrs \\ %{}) do
    {:ok, hours_record} =
      attrs
      |> Enum.into(%{
        month: 42,
        number_of_hours: 42,
        year: 42
      })
      |> Firmowid.Timetracker.create_hours_record()

    hours_record
  end
end
