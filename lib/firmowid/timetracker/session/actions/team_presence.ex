defmodule Firmowid.Timetracker.Session.Actions.TeamPresence do
  @moduledoc """
  Where the organization's active members are on a day: working now in the
  office or remotely, on accepted leave, or neither.

  Every member sees it, but members only read their own sessions and leave
  requests, and only administrators list the team. So the team, its running
  sessions and accepted leave are read by the `:presence_reader` system actor
  of the caller's organization, taken from the caller's membership rather than
  the requested tenant. Only names and states leave this module, never the
  sessions or leave reasons.
  """

  alias Firmowid.Core
  alias Firmowid.Scope
  alias Firmowid.SystemActor
  alias Firmowid.Timetracker

  @type status :: :office | :remote | :leave | :away
  @type presence :: %{name: String.t(), status: status()}

  @doc "Lists the active members with their state, the working ones first."
  @spec run(Ash.ActionInput.t(), Ash.Resource.Actions.Implementation.Context.t()) ::
          {:ok, [presence()]}
  def run(input, context) do
    date = input.arguments.date

    org_id = context.actor.member.organization_id
    reader = %Scope{actor: %SystemActor{org_id: org_id, role: :presence_reader}, tenant: org_id}

    remote_by_member =
      %{running_only: true}
      |> Timetracker.list_sessions!(scope: reader)
      |> Map.new(&{&1.member_id, &1.is_remote == true})

    on_leave =
      %{status: :accepted, start_date: date, end_date: date}
      |> Timetracker.list_leave_requests!(scope: reader)
      |> MapSet.new(& &1.member_id)

    presence =
      %{status: :active}
      |> Core.list_users!(scope: reader, load: [member: [:display_name]])
      |> Enum.map(fn %{member: member} ->
        %{
          name: member.display_name,
          status: status(Map.fetch(remote_by_member, member.id), MapSet.member?(on_leave, member.id))
        }
      end)
      |> Enum.sort_by(&{rank(&1.status), String.downcase(&1.name)})

    {:ok, presence}
  end

  defp status({:ok, true}, _on_leave?), do: :remote
  defp status({:ok, false}, _on_leave?), do: :office
  defp status(:error, true), do: :leave
  defp status(:error, false), do: :away

  defp rank(:office), do: 0
  defp rank(:remote), do: 1
  defp rank(:leave), do: 2
  defp rank(:away), do: 3
end
