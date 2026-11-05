defmodule Firmowid.Timetracker.Session.Actions.TeamPresence do
  @moduledoc """
  Where the organization's active members are on a day: working now in the
  office or remotely, on accepted leave, or neither.

  Members only read their own sessions, so the running sessions of the team
  are read by the `:presence_reader` system actor of the caller's tenant. Only
  the resulting state leaves this module, never the sessions or leave reasons.
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
    opts = Ash.Context.to_opts(context)
    date = input.arguments.date

    reader = %Scope{
      actor: %SystemActor{org_id: context.tenant, role: :presence_reader},
      tenant: context.tenant
    }

    remote_by_member =
      %{running_only: true}
      |> Timetracker.list_sessions!(scope: reader)
      |> Map.new(&{&1.member_id, &1.is_remote == true})

    on_leave =
      %{status: :accepted, start_date: date, end_date: date}
      |> Timetracker.list_leave_requests!(opts)
      |> MapSet.new(& &1.member_id)

    presence =
      %{status: :active}
      |> Core.list_users!(Keyword.put(opts, :load, member: [:display_name]))
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
