defmodule Firmowid.Accounts.Organization do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  alias Firmowid.Accounts.User

  schema "organizations" do
    field :identification_number, :string
    field :address, :string
    field :name, :string
    field :phone_number, :string
    field :organization_type, :string
    field :correspondence_name, :string
    field :correspondence_address, :string
    field :is_vat_payer, :boolean, default: true
    field :allowed_sender_emails, {:array, :string}, default: []
    field :inbound_email_nickname, :string

    belongs_to :owner, User
    belongs_to :avatar_blob, Firmowid.Blobs.Blob
    has_many :users, User

    timestamps()
  end

  @doc false
  def changeset(organization, attrs \\ %{}) do
    organization
    |> cast(attrs, [
      :identification_number,
      :address,
      :name,
      :owner_id,
      :avatar_blob_id,
      :phone_number,
      :organization_type,
      :correspondence_name,
      :correspondence_address,
      :is_vat_payer,
      :allowed_sender_emails,
      :inbound_email_nickname
    ])
    |> validate_required([:identification_number, :name, :owner_id, :inbound_email_nickname])
    |> unique_constraint(:inbound_email_nickname)
    |> assoc_constraint(:owner)
  end

  def basic_info_changeset(organization, attrs \\ %{}) do
    organization
    |> cast(
      attrs,
      [:identification_number, :address, :name, :phone_number, :organization_type, :is_vat_payer]
    )
    |> validate_required([:identification_number, :name])
  end

  def correspondence_changeset(organization, attrs \\ %{}) do
    cast(organization, attrs, [:correspondence_name, :correspondence_address])
  end
end
