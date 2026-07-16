defmodule FirmowidWeb.Management.Utilities.CounterpartyHelpers do
  @moduledoc """
  Shared presentation helpers for management counterparty views.
  """

  @doc "Returns the most relevant identifier for a counterparty."
  @spec identifier(map()) :: String.t()
  def identifier(%{type: :individual, pesel: pesel}) when pesel not in [nil, ""], do: pesel
  def identifier(%{tax_id: tax_id}) when tax_id not in [nil, ""], do: tax_id
  def identifier(_counterparty), do: "—"

  @doc "Returns the icon name representing the counterparty type."
  @spec type_icon_name(map()) :: String.t()
  def type_icon_name(%{type: :company}), do: "hero-building-office-2"
  def type_icon_name(_counterparty), do: "hero-user"

  @doc "Returns the legal/full name for a counterparty, without display-name fallback."
  @spec full_name(map()) :: String.t()
  def full_name(%{type: :company, full_name: full_name}) when full_name not in [nil, ""], do: full_name

  def full_name(%{given_name: given_name, surname: surname}) do
    [given_name, surname]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> case do
      "" -> "—"
      value -> value
    end
  end

  def full_name(_counterparty), do: "—"

  def party_label(nil, org), do: format_label(org.name)

  def party_label(%{display_label: label}, org) when label in [nil, ""], do: format_label(org.name)

  def party_label(%{display_label: label}, _org), do: format_label(label)

  defp format_label(label) do
    String.replace(label, ~r/spółka z ograniczoną odpowiedzialnością/iu, "sp. z o.o.")
  end
end
