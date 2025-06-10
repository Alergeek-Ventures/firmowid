defmodule FirmowidWeb.Components.Timetracker.UserProfileSummary do
  use FirmowidWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp format_hourly_rate(nil), do: "Brak stawki"

  defp format_hourly_rate(hourly_rate) do
    "#{Decimal.to_string(hourly_rate)} PLN/h"
  end

  defp format_total_salary(nil, _user_hours), do: "Brak stawki"
  defp format_total_salary(_hourly_rate, nil), do: "0 PLN"

  defp format_total_salary(hourly_rate, user_hours) do
    hours = user_hours.time_worked / 60 / 60
    total_salary = Decimal.mult(hourly_rate, Decimal.from_float(hours))
    rounded_salary = Decimal.round(total_salary, 2)
    "#{Decimal.to_string(rounded_salary)} PLN"
  end

  defp get_current_hourly_rate(user) do
    case user.current_salary do
      nil -> nil
      salary -> salary.hourly_rate
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-4">
      <div class="grid grid-cols-3 gap-4">
        <div>
          <div class="text-sm font-medium text-darkGrey uppercase mb-1">Łączny czas</div>
          <div class="font-medium text-lg">
            <%= if @user_hours do %>
              {trunc(@user_hours.time_worked / 60 / 60)} h
            <% else %>
              0 h
            <% end %>
          </div>
        </div>
        <div>
          <div class="text-sm font-medium text-darkGrey uppercase mb-1">Stawka</div>
          <div class="font-medium text-lg">{format_hourly_rate(get_current_hourly_rate(@user))}</div>
        </div>
        <div class="flex flex-col items-end pr-2">
          <div class="text-sm font-medium text-darkGrey uppercase mb-1">Wynagrodzenie</div>
          <div class="font-bold text-lg">
            {format_total_salary(get_current_hourly_rate(@user), @user_hours)}
          </div>
        </div>
      </div>
    </div>
    """
  end
end
