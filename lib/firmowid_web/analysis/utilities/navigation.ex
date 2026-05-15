defmodule FirmowidWeb.Analysis.Utilities.Navigation do
  @moduledoc """
  Canonical navigation contract for the analysis dashboard.
  """

  use FirmowidWeb, :verified_routes

  @type tag_filter :: {:company} | {:project, String.t()}

  @doc """
  Builds the canonical analysis dashboard path.
  """
  @spec dashboard_path(Date.t(), [tag_filter()]) :: String.t()
  def dashboard_path(%Date{} = month, tag_filters \\ []) when is_list(tag_filters) do
    query_params = %{miesiac: Date.to_iso8601(month)}

    query_params =
      case tag_filters do
        [] -> query_params
        filters -> Map.put(query_params, :tagi, Enum.map_join(filters, ",", &encode_tag_key/1))
      end

    ~p"/analiza?#{query_params}"
  end

  @doc """
  Parses a single raw tag-filter key from the analysis URL.
  """
  @spec parse_tag_filter(String.t() | nil) :: tag_filter() | :invalid
  def parse_tag_filter("firma"), do: {:company}
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
      {:project, id} -> MapSet.member?(valid_project_ids, id)
    end)
  end

  def parse_tag_filters(_params, _tag_definitions), do: []

  defp encode_tag_key({:company}), do: "firma"
  defp encode_tag_key({:project, id}), do: "projekt:#{id}"
end
