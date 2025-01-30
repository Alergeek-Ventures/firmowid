defmodule Firmowid.Timetracker.Project do
  alias Firmowid.Repo
  use Firmowid.Schema
  import Ecto.Changeset

  schema "projects" do
    field :name, :string

    many_to_many :users,
                 Firmowid.Accounts.User,
                 join_through: "projects_users"

    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> put_change(:organization_id, Repo.get_org_id())
  end

  @doc """
  Creates a changeset for project forms.
  """
  def form_changeset(project \\ %__MODULE__{}, attrs \\ %{}) do
    project
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 100)
  end
end
