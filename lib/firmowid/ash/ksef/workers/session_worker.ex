defmodule Firmowid.Ash.Ksef.Workers.SessionWorker do
  @moduledoc """
  Maintains active KSeF sessions with automatic renewal.

  This worker handles:
  - Initial authentication with KSeF credentials
  - Session token management
  - Automatic session renewal before expiry

  The worker uses the organization_id to uniquely identify sessions,
  and the environment is determined from the active credential.
  """

  use Oban.Worker,
    queue: :ksef_sessions,
    max_attempts: 3

  import Ecto.Query

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.Credential
  alias Firmowid.Ash.Ksef.Services.ApiClient
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.SystemActor
  alias Firmowid.Repo

  require Logger

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: Oban.Worker.result()
  def perform(%Oban.Job{args: %{"organization_id" => organization_id}} = job) do
    actor = %SystemActor{org_id: organization_id, role: :ksef_session}
    scope = %Scope{actor: actor, tenant: organization_id}

    Logger.info("Starting KSeF authentication for organization #{organization_id}")

    with %Credential{} = credential <- Ksef.get_credential(scope),
         {:ok, %{access_token: access_token, refresh_token: refresh_token}} <-
           perform_authentication(credential) do
      Ksef.fetch_cost_invoices(DateTime.shift(DateTime.utc_now(), day: -30), scope)
      schedule_reauthentication!(refresh_token, organization_id)

      Cachex.put(:ksef, {:access_token, organization_id}, access_token, expire: access_token_ttl(access_token))
    else
      nil ->
        Logger.error("No KSeF credentials found for organization #{organization_id}")
        {:cancel, :no_credentials}

      {:error, reason} = error ->
        maybe_unauthenticate(scope, reason, job)
        error
    end
  end

  defp perform_authentication(%Credential{organization_id: org_id, auth_type: :token, credentials: token}) do
    organization = Core.get_organization!(org_id)

    ApiClient.auth(organization.nip, token)
  end

  defp schedule_reauthentication!(refresh_token, organization_id) do
    schedule_at =
      refresh_token
      |> ApiClient.token_expire_time()
      |> DateTime.shift(minute: -15)

    refresh_token = refresh_token |> Firmowid.Vault.encrypt!() |> Base.encode64()

    %{
      "organization_id" => organization_id,
      "refresh_token" => refresh_token
    }
    |> new(scheduled_at: schedule_at)
    |> Firmowid.Oban.insert!(skip_organization_id: true)
  end

  # Oban.Job is not an Ash resource — raw Ecto query is required here.
  # TODO: Evaluate wrapping Oban job queries behind a dedicated module.
  defp get_refresh_token(organization_id) do
    refresh_token =
      Repo.one(
        from(j in Oban.Job,
          where:
            j.worker == "Firmowid.Ash.Ksef.Workers.SessionWorker" and
              j.state in ["scheduled", "available"] and
              fragment("?->>'organization_id' = ?::text", j.args, ^organization_id) and
              not is_nil(fragment("?->>'refresh_token'", j.args)),
          order_by: [desc: j.scheduled_at],
          limit: 1,
          select: fragment("?->>'refresh_token'", j.args)
        ),
        oban_jobs: true
      )

    case refresh_token do
      nil ->
        nil

      refresh_token ->
        refresh_token
        |> Base.decode64!()
        |> Firmowid.Vault.decrypt!()
    end
  end

  @doc "Returns a valid KSeF access token for the given organization. Refreshes or re-authenticates as needed."
  @spec get_access_token!(String.t()) :: String.t()
  def get_access_token!(organization_id) do
    Cachex.fetch!(:ksef, {:access_token, organization_id}, fn _key ->
      refresh_token = get_refresh_token(organization_id)

      case ApiClient.refresh_session(refresh_token) do
        {:ok, access_token} ->
          {:commit, access_token, expire: access_token_ttl(access_token)}

        {:error, :refresh_token_expired} ->
          Logger.info("Refresh token expired, re-authenticating")

          %{"organization_id" => organization_id}
          |> new()
          |> Firmowid.Oban.insert!(skip_organization_id: true)

          raise RuntimeError, "Refresh token expired, re-authentication scheduled"

        {:error, reason} ->
          Logger.error("Session renewal failed: #{inspect(reason)}")
          raise RuntimeError, "KSeF session renewal failed: #{inspect(reason)}"
      end
    end)
  end

  @doc "Invalidates the cached KSeF access token for the given organization."
  @spec invalidate_access_token(String.t()) :: {:ok, true} | {:ok, false}
  def invalidate_access_token(organization_id) do
    Cachex.del(:ksef, {:access_token, organization_id})
  end

  defp access_token_ttl(access_token) do
    access_token
    |> ApiClient.token_expire_time()
    |> DateTime.diff(DateTime.utc_now(), :millisecond)
  end

  defp final_attempt?(%Oban.Job{attempt: attempt, max_attempts: max_attempts}) do
    attempt >= max_attempts
  end

  defp maybe_unauthenticate(scope, reason, job) do
    if final_attempt?(job) and terminal_auth_failure?(reason) do
      Ksef.unauthenticate(scope)
    end
  end

  defp terminal_auth_failure?(:refresh_token_expired), do: true
  defp terminal_auth_failure?(:unauthorized), do: true
  defp terminal_auth_failure?(:forbidden), do: true
  defp terminal_auth_failure?({:unexpected_status, 401, _body}), do: true
  defp terminal_auth_failure?({:unexpected_status, 403, _body}), do: true
  defp terminal_auth_failure?(_reason), do: false
end
