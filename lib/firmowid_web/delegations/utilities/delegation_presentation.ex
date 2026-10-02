defmodule FirmowidWeb.Delegations.Utilities.DelegationPresentation do
  @moduledoc "Presentation helpers shared by employee and management delegation lists."

  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter

  @spec status_label(atom()) :: String.t()
  def status_label(:pending), do: "oczekiwanie"
  def status_label(:in_progress), do: "w toku"
  def status_label(:complete), do: "zakończono"

  @spec status_badge_styles(atom()) :: list(String.t())
  def status_badge_styles(:pending), do: ["bg-turquoise-100 text-turquoise-700"]
  def status_badge_styles(:in_progress), do: ["bg-green-200/80 text-green-700"]
  def status_badge_styles(:complete), do: ["bg-grey-100 text-grey-700"]

  @spec format_range(Date.t(), Date.t()) :: String.t()
  def format_range(start_date, end_date), do: TimeFormatter.format_date_range(start_date, end_date)

  @spec format_date(Date.t()) :: String.t()
  def format_date(date), do: Calendar.strftime(date, "%d.%m.%Y")
end
