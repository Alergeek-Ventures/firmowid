defmodule Firmowid.Ksef do
  @moduledoc """
  The KSeF (Krajowy System e-Faktur) context.

  Provides functions for managing KSeF credentials and authentication.
  """

  import Ecto.Query, warn: false

  alias Firmowid.Ksef.Credential
  alias Firmowid.Ksef.SessionWorker
  alias Firmowid.Repo

  def authenticate_with_ksef_token(ksef_token) when is_binary(ksef_token) do
    {:ok, _credential} =
      %Credential{}
      |> Credential.changeset(%{
        organization_id: Repo.get_org_id(),
        auth_type: :token,
        credentials: %{"token" => ksef_token}
      })
      |> Repo.insert()

    %{"organization_id" => Repo.get_org_id(), "action" => "authenticate"}
    |> SessionWorker.new()
    |> Firmowid.Oban.insert!()
  end

  def get_credential do
    Repo.get_by(Credential, organization_id: Repo.get_org_id())
  end

  def delete_credential(%Credential{} = credential) do
    Repo.delete(credential)
  end
end
