defmodule Firmowid.Ksef.SessionWorker do
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
    max_attempts: 3,
    unique: [period: :infinity, keys: [:organization_id]]

  import Ecto.Query

  alias Firmowid.Accounts
  alias Firmowid.Ksef
  alias Firmowid.Ksef.ApiClient
  alias Firmowid.Ksef.Credential
  alias Firmowid.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => organization_id, "action" => action} = args}) do
    Repo.put_org_id(organization_id)

    case action do
      "authenticate" -> authenticate(organization_id)
      "renew" -> renew_session(organization_id, args)
      _ -> {:error, {:unknown_action, action}}
    end
  end

  defp authenticate(organization_id) do
    Logger.info("Starting KSeF authentication for organization #{organization_id}")

    with {:ok, credential} <- get_credential(),
         {:ok, %{access_token: access_token, refresh_token: refresh_token}} <-
           perform_authentication(credential),
         {:ok, _job} <- schedule_renewal(organization_id, access_token, refresh_token) do
      Logger.info("Successfully authenticated with KSeF")
      :ok
    else
      {:error, :credential_not_found} ->
        Logger.warning("No active KSeF credential found")
        {:error, :credential_not_found}

        date_from = DateTime.shift(DateTime.utc_now(), day: -30 * 2)
        Ksef.fetch_cost_invoices(date_from)

      {:error, reason} = error ->
        Logger.error("Authentication failed: #{inspect(reason)}")
        error
    end
  end

  defp renew_session(organization_id, %{"access_token" => _access_token, "refresh_token" => refresh_token}) do
    Logger.info("Renewing KSeF session for organization #{organization_id}")

    with {:ok, _credential} <- get_credential(),
         {:ok, access_token} <- ApiClient.refresh_session(refresh_token),
         {:ok, _job} <- schedule_renewal(organization_id, access_token, refresh_token) do
      Logger.info("Successfully renewed KSeF session")
      :ok
    else
      {:error, :refresh_token_expired} ->
        Logger.info("Refresh token expired, re-authenticating")
        authenticate(organization_id)

      {:error, :credential_not_found} ->
        Logger.warning("No active credential found during renewal")
        {:error, :credential_not_found}

      {:error, reason} = error ->
        Logger.error("Session renewal failed: #{inspect(reason)}")
        error
    end
  end

  defp get_credential do
    case Ksef.get_credential() do
      nil -> {:error, :credential_not_found}
      credential -> {:ok, credential}
    end
  end

  defp perform_authentication(%Credential{organization_id: org_id, auth_type: :token, credentials: token}) do
    organization = Repo.get!(Accounts.Organization, org_id)
    context_nip = organization.identification_number

    ApiClient.auth(context_nip, token)
  end

  defp perform_authentication(%Credential{auth_type: :certificate}) do
    # Certificate authentication not yet implemented
    {:error, :certificate_auth_not_implemented}
  end

  defp schedule_renewal(organization_id, access_token, refresh_token) do
    expires_at = ApiClient.token_expire_time(access_token)
    scheduled_at = DateTime.shift(expires_at, minutes: -5)

    %{
      "action" => "renew",
      "organization_id" => organization_id,
      "access_token" => access_token,
      "refresh_token" => refresh_token
    }
    |> new(schedule_at: scheduled_at)
    |> Firmowid.Oban.insert()
  end

  @doc """
  Ensures an active session exists for the organization.

  If a session renewal job is already scheduled, returns :ok.
  Otherwise, schedules an authentication job.
  """
  def ensure_session(organization_id) do
    case get_scheduled_session_job(organization_id) do
      nil ->
        %{
          "organization_id" => organization_id,
          "action" => "authenticate"
        }
        |> new()
        |> Firmowid.Oban.insert()

      _job ->
        {:ok, :already_scheduled}
    end
  end

  # Get scheduled or executing session job for organization
  defp get_scheduled_session_job(organization_id) do
    Repo.put_org_id(organization_id)

    Repo.one(
      from(j in Oban.Job,
        where: j.worker == "Firmowid.Ksef.SessionWorker",
        where: j.state in ["available", "scheduled", "executing"],
        where: fragment("?->>'organization_id' = ?", j.args, ^organization_id),
        order_by: [desc: j.scheduled_at],
        limit: 1
      ),
      oban_jobs: true
    )
  end
end
