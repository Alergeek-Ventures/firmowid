defmodule Firmowid.Ksef do
  @moduledoc false
  import Ecto.Query, warn: false

  alias Firmowid.Ksef.Credential
  alias Firmowid.Ksef.FetchWorker
  alias Firmowid.Ksef.SessionWorker
  alias Firmowid.Repo

  def authenticate_with_ksef_token(ksef_token) when is_binary(ksef_token) do
    # todo add ksef_token owner and permission validation
    # todo credentials should be persisted only if authentication is successful - move to session worker and transaction
    {:ok, _credential} =
      %Credential{}
      |> Credential.changeset(%{
        organization_id: Repo.get_org_id(),
        auth_type: :token,
        credentials: ksef_token
      })
      |> Repo.insert()

    %{"organization_id" => Repo.get_org_id(), "action" => "authenticate"}
    |> SessionWorker.new()
    |> Firmowid.Oban.insert!()
  end

  def get_credential do
    Repo.get_by(Credential, organization_id: Repo.get_org_id())
  end

  def unauthenticate do
    credential = get_credential()

    Firmowid.Oban.cancel_all_jobs(
      from(j in Oban.Job,
        where: j.worker in ["Firmowid.Ksef.SessionWorker", "Firmowid.Ksef.FetchWorker"],
        where: fragment("?->>'organization_id' = ?", j.args, ^Repo.get_org_id()),
        where: j.state in ["available", "scheduled", "executing"]
      )
    )

    Repo.delete(credential)
  end

  def fetch_cost_invoices(date_from) do
    %{
      "action" => "initiate_export",
      "organization_id" => Repo.get_org_id(),
      "date_from" => DateTime.to_iso8601(date_from)
    }
    |> FetchWorker.new()
    |> Firmowid.Oban.insert()
  end
end
