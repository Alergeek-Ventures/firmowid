defmodule Firmowid.Timetracker.Project do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  alias Firmowid.Repo
  alias Firmowid.SalesInvoices.Counterparty
  alias Firmowid.Timetracker.ProjectUser
  alias Firmowid.Timetracker.Session

  schema "projects" do
    field :name, :string
    field :archived_at, :date
    field :hours, :integer, virtual: true, default: 0

    many_to_many :users,
                 Firmowid.Accounts.User,
                 join_through: ProjectUser

    has_many :project_users,
             ProjectUser,
             on_replace: :delete

    has_many :sessions, Session

    belongs_to :counterparty, Counterparty
    belongs_to :organization, Firmowid.Accounts.Organization
    belongs_to :tag_definition, Firmowid.Analysis.TagDefinition

    timestamps()
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :tag_definition_id, :archived_at, :counterparty_id])
    |> cast_assoc(:project_users)
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
