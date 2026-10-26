defmodule FirmowidWeb.Analysis.Utilities.Navigation do
  @moduledoc """
  Canonical navigation contract for the analysis dashboard.
  """

  use FirmowidWeb, :verified_routes

  alias Firmowid.Ash.Analysis.ProjectProfitability
  alias FirmowidWeb.Infrastructure.Utilities.QueryParams

  @type tag_filter :: {:company} | {:taxes} | {:project, String.t()}
  @type view ::
          %{view: :tagging, month: Date.t()}
          | %{view: :dashboard, year: pos_integer(), month: Date.t() | nil}
          | %{view: :categories, year: pos_integer()}
          | %{
              view: :matrix,
              year: pos_integer(),
              allocation: ProjectProfitability.allocation_basis(),
              metric: :net | :direct,
              month: Date.t() | nil,
              project: String.t() | :company | :residual | nil
            }

  @doc """
  Builds the dashboard path with the selected month's details.
  """
  @spec dashboard_path(Date.t(), [tag_filter()]) :: String.t()
  def dashboard_path(%Date{} = month, tag_filters \\ []) when is_list(tag_filters) do
    view_path(%{view: :dashboard, year: month.year, month: month}, tag_filters)
  end

  @doc """
  Builds the canonical path of the dashboard, project matrix, categories or monthly tagging.
  """
  @spec view_path(view(), [tag_filter()]) :: String.t()
  def view_path(view, tag_filters) when is_list(tag_filters) do
    query_params =
      case tag_filters do
        [] -> view_query(view)
        filters -> view_query(view) ++ [tagi: Enum.map_join(filters, ",", &encode_tag_key/1)]
      end

    ~p"/analiza?#{query_params}"
  end

  @doc """
  Parses the selected view from raw route params.

  Invalid values fall back to the current year, income allocation and net result.
  A selected dashboard or matrix month must belong to the selected year.
  """
  @spec parse_view(map()) :: view()
  def parse_view(%{"tryb" => "tagowanie"} = params), do: %{view: :tagging, month: parse_month(params)}

  def parse_view(%{"tryb" => "kategorie"} = params), do: %{view: :categories, year: parse_year(params)}

  def parse_view(%{"tryb" => "macierz"} = params) do
    year = parse_year(params)

    allocation =
      if params["podzial"] == "koszty_bezposrednie", do: :direct_expenses, else: :income

    %{
      view: :matrix,
      year: year,
      allocation: allocation,
      metric: if(params["wartosc"] == "bez_narzutow", do: :direct, else: :net),
      month: selected_month(params, year),
      project: parse_project(params["projekt"])
    }
  end

  def parse_view(params) do
    year = parse_year(params)
    %{view: :dashboard, year: year, month: selected_month(params, year)}
  end

  @doc "Parses a matrix cell selection without changing the current allocation or metric."
  @spec parse_matrix_selection(pos_integer(), String.t(), String.t()) ::
          {:ok, %{month: Date.t() | nil, project: String.t() | :company | :residual}} | :error
  def parse_matrix_selection(year, month, project) do
    selected_month = selected_month(%{"miesiac" => month}, year)
    selected_project = parse_project(project)

    if selected_project != nil and (month == "rok" or selected_month != nil),
      do: {:ok, %{month: selected_month, project: selected_project}},
      else: :error
  end

  @doc """
  Parses a single raw tag-filter key from the analysis URL.
  """
  @spec parse_tag_filter(String.t() | nil) :: tag_filter() | :invalid
  def parse_tag_filter("firma"), do: {:company}
  def parse_tag_filter("podatki"), do: {:taxes}
  def parse_tag_filter("projekt:" <> id), do: {:project, id}
  def parse_tag_filter(_raw_tag_filter), do: :invalid

  @doc """
  Parses and validates analysis tag filters from raw route params.
  """
  @spec parse_tag_filters(map(), list()) :: [tag_filter()]
  def parse_tag_filters(%{"tagi" => tags_param}, tag_definitions)
      when is_binary(tags_param) and is_list(tag_definitions) do
    valid_project_ids = MapSet.new(tag_definitions, & &1.id)

    tags_param
    |> String.split(",", trim: true)
    |> Enum.map(&parse_tag_filter/1)
    |> Enum.reject(&(&1 == :invalid))
    |> Enum.filter(fn
      {:company} -> true
      {:taxes} -> true
      {:project, id} -> MapSet.member?(valid_project_ids, id)
    end)
  end

  def parse_tag_filters(_params, _tag_definitions), do: []

  defp parse_month(%{"miesiac" => value} = params) when is_binary(value) do
    QueryParams.parse_date(params, "miesiac", Date.beginning_of_month(Date.utc_today()))
  end

  defp parse_month(_params), do: Date.beginning_of_month(Date.utc_today())

  # YearSummary accepts years 1-9999; other values fall back like an invalid month.
  defp parse_year(params) do
    case QueryParams.parse_integer(params, "rok", nil) do
      year when year in 1..9999 -> year
      _invalid -> Date.utc_today().year
    end
  end

  defp selected_month(%{"miesiac" => value} = params, year) when is_binary(value) do
    case QueryParams.parse_date(params, "miesiac", nil) do
      %Date{year: ^year} = month -> Date.beginning_of_month(month)
      _ -> nil
    end
  end

  defp selected_month(_params, _year), do: nil

  defp parse_project("firma"), do: :company
  defp parse_project("poza_projektami"), do: :residual

  defp parse_project(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp parse_project(_), do: nil

  defp view_query(%{view: :tagging, month: month}), do: [tryb: "tagowanie", miesiac: Date.to_iso8601(month)]

  defp view_query(%{view: :dashboard, year: year, month: month}), do: with_month([rok: year], month)

  defp view_query(%{view: :categories, year: year}), do: [tryb: "kategorie", rok: year]

  defp view_query(%{view: :matrix} = view) do
    query = [tryb: "macierz", rok: view.year]

    query =
      if view.allocation == :direct_expenses,
        do: query ++ [podzial: "koszty_bezposrednie"],
        else: query

    query = if view.metric == :direct, do: query ++ [wartosc: "bez_narzutow"], else: query
    query = with_month(query, view.month)

    case view.project do
      nil -> query
      :company -> query ++ [projekt: "firma"]
      :residual -> query ++ [projekt: "poza_projektami"]
      id -> query ++ [projekt: id]
    end
  end

  defp with_month(query, nil), do: query
  defp with_month(query, month), do: query ++ [miesiac: Date.to_iso8601(month)]

  defp encode_tag_key({:company}), do: "firma"
  defp encode_tag_key({:taxes}), do: "podatki"
  defp encode_tag_key({:project, id}), do: "projekt:#{id}"
end
