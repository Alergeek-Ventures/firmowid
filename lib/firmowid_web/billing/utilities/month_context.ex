defmodule FirmowidWeb.Billing.Utilities.MonthContext do
  @moduledoc """
  Builds shared billing month context for admin and settings screens.
  """

  alias Firmowid.Ash.Billing
  alias Firmowid.Ash.Billing.Month
  alias Firmowid.Ash.Billing.Snapshot
  alias Firmowid.Ash.Billing.SnapshotCalculator
  alias Firmowid.Ash.Core.Organization
  alias FirmowidWeb.Billing.Utilities.Worksheet

  require Ash.Query

  @type status :: %{kind: :live_preview} | %{kind: :snapshot, frozen_at: DateTime.t()}

  @type t :: %{
          selected_month: Date.t(),
          selected_snapshot: Snapshot.t() | nil,
          status: status(),
          usage_source: map(),
          worksheet: map()
        }

  @doc """
  Builds worksheet data for one organization and one billing month.
  """
  @spec load(Organization.t(), Date.t(), map(), keyword()) :: t()
  def load(%Organization{} = organization, selected_month, current_user, opts \\ []) do
    selected_month = Month.normalize(selected_month)
    current_month = opts |> Keyword.get(:current_month, Month.current()) |> Month.normalize()
    snapshots = Keyword.get(opts, :snapshots)

    {status, usage_source, selected_snapshot} =
      load_usage_source(organization, selected_month, current_user, current_month, snapshots)

    %{
      selected_month: selected_month,
      selected_snapshot: selected_snapshot,
      status: status,
      usage_source: usage_source,
      worksheet: Worksheet.build(usage_source)
    }
  end

  @doc """
  Returns historical billing snapshots for one organization in descending month order.
  """
  @spec list_snapshots(binary(), map()) :: [Snapshot.t()]
  def list_snapshots(organization_id, current_user) do
    %{}
    |> Billing.query_to_list_billing_snapshots_global(actor: current_user)
    |> Ash.Query.filter(organization_id == ^organization_id)
    |> Ash.Query.sort(month: :desc)
    |> Ash.read!(actor: current_user)
  end

  defp load_usage_source(organization, selected_month, _current_user, current_month, _snapshots)
       when selected_month == current_month do
    usage_source = SnapshotCalculator.build_snapshot_attrs!(organization.id, selected_month)
    {%{kind: :live_preview}, usage_source, nil}
  end

  defp load_usage_source(organization, selected_month, current_user, _current_month, snapshots) do
    snapshot =
      organization.id
      |> load_snapshots(current_user, snapshots)
      |> find_snapshot!(selected_month, organization.id)

    {%{kind: :snapshot, frozen_at: snapshot.frozen_at}, snapshot, snapshot}
  end

  defp load_snapshots(organization_id, current_user, nil), do: list_snapshots(organization_id, current_user)

  defp load_snapshots(_organization_id, _current_user, snapshots), do: snapshots

  defp find_snapshot!(snapshots, selected_month, organization_id) do
    Enum.find(snapshots, &(Date.compare(&1.month, selected_month) == :eq)) ||
      raise ArgumentError,
            "missing billing snapshot for organization #{organization_id} and month #{Date.to_iso8601(selected_month)}"
  end
end
