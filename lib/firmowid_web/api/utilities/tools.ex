defmodule FirmowidWeb.Api.Utilities.Tools do
  @moduledoc """
  The operations of the public API: the AshAi tools of `Firmowid.AiTools.api/0`, the same tools
  the MCP server exposes, so both interfaces share their contracts, policies and execution.
  """

  alias Firmowid.AiTools
  alias Firmowid.Core.ServiceAccount

  @doc """
  Returns the tools the actor's role may call in the organization, like the MCP tool list. A
  company key's account gets none of the tools that act as a person.
  """
  @spec for_actor(term(), binary() | nil) :: [%AshAi.Tool{}]
  def for_actor(%ServiceAccount{} = actor, tenant), do: exposed(AiTools.company_api(), actor, tenant)

  def for_actor(actor, tenant), do: exposed(AiTools.api(), actor, tenant)

  @doc """
  Returns the tools the documentation describes: those the admin role, the widest a key can
  have, may call, including the ones only a personal key gets. Policies are only pre-checked, so
  the made-up organization is never read.
  """
  @spec documented() :: [%AshAi.Tool{}]
  def documented,
    do:
      exposed(
        AiTools.api(),
        %ServiceAccount{id: Ecto.UUID.generate(), role: :admin, organization_id: Ecto.UUID.generate()},
        nil
      )

  @doc "Whether the API has a tool with this name, whatever the actor's role."
  @spec known?(String.t()) :: boolean()
  def known?(name), do: Enum.any?(AiTools.api(), &(Atom.to_string(&1) == name))

  defp exposed(tools, actor, tenant),
    do: AshAi.exposed_tools(otp_app: :firmowid, tools: tools, actor: actor, tenant: tenant)
end
