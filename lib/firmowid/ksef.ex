defmodule Firmowid.Ksef do
  @moduledoc false
  import Ecto.Query, warn: false

  alias Firmowid.Accounts
  alias Firmowid.Ksef.Credential
  alias Firmowid.Ksef.FetchWorker
  alias Firmowid.Ksef.SessionWorker
  alias Firmowid.Repo

  @doc """
  Authenticates the current organization with KSeF using the provided token.

  The token format is: `<id>|nip-<nip>|<hash>`
  Example: `20251129-EC-2880DEC000-943359B3B3-DA|nip-1234563218|7489ef19...`

  Returns:
    - `{:ok, credential}` on success
    - `{:error, :invalid_token_format}` if token format is invalid
    - `{:error, :nip_mismatch}` if NIP in token doesn't match organization's NIP
    - `{:error, :already_connected}` if organization already has KSeF credentials
  """
  def authenticate_with_ksef_token(ksef_token) when is_binary(ksef_token) do
    org_id = Repo.get_org_id()
    {:ok, organization} = Accounts.get_organization(org_id)

    with {:ok, token_nip} <- extract_nip_from_token(ksef_token),
         :ok <- validate_nip_match(token_nip, organization.identification_number),
         :ok <- validate_no_existing_credential() do
      {:ok, credential} =
        %Credential{}
        |> Credential.changeset(%{
          organization_id: org_id,
          auth_type: :token,
          credentials: ksef_token
        })
        |> Repo.insert()

      %{"organization_id" => org_id, "action" => "authenticate"}
      |> SessionWorker.new()
      |> Firmowid.Oban.insert!()

      {:ok, credential}
    end
  end

  defp extract_nip_from_token(token) do
    case String.split(token, "|") do
      [_id, "nip-" <> nip, _hash] when byte_size(nip) > 0 ->
        {:ok, nip}

      _ ->
        {:error, :invalid_token_format}
    end
  end

  defp validate_nip_match(token_nip, org_nip) do
    # Normalize NIPs by removing any non-digit characters for comparison
    normalized_token_nip = String.replace(token_nip, ~r/\D/, "")
    normalized_org_nip = String.replace(org_nip || "", ~r/\D/, "")

    if normalized_token_nip == normalized_org_nip do
      :ok
    else
      {:error, :nip_mismatch}
    end
  end

  defp validate_no_existing_credential do
    case get_credential() do
      nil -> :ok
      _credential -> {:error, :already_connected}
    end
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
