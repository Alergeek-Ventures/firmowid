defmodule Firmowid.BankData.CleanupWorker do
  @moduledoc """
  Periodic cleanup tasks for BankData requisitions:
  - Mark stale pending (>1h) as rejected and delete remote requisitions
  - Delete orphaned requisitions (no bank accounts) older than 1h (remote + local)
  - Delete expired remote requisitions (created_at + 90 days) while keeping local rows
  """

  use Oban.Worker, queue: :bank_data

  require Logger
  import Ecto.Query

  alias Firmowid.BankData
  alias Firmowid.Repo
  alias Firmowid.Accounts.Organization

  @stale_pending_seconds 60 * 60
  @expired_days 90

  @impl Oban.Worker
  def perform(%Oban.Job{} = _job) do
    now = DateTime.utc_now()
    stale_cutoff = DateTime.add(now, -@stale_pending_seconds, :second)
    expired_cutoff = DateTime.add(now, -@expired_days, :day)

    Logger.metadata(module: __MODULE__)

    org_ids = Repo.all(from(o in Organization, select: o.id), skip_organization_id: true)

    {stale_total, orphaned_total, expired_total} =
      Enum.reduce(org_ids, {0, 0, 0}, fn org_id, {s_acc, o_acc, e_acc} ->
        s = BankData.cleanup_reject_stale_pending_and_delete_remote(stale_cutoff, org_id)
        o = BankData.cleanup_delete_orphaned_requisitions(stale_cutoff, org_id)
        e = BankData.cleanup_delete_expired_remote_requisitions(expired_cutoff, org_id)
        {s_acc + s, o_acc + o, e_acc + e}
      end)

    Logger.info("Processed #{stale_total} stale pending requisitions older than 1h (across orgs)")
    Logger.info("Deleted #{orphaned_total} orphaned requisitions older than 1h (across orgs)")

    Logger.info(
      "Deleted remote for #{expired_total} expired requisitions (90+ days) with accounts (across orgs)"
    )

    :ok
  end
end
