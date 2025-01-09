defmodule Firmowid.Accounts.OrganizationInvites do
  use Firmowid.Schema
  import Ecto.Changeset

  schema "organization_invites" do
    field :expires_at, :utc_datetime
    field :consumed_at, :utc_datetime

    field :invite_code, :string

    belongs_to :organization, Firmowid.Accounts.Organization
    belongs_to :issued_by, Firmowid.Accounts.User
    belongs_to :consumed_by, Firmowid.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(organization_invites, attrs) do
    organization_invites
    |> cast(attrs, [
      :expires_at,
      :consumed_at,
      :invite_code,
      :organization_id,
      :issued_by_id,
      :consumed_by_id
    ])
    |> assoc_constraint(:organization)
    |> assoc_constraint(:issued_by)
    |> assoc_constraint(:consumed_by)
    |> validate_required([:expires_at, :invite_code, :organization_id, :issued_by_id])
  end
end
