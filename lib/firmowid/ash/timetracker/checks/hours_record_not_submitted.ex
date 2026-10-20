defmodule Firmowid.Ash.Timetracker.Checks.HoursRecordNotSubmitted do
  @moduledoc """
  Policy check that denies write actions on sessions whose month already has
  an hours record submitted by the session's member.

  For **create** actions the `start_datetime` comes from `changeset.attributes`.
  For **update/destroy** actions both the existing record's month and, when the
  update moves the session, the new month must be unlocked.

  The `:stop` action is excluded at the policy level — stopping a running
  session is always allowed, matching the old Bodyguard behaviour where
  `end_datetime == nil` bypassed the lockdown.
  """
  use Ash.Policy.SimpleCheck

  alias Firmowid.Ash.Timetracker.HoursRecord

  require Ash.Query

  @impl true
  def describe(_opts), do: "hours record has not been submitted for the session's month"

  @impl true
  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    # A missing start_datetime means the month is unknown — allow the action and
    # let normal validation catch missing required fields.
    locked? =
      changeset
      |> session_start_datetimes()
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&{&1.year, &1.month})
      |> Enum.any?(&hours_record_exists?(changeset, &1, actor))

    {:ok, not locked?}
  end

  def match?(_, _, _), do: {:ok, true}

  defp session_start_datetimes(%Ash.Changeset{action_type: :create} = changeset) do
    [Ash.Changeset.get_attribute(changeset, :start_datetime)]
  end

  defp session_start_datetimes(%Ash.Changeset{} = changeset) do
    [changeset.data.start_datetime, Ash.Changeset.get_attribute(changeset, :start_datetime)]
  end

  defp hours_record_exists?(changeset, %DateTime{} = dt, actor) do
    member_id = session_member_id(changeset)
    org_id = changeset.tenant

    if member_id && org_id do
      month = dt.month
      year = dt.year

      HoursRecord
      |> Ash.Query.filter(
        member_id: member_id,
        month: month,
        year: year,
        submission_status: :submitted
      )
      |> Ash.exists?(actor: actor, tenant: org_id)
    else
      false
    end
  end

  defp session_member_id(%Ash.Changeset{action_type: :create} = changeset) do
    Ash.Changeset.get_attribute(changeset, :member_id)
  end

  defp session_member_id(%Ash.Changeset{} = changeset) do
    changeset.data.member_id
  end
end
