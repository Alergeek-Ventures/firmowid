defmodule FirmowidWeb.Infrastructure.Utilities.PolishQuantity do
  @moduledoc """
  Formats integer quantities using Polish noun declension rules.
  """

  @doc """
  Formats a quantity with its singular, paucal, or plural noun form.

  ## Examples

      iex> FirmowidWeb.Infrastructure.Utilities.PolishQuantity.quantity(1, "jabłko", "jabłka", "jabłek")
      "1 jabłko"

      iex> FirmowidWeb.Infrastructure.Utilities.PolishQuantity.quantity(22, "jabłko", "jabłka", "jabłek")
      "22 jabłka"
  """
  @spec quantity(integer(), String.t(), String.t(), String.t()) :: String.t()
  def quantity(value, singular, paucal, plural) when is_integer(value) do
    "#{value} #{noun_form(value, singular, paucal, plural)}"
  end

  defp noun_form(value, singular, _paucal, _plural) when abs(value) == 1, do: singular

  defp noun_form(value, _singular, _paucal, plural) when rem(abs(value), 100) in 12..14, do: plural

  defp noun_form(value, _singular, paucal, _plural) when rem(abs(value), 10) in 2..4, do: paucal

  defp noun_form(_value, _singular, _paucal, plural), do: plural
end
