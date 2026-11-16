defmodule Firmowid.Finances.RecipientName do
  @moduledoc """
  Compares an employee's name with the name a bank wrote on a transfer.

  Banks write names in any order and case, with or without diacritics and with extra words such
  as a company name, so names are compared as sets of words.
  """

  @partial_similarity 0.9

  @doc """
  Splits a name into sorted, unique, lower-case ASCII words, without initials.
  """
  @spec parts(String.t() | nil) :: [String.t()]
  def parts(nil), do: []

  def parts(name) do
    name
    |> AnyAscii.transliterate()
    |> IO.iodata_to_binary()
    |> String.downcase()
    |> String.split(~r/[^a-z]+/, trim: true)
    |> Enum.reject(&(String.length(&1) == 1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Ranks how well an employee's name matches the transfer's name words: 2 when every word of a
  name of at least two words is there, 1 for one shared or nearly equal word, 0 otherwise.
  """
  @spec rank(String.t() | nil, [String.t()]) :: 0..2
  def rank(name, recipient_parts) do
    employee_parts = parts(name)

    cond do
      employee_parts == [] or recipient_parts == [] ->
        0

      length(employee_parts) >= 2 and
          MapSet.subset?(MapSet.new(employee_parts), MapSet.new(recipient_parts)) ->
        2

      Enum.any?(employee_parts, &(&1 in recipient_parts)) ->
        1

      true ->
        similarity =
          employee_parts
          |> Enum.join(" ")
          |> Akin.compare(Enum.join(recipient_parts, " "), algorithms: ["jaro_winkler"])
          |> Map.fetch!(:jaro_winkler)

        if similarity >= @partial_similarity, do: 1, else: 0
    end
  end
end
