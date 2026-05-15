defmodule FirmowidWeb.Timetracker.Utilities.Navigation do
  @moduledoc """
  Canonical navigation contract for timetracker routes.
  """

  use FirmowidWeb, :verified_routes

  @doc """
  Builds the canonical salaries CSV export path.
  """
  @spec salaries_csv_path(Date.t()) :: String.t()
  def salaries_csv_path(%Date{} = date) do
    ~p"/czasosledz/projekty/csv?#{[miesiac: date.month, rok: date.year]}"
  end

  @doc """
  Builds the canonical project CSV export path.
  """
  @spec project_csv_path(Ash.UUID.t() | String.t(), Date.t()) :: String.t()
  def project_csv_path(project_id, %Date{} = date) when is_binary(project_id) do
    ~p"/czasosledz/projekty/#{project_id}/csv?#{[miesiac: date.month, rok: date.year]}"
  end

  @doc """
  Builds the canonical hours-record index path.
  """
  @spec hours_record_index_path(Date.t()) :: String.t()
  def hours_record_index_path(%Date{} = date) do
    ~p"/czasosledz/ewidencja?#{[miesiac: Date.to_iso8601(Date.beginning_of_month(date))]}"
  end
end
