defmodule Firmowid.Delegations.Validations.HasDateChangeReason do
  @moduledoc "Requires a reason when evidence expands a delegation's date range."

  use Ash.Resource.Validation
  use Gettext, backend: Firmowid.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    if not is_nil(detected_date_change?(changeset)) and
         blank?(Ash.Changeset.get_attribute(changeset, :date_change_reason)) do
      {:error, field: :date_change_reason, message: gettext_noop("This field is required")}
    else
      :ok
    end
  end

  defp detected_date_change?(changeset) do
    Ash.Changeset.get_attribute(changeset, :detected_start_date) ||
      Ash.Changeset.get_attribute(changeset, :detected_end_date)
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false
end
