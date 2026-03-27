defmodule Firmowid.Ash.Timetracker.Checks.HoursRecordNotSubmitted do
  @moduledoc """
  Policy check that denies write actions on sessions whose month already has
  an hours record submitted by the session's user.

  For **create** actions the `start_datetime` comes from `changeset.attributes`.
  For **update/destroy** actions it comes from `changeset.data` (the existing
  record).

  The `:stop` action is excluded at the policy level — stopping a running
  session is always allowed, matching the old Bodyguard behaviour where
  `end_datetime == nil` bypassed the lockdown.
  """
  use Ash.Policy.SimpleCheck

  import Ecto.Query, only: [from: 2]

  alias Firmowid.Ash.Timetracker.HoursRecord

  @impl true
  def describe(_opts), do: "hours record has not been submitted for the session's month"

  @impl true
  def match?(_actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    start_datetime = session_start_datetime(changeset)

    case start_datetime do
      nil ->
        # No start_datetime means we can't determine the month — allow the
        # action and let normal validation catch missing required fields.
        {:ok, true}

      %DateTime{} = dt ->
        {:ok, not hours_record_exists?(changeset, dt)}
    end
  end

  def match?(_, _, _), do: {:ok, true}

  defp session_start_datetime(%Ash.Changeset{action_type: :create} = changeset) do
    Ash.Changeset.get_attribute(changeset, :start_datetime)
  end

  defp session_start_datetime(%Ash.Changeset{} = changeset) do
    changeset.data.start_datetime
  end

  defp hours_record_exists?(changeset, %DateTime{} = dt) do
    user_id = session_user_id(changeset)
    org_id = changeset.tenant

    if user_id && org_id do
      Firmowid.Repo.exists?(
        from(hr in HoursRecord,
          where:
            hr.user_id == ^user_id and
              hr.organization_id == ^org_id and
              hr.month == ^dt.month and
              hr.year == ^dt.year
        ),
        skip_organization_id: true
      )
    else
      false
    end
  end

  defp session_user_id(%Ash.Changeset{action_type: :create} = changeset) do
    Ash.Changeset.get_attribute(changeset, :user_id)
  end

  defp session_user_id(%Ash.Changeset{} = changeset) do
    changeset.data.user_id
  end
end
