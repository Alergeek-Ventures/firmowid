defmodule Firmowid.Ash.Delegations.Validations.ExpenseDetailsMatchKind do
  @moduledoc "Ensures an expense category and its typed details agree."

  use Ash.Resource.Validation

  alias Firmowid.Ash.Delegations.DelegationExpense.AccommodationDetails
  alias Firmowid.Ash.Delegations.DelegationExpense.OtherDetails
  alias Firmowid.Ash.Delegations.DelegationExpense.TransportDetails

  @impl true
  def validate(changeset, _opts, _context) do
    kind = Ash.Changeset.get_attribute(changeset, :kind)
    details = Ash.Changeset.get_attribute(changeset, :details)

    if matches?(kind, details),
      do: :ok,
      else: {:error, field: :details, message: "nie pasują do kategorii wydatku"}
  end

  defp matches?(:transport, %Ash.Union{value: %TransportDetails{}}), do: true
  defp matches?(:accommodation, %Ash.Union{value: %AccommodationDetails{}}), do: true
  defp matches?(:other, %Ash.Union{value: %OtherDetails{}}), do: true
  defp matches?(:transport, %TransportDetails{}), do: true
  defp matches?(:accommodation, %AccommodationDetails{}), do: true
  defp matches?(:other, %OtherDetails{}), do: true
  defp matches?(_, _), do: false
end
