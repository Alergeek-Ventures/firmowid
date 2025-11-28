defmodule Firmowid.Ksef.Credential do
  @moduledoc """
  Schema for storing KSeF authentication credentials per organization.

  Credentials are stored encrypted and support both token-based and
  certificate-based authentication methods.
  """
  use Firmowid.Schema

  import Ecto.Changeset

  alias Firmowid.Accounts.Organization

  schema "ksef_credentials" do
    field :auth_type, Ecto.Enum, values: [:token, :certificate]
    field :credentials, Firmowid.Encrypted.Binary

    belongs_to :organization, Organization

    timestamps()
  end

  def changeset(credential, attrs \\ %{}) do
    credential
    |> cast(attrs, [
      :organization_id,
      :auth_type,
      :credentials
    ])
    |> validate_required([:organization_id, :auth_type, :credentials])
    |> unique_constraint([:organization_id])
    |> assoc_constraint(:organization)
  end
end
