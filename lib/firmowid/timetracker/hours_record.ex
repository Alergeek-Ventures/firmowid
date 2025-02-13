defmodule Firmowid.Timetracker.HoursRecord do
  alias Firmowid.Repo
  use Firmowid.Schema
  import Ecto.Changeset

  schema "hours_records" do
    field :month, :integer
    field :year, :integer
    field :number_of_hours, :integer

    belongs_to :blob, Firmowid.Blobs.Blob
    belongs_to :organization, Firmowid.Accounts.Organization
    belongs_to :user, Firmowid.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(hours_record, attrs) do
    hours_record
    |> cast(attrs, [:month, :year, :number_of_hours, :blob_id, :user_id])
    |> validate_required([:month, :year, :number_of_hours, :blob_id, :user_id])
    |> foreign_key_constraint(:user_id)
    |> put_change(:organization_id, Repo.get_org_id())
    |> unique_constraint([:month, :year, :organization_id, :user_id])
    |> validate_number(:number_of_hours, greater_than: 0)
    |> validate_number(:month, greater_than: 0, less_than: 13)
    |> validate_number(:year, greater_than: 1900)
  end
end
