defmodule Firmowid.Ash.Ksef.Changes.RevokeSupersededCertificate do
  @moduledoc """
  Revokes a replaced Firmowid-generated KSeF certificate after persistence.
  """

  use Ash.Resource.Change

  alias Firmowid.Ash.Ksef.CredentialMetadata
  alias Firmowid.Ash.Ksef.Services.ApiClient
  alias Firmowid.Ash.Ksef.Workers.SessionWorker

  @impl true
  def change(changeset, _opts, _context) do
    if changeset.data.auth_type == :generated_certificate do
      Ash.Changeset.after_action(changeset, fn changeset, credential ->
        access_token = SessionWorker.get_access_token!(credential.organization_id)
        serial_number = CredentialMetadata.certificate_serial_number(changeset.data)

        case ApiClient.revoke_certificate(access_token, serial_number, :superseded) do
          :ok -> {:ok, credential}
          {:error, _reason} = error -> error
        end
      end)
    else
      changeset
    end
  end
end
