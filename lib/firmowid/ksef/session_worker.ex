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
    max_attempts: 3

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
      "authenticate" -> authenticate()
      "renew" -> renew_session(args)
    end
  end

  defp authenticate do
    Logger.info("Starting KSeF authentication for organization #{Repo.get_org_id()}")

    Ksef.get_credential()
    |> perform_authentication()
    |> case do
      {:ok, tokens} ->
        schedule_renewal(tokens.access_token, tokens.refresh_token)

        date_from = DateTime.shift(DateTime.utc_now(), day: -30 * 2)
        Ksef.fetch_cost_invoices(date_from)

      {:error, reason} = error ->
        Ksef.unauthenticate()
        Logger.error("Authentication failed: #{inspect(reason)}")
        error
    end
  rescue
    e ->
      Ksef.unauthenticate()
      {:error, e}
  end

  defp renew_session(%{"refresh_token" => refresh_token}) do
    Logger.info("Renewing KSeF session for organization #{Repo.get_org_id()}")

    case ApiClient.refresh_session(refresh_token) do
      {:ok, access_token} ->
        schedule_renewal(access_token, refresh_token)

      {:error, :refresh_token_expired} ->
        Logger.info("Refresh token expired, re-authenticating")
        authenticate()

      {:error, reason} = error ->
        Logger.error("Session renewal failed: #{inspect(reason)}")
        error
    end
  end

  defp perform_authentication(%Credential{organization_id: org_id, auth_type: :token, credentials: token}) do
    {:ok, organization} = Accounts.get_organization(org_id)
    "PL" <> context_nip = organization.identification_number

    ApiClient.auth(context_nip, token)
  end

  defp schedule_renewal(access_token, refresh_token) do
    scheduled_at =
      access_token |> ApiClient.token_expire_time() |> DateTime.shift(minute: -5)

    %{
      "action" => "renew",
      "organization_id" => Repo.get_org_id(),
      "access_token" => access_token,
      "refresh_token" => refresh_token
    }
    |> new(scheduled_at: scheduled_at)
    |> Firmowid.Oban.insert()
  end

  def get_active_session_token! do
    organization_id = Repo.get_org_id()

    # Query most recent scheduled session job with access token
    job =
      Repo.one(
        from(j in Oban.Job,
          where: j.worker == "Firmowid.Ksef.SessionWorker",
          where: j.state in ["scheduled", "available"],
          where: fragment("?->>'organization_id' = ?", j.args, ^organization_id),
          where: fragment("?->>'action' = 'renew'", j.args),
          order_by: [desc: j.scheduled_at],
          limit: 1
        ),
        oban_jobs: true
      )

    case job do
      %{args: %{"access_token" => token}} -> token
      _ -> raise "No active KSeF session found for organization #{organization_id}"
    end
  end
end
