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

  @doc "Enqueues a KSeF session authentication worker for the given organization."
  @spec enqueue(Ash.UUID.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(organization_id) do
    %{"organization_id" => organization_id}
    |> new()
    |> Firmowid.Oban.insert(skip_organization_id: true)
  end

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: Oban.Worker.result()
  def perform(%Oban.Job{args: %{"organization_id" => organization_id}} = job) do
    actor = %SystemActor{org_id: organization_id, role: :ksef_session}
    scope = %Scope{actor: actor, tenant: organization_id}

    Logger.info("Starting KSeF authentication for organization #{organization_id}")

    with {:ok, %Credential{} = credential} <- get_credential(scope),
         {:ok, tokens} <- perform_authentication(credential) do
      establish_session(tokens, credential, scope)
    else
      {:error, :no_credential} ->
        Logger.error("No authenticating or working KSeF credentials found for organization #{organization_id}")

        {:cancel, :no_credential}

      {:error, {:invalid_credential_status, message}} ->
        Logger.error("Invalid KSeF credential status for organization #{organization_id}: #{message}")

        {:cancel, :invalid_credential_status}

      {:error, reason} = error ->
        maybe_unauthenticate(scope, reason, job)
        error
    end
  end

  defp get_credential(scope) do
    case Credential.get_internal!(scope: scope) do
      %Credential{status: status} = credential when status in [:authenticating, :working] ->
        {:ok, credential}

      %Credential{status: status} ->
        {:error, {:invalid_credential_status, "Credential status is #{status}, expected :authenticating or :working"}}

      nil ->
        {:error, :no_credential}
    end
  end

  defp perform_authentication(%Credential{organization_id: org_id, auth_type: :token, credentials: token}) do
    organization = Core.get_organization!(org_id)

    ApiClient.auth_with_token(organization.nip, token)
  end

  defp perform_authentication(%Credential{organization_id: org_id, auth_type: auth_type, credentials: credentials})
       when auth_type in [:certificate, :generated_certificate] do
    organization = Core.get_organization!(org_id)

    case Jason.decode(credentials) do
      {:ok,
       %{
         "certificate" => certificate,
         "private_key" => private_key,
         "private_key_password" => private_key_password
       }} ->
        ApiClient.auth_with_ksef_certificate(
          organization.nip,
          certificate,
          private_key,
          private_key_password
        )

      _error ->
        {:error, :invalid_certificate_credentials}
    end
  end

  @spec establish_session(
          %{access_token: String.t(), refresh_token: String.t()},
          Credential.t(),
          Scope.t()
        ) :: {:ok, boolean()} | {:error, term()}
  defp establish_session(
         %{access_token: access_token, refresh_token: refresh_token},
         %Credential{organization_id: organization_id, status: status} = credential,
         scope
       ) do
    with {:ok, _cached?} <- put_access_token!(organization_id, access_token),
         {:ok, _job} <- schedule_reauthentication(refresh_token, organization_id),
         {:ok, _credential} <- Credential.mark_working(credential, scope: scope) do
      if status == :authenticating do
        Ksef.fetch_cost_invoices(DateTime.shift(DateTime.utc_now(), day: -30), scope)
      end

      :ok
    end
  end

  defp schedule_reauthentication(refresh_token, organization_id) do
    schedule_at =
      refresh_token
      |> ApiClient.token_expire_time()
      |> DateTime.shift(minute: -15)

    refresh_token = refresh_token |> Firmowid.Vault.encrypt!() |> Base.encode64()
    cancel_scheduled_reauthentication_jobs(organization_id)

    %{
      "organization_id" => organization_id,
      "refresh_token" => refresh_token
    }
    |> new(scheduled_at: schedule_at)
    |> Firmowid.Oban.insert(skip_organization_id: true)
  end

  defp cancel_scheduled_reauthentication_jobs(organization_id) do
    Firmowid.Oban.cancel_all_jobs(
      from(j in Oban.Job,
        where:
          j.worker == "Firmowid.Ash.Ksef.Workers.SessionWorker" and
            j.state in ["available", "scheduled"] and
            fragment("?->>'organization_id' = ?::text", j.args, ^organization_id) and
            not is_nil(fragment("?->>'refresh_token'", j.args))
      )
    )
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

          {:ok, _job} = enqueue(organization_id)

          raise RuntimeError, "Refresh token expired, re-authentication scheduled"

        {:error, reason} ->
          Logger.error("Session renewal failed: #{inspect(reason)}")
          raise RuntimeError, "KSeF session renewal failed: #{inspect(reason)}"
      end
    end)
  end

  defp put_access_token!(organization_id, access_token) do
    expire = access_token_ttl(access_token)
    Cachex.put(:ksef, {:access_token, organization_id}, access_token, expire: expire)
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
      if credential = Credential.get_internal!(scope: scope) do
        Credential.delete_failed!(credential, credential_failure_reason(reason), scope: scope)
      end
    end
  end

  defp credential_failure_reason(reason) when reason in [:invalid_private_key, :invalid_certificate_credentials],
    do: :invalid_credentials

  defp credential_failure_reason(_reason), do: :authentication_failed

  defp terminal_auth_failure?(:refresh_token_expired), do: true
  defp terminal_auth_failure?(:unauthorized), do: true
  defp terminal_auth_failure?(:forbidden), do: true
  defp terminal_auth_failure?(:invalid_private_key), do: true
  defp terminal_auth_failure?(:invalid_certificate_credentials), do: true
  defp terminal_auth_failure?({:authentication_failed, _message}), do: true
  defp terminal_auth_failure?(_reason), do: false
end
