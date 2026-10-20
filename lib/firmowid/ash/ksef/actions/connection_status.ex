defmodule Firmowid.Ash.Ksef.Actions.ConnectionStatus do
  @moduledoc "Projects KSeF connection metadata for authorized invoice readers without loading secrets."

  use Ash.Resource.Actions.Implementation

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Ksef.Credential
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor

  @impl true
  def run(_input, _opts, %{actor: %User{organization_id: tenant, member: %{role: role}}, tenant: tenant})
      when is_binary(tenant) do
    scope = %Scope{actor: %SystemActor{org_id: tenant, role: :ksef_session}, tenant: tenant}

    # Authorization precedes this tenant-bound privileged projection; selecting metadata
    # keeps encrypted credentials out of the read and never grants readers credential access.
    with {:ok, credential} <-
           Credential.get_internal(
             scope: scope,
             query: [select: [:status, :auth_type, :expires_on]]
           ) do
      {:ok, project(credential, role == :admin)}
    end
  end

  # This must also reject mismatched tenants for admins, whose policy bypass is global.
  def run(_input, _opts, _context), do: {:error, Ash.Error.Forbidden.exception([])}

  defp project(nil, can_connect) do
    %{status: :disconnected, can_connect: can_connect, data_freshness: :unknown}
  end

  defp project(credential, can_connect) do
    %{
      status: connection_status(credential),
      can_connect: can_connect,
      auth_method: credential.auth_type,
      expires_on: credential.expires_on,
      data_freshness: :unknown
    }
  end

  defp connection_status(%{status: status, expires_on: expires_on}) when status in [:working, :refreshing] do
    if expires_on && Date.before?(expires_on, Date.utc_today()), do: :expired, else: :connected
  end

  defp connection_status(%{status: status})
       when status in [:authenticating, :authenticating_epuap, :preparing_enrollment, :wait_for_certificate],
       do: :connecting
end
