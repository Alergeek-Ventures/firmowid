defmodule Firmowid.Timetracker.UserSalary do
  alias Firmowid.Repo
  use Firmowid.Schema
  import Ecto.Changeset

  schema "user_salaries" do
    field :hourly_rate, :decimal
    field :effective_from, :date

    belongs_to :user, Firmowid.Accounts.User
    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  @doc false
  def changeset(user_salary, attrs \\ %{}) do
    user_salary
    |> cast(attrs, [:hourly_rate, :effective_from, :user_id])
    |> validate_required([:hourly_rate, :effective_from, :user_id])
    |> validate_number(:hourly_rate, greater_than: 0)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
    |> put_change(:organization_id, Repo.get_org_id())
    |> unique_constraint([:user_id, :effective_from, :organization_id])
  end
end
