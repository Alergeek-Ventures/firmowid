defmodule Firmowid.Timetracker.UserSalary do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  alias Firmowid.Repo

  schema "user_salaries" do
    field :hourly_rate, :decimal
    field :deleted_at, :date

    belongs_to :user, Firmowid.Accounts.User
    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  @doc false
  def changeset(user_salary, attrs \\ %{}) do
    user_salary
    |> cast(attrs, [:hourly_rate, :deleted_at, :user_id])
    |> validate_required([:hourly_rate, :user_id])
    |> validate_number(:hourly_rate, greater_than: 0)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
    |> put_change(:organization_id, Repo.get_org_id())
    |> unique_constraint([:user_id, :organization_id],
      name: :user_salaries_active_unique_index,
      message: "User already has an active salary record"
    )
  end
end
