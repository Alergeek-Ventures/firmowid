defmodule Firmowid.Ash.Core.User.Actions.UpdateCurrentProfile do
  @moduledoc "Updates profile fields for the action actor."

  alias Firmowid.Ash.Core.User

  @doc "Updates the action actor with the supplied profile attributes."
  @spec run(Ash.ActionInput.t(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, User.t()} | {:error, term()}
  def run(input, context) do
    Ash.update(context.actor, profile_attributes(input.arguments),
      action: :update_profile,
      actor: context.actor,
      tenant: context.tenant
    )
  end

  defp profile_attributes(arguments) do
    arguments
    |> Map.take([
      :name,
      :employment_date,
      :phone,
      :slack_id,
      :bank_account_number,
      :position,
      :correspondence_street,
      :correspondence_city,
      :correspondence_code,
      :residence_street,
      :residence_city,
      :residence_code
    ])
    |> Enum.reject(fn {_field, value} -> is_nil(value) end)
    |> Map.new()
  end
end
