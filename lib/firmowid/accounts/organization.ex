defmodule Firmowid.Accounts.Organization do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  alias Firmowid.Accounts.User

  schema "organizations" do
    field :nip, :string
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
      :nip,
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
    |> validate_required([:nip, :name, :owner_id, :inbound_email_nickname])
    |> validate_format(:nip, ~r/^[0-9]{10}$/)
    |> unique_constraint(:inbound_email_nickname)
    |> assoc_constraint(:owner)
  end

  def basic_info_changeset(organization, attrs \\ %{}) do
    organization
    |> cast(
      attrs,
      [:nip, :address, :name, :phone_number, :organization_type, :is_vat_payer]
    )
    |> validate_required([:nip, :name])
  end

  def correspondence_changeset(organization, attrs \\ %{}) do
    cast(organization, attrs, [:correspondence_name, :correspondence_address])
  end

  def vat_eu(%{nip: nip}), do: "PL" <> nip
end
