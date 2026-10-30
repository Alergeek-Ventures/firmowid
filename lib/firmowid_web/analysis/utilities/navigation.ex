defmodule FirmowidWeb.Analysis.Utilities.Navigation do
  @moduledoc """
  Canonical navigation contract for the analysis dashboard.
  """

  use FirmowidWeb, :verified_routes

  alias FirmowidWeb.Infrastructure.Utilities.QueryParams

  @type tag_filter :: {:company} | {:taxes} | {:project, String.t()}
  @typedoc "First and last month of the analysed period."
  @type period :: {Date.t(), Date.t()}
  @type view ::
          %{view: :dashboard, period: period(), month: Date.t() | nil}
          | %{view: :segments, period: period()}

  # The chart shows one bar per month, so a longer period keeps its latest months.
  @max_months 36

  @doc """
  Builds the dashboard path with the given month's details within its year.
  """
  @spec dashboard_path(Date.t(), [tag_filter()]) :: String.t()
  def dashboard_path(%Date{} = month, tag_filters \\ []) when is_list(tag_filters) do
    month = Date.beginning_of_month(month)
    view_path(%{view: :dashboard, period: year_period(month.year), month: month}, tag_filters)
  end

  @doc "The calendar year of `year` as a period, the default one."
  @spec year_period(pos_integer()) :: period()
  def year_period(year), do: {Date.new!(year, 1, 1), Date.new!(year, 12, 1)}

  @doc "The period's months, first to last."
  @spec months(period()) :: [Date.t()]
  def months({from, to}) do
    from
    |> Stream.iterate(&Date.shift(&1, month: 1))
    |> Enum.take_while(&(Date.compare(&1, to) != :gt))
  end

  @doc """
  Builds the canonical path of the dashboard or the projects view.
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

  The period runs from month `od` to month `do` (`do` defaults to `od`), at
  most #{@max_months} months; without a valid `od` it is the current year. A
  dashboard `miesiac` within the period selects that month's details.
  """
  @spec parse_view(map()) :: view()
  def parse_view(%{"tryb" => "projekty"} = params), do: %{view: :segments, period: parse_period(params)}

  def parse_view(params) do
    {from, to} = period = parse_period(params)
    month = parse_month(params, "miesiac", nil)

    month =
      if month && Date.compare(month, from) != :lt && Date.compare(month, to) != :gt, do: month

    %{view: :dashboard, period: period, month: month}
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
    # Projects counted as shared costs are not slices of their own.
    valid_project_ids = tag_definitions |> Enum.reject(& &1.overhead) |> MapSet.new(& &1.id)

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

  defp parse_period(params) do
    from = parse_month(params, "od", nil)
    to = parse_month(params, "do", from)

    case {from, to} do
      {%Date{}, %Date{}} ->
        {from, to} = Enum.min_max_by([from, to], & &1, Date)
        {Enum.max([from, Date.shift(to, month: 1 - @max_months)], Date), to}

      _current_year ->
        year_period(Date.utc_today().year)
    end
  end

  # YearSummary accepts years 1-9999.
  defp parse_month(params, key, default) do
    case is_binary(params[key]) && QueryParams.parse_date(params, key, nil) do
      %Date{year: year} = date when year in 1..9999 -> Date.beginning_of_month(date)
      _invalid -> default
    end
  end

  defp view_query(%{view: :dashboard, period: period, month: month}),
    do: period_query(period) ++ if(month, do: [miesiac: Date.to_iso8601(month)], else: [])

  defp view_query(%{view: :segments, period: period}), do: [tryb: "projekty"] ++ period_query(period)

  defp period_query({from, to}), do: [od: Date.to_iso8601(from), do: Date.to_iso8601(to)]

  defp encode_tag_key({:company}), do: "firma"
  defp encode_tag_key({:taxes}), do: "podatki"
  defp encode_tag_key({:project, id}), do: "projekt:#{id}"
end
