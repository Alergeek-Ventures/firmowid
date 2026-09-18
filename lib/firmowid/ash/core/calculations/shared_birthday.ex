defmodule Firmowid.Ash.Core.Calculations.SharedBirthday do
  @moduledoc """
  Provides shared birthday information for a user, based on their birthday and birthday_visibility fields.
  """
  use Ash.Resource.Calculation

  @impl true
  def load(_, _, _), do: [:birthday, :birthday_visibility]

  @impl true
  def calculate(records, _, _) do
    {:ok,
     Enum.map(records, fn record ->
       case {record.birthday, record.birthday_visibility} do
         {nil, _} -> nil
         {_, :not_shared} -> nil
         {bday, :day_with_month} -> %{day: bday.day, month: bday.month}
         {bday, :full_date} -> %{day: bday.day, month: bday.month, year: bday.year}
       end
     end)}
  end
end
