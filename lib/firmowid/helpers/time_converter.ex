defmodule Firmowid.Helpers.TimeConverter do
  @moduledoc """
  Helper functions for converting time durations.
  """

  def time_worked_to_hours(seconds) when is_integer(seconds) do
    ceil(seconds / 3600)
  end
end
