defmodule FirmowidWeb.Api.Utilities.Tools do
  @moduledoc """
  The operations of the public API: the AshAi tools of `Firmowid.AiTools.api/0`, the same tools
  the MCP server exposes, so both interfaces share their contracts, policies and execution.
  """

  alias Firmowid.AiTools
  alias Firmowid.Core.ServiceAccount

  @doc """
  Returns the tools the actor's role may call in the organization, like the MCP tool list.
  """
  @spec for_actor(term(), binary() | nil) :: [%AshAi.Tool{}]
  def for_actor(actor, tenant),
    do: AshAi.exposed_tools(otp_app: :firmowid, tools: AiTools.api(), actor: actor, tenant: tenant)

  @doc """
  Returns the tools the documentation describes: those a company key with the admin role, the
  widest a key can have, may call. Policies are only pre-checked, so its organization is never
  read.
  """
  @spec documented() :: [%AshAi.Tool{}]
  def documented,
    do: for_actor(%ServiceAccount{id: Ecto.UUID.generate(), role: :admin, organization_id: Ecto.UUID.generate()}, nil)

  @doc "Whether the API has a tool with this name, whatever the actor's role."
  @spec known?(String.t()) :: boolean()
  def known?(name), do: Enum.any?(AiTools.api(), &(Atom.to_string(&1) == name))
end
