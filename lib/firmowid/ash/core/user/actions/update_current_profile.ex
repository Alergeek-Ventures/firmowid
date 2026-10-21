defmodule Firmowid.Ash.Core.User.Actions.UpdateCurrentProfile do
  @moduledoc "Updates the action actor's name and their member's profile details."

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User

  @member_fields [
    :phone,
    :slack_url,
    :bank_account_number,
    :birthday,
    :birthday_visibility,
    :correspondence_address,
    :residence_address,
    :is_same_correspondence_address
  ]

  @doc "Updates the action actor and their member with the supplied profile attributes."
  @spec run(Ash.ActionInput.t(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, User.t()} | {:error, term()}
  def run(input, context) do
    opts = Ash.Context.to_opts(context)

    arguments =
      input.arguments |> Enum.reject(fn {_field, value} -> is_nil(value) end) |> Map.new()

    {member_attributes, user_attributes} = Map.split(arguments, @member_fields)

    with {:ok, user} <- Core.update_profile(context.actor, user_attributes, opts),
         {:ok, member} <-
           Core.update_member_profile(context.actor.member, member_attributes, opts) do
      {:ok, %{user | member: member}}
    end
  end
end
