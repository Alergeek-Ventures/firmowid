defmodule Firmowid.Core.User.Actions.UpdateCurrentProfile do
  @moduledoc "Updates the action actor's member: name and profile details."

  alias Firmowid.Core
  alias Firmowid.Core.User

  @doc "Updates the action actor's member with the supplied profile attributes."
  @spec run(Ash.ActionInput.t(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, User.t()} | {:error, term()}
  def run(input, context) do
    opts = Ash.Context.to_opts(context)

    attributes =
      input.arguments |> Enum.reject(fn {_field, value} -> is_nil(value) end) |> Map.new()

    with {:ok, member} <- Core.update_member_profile(context.actor.member, attributes, opts) do
      {:ok, %{context.actor | member: member}}
    end
  end
end
