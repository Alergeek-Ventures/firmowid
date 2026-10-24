defmodule FirmowidWeb.Analysis.Utilities.CategoryColors do
  @moduledoc "Stable category colors shared by analysis entries and their category selectors."

  alias Firmowid.Ash.Analysis.CategoryTotals

  @palette ~w(#0072B2 #E69F00 #009E73 #CC79A7 #D55E00 #56B4E9 #6F4C9B #B6A800 #E5383B #00A6A6 #845B32 #F285B5)

  @doc "Assigns the same project colors regardless of the selected month or entry amounts."
  @spec for_definitions([map()]) :: %{CategoryTotals.category_key() => String.t()}
  def for_definitions(tag_definitions) do
    tag_definitions
    |> Enum.sort_by(& &1.id)
    |> Enum.with_index()
    |> Map.new(fn {definition, index} ->
      {{:project, definition.id}, Enum.at(@palette, rem(index, length(@palette)))}
    end)
    |> Map.merge(%{
      company: "#334155",
      taxes: "#111827",
      unassigned: "#CBD5E1"
    })
  end
end
