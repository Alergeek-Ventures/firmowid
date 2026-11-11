defmodule Firmowid.Billing.SnapshotCalculator do
  @moduledoc """
  Builds factual monthly billing snapshot attributes for one organization.
  """

  alias Firmowid.Billing
  alias Firmowid.Billing.Month
  alias Firmowid.Billing.Snapshot
  alias Firmowid.Core
  alias Firmowid.Core.Organization
  alias Firmowid.Finances
  alias Firmowid.Invoicing
  alias Firmowid.Scope
  alias Firmowid.SystemActor
  alias Firmowid.Timetracker

  require Ash.Query

  @warsaw_timezone "Europe/Warsaw"

  @doc """
  Returns a snapshot attribute map for the given organization and month.

  `month` must be the first day of the target month in Europe/Warsaw terms.
  """
  @spec build_snapshot_attrs!(binary() | Organization.t(), Date.t()) :: map()
  def build_snapshot_attrs!(%Organization{} = organization, month) do
    month = normalize_month(month)
    scope = org_scope(organization.id)
    {inserted_from, inserted_to} = warsaw_month_utc_bounds(month)

    %{
      month: month,
      # Intentionally capture the plan that is active when the monthly snapshot
      # is generated. `billing_plan` can only be changed by a superuser, so we accept the
      # narrow gap between month end and the scheduled snapshot run instead of
      # modeling effective-dated subscription history.
      billing_plan: organization.billing_plan,
      manual_external_invoices_count: manual_external_invoices_count(scope, inserted_from, inserted_to),
      synced_bank_accounts_count: scope |> synced_bank_accounts_query() |> Ash.count!(scope: scope),
      synced_bank_institutions_count:
        scope
        |> synced_bank_institution_accounts_query()
        |> Ash.count!(field: :institution_id, uniq?: true, scope: scope),
      active_non_owner_users_count: active_non_owner_users_count(scope, organization.owner_id),
      active_projects_count: active_projects_count(scope),
      frozen_at: DateTime.utc_now()
    }
  end

  def build_snapshot_attrs!(organization_id, month) when is_binary(organization_id) do
    scope = org_scope(organization_id)
    organization = Core.get_organization!(organization_id, scope: scope)
    build_snapshot_attrs!(organization, month)
  end

  @doc """
  Returns the previous month marker for the given Warsaw-local date or datetime.
  """
  @spec previous_month(Date.t() | DateTime.t()) :: Date.t()
  def previous_month(%DateTime{} = datetime) do
    datetime
    |> DateTime.shift_zone!(@warsaw_timezone)
    |> DateTime.to_date()
    |> previous_month()
  end

  def previous_month(%Date{} = date) do
    date
    |> normalize_month()
    |> Date.add(-1)
    |> normalize_month()
  end

  @doc """
  Returns an existing snapshot for the month inside the organization scope.
  """
  @spec existing_snapshot(binary(), Date.t()) :: Snapshot.t() | nil
  def existing_snapshot(organization_id, month) do
    scope = org_scope(organization_id)

    month
    |> normalize_month()
    |> Billing.query_to_get_billing_snapshot_for_month(scope: scope)
    |> Ash.read_one!(scope: scope)
  end

  @doc """
  Returns the system scope used for per-organization snapshot work.
  """
  @spec org_scope(binary()) :: Scope.t()
  def org_scope(organization_id) do
    %Scope{
      actor: %SystemActor{org_id: organization_id, role: :billing_snapshotter},
      tenant: organization_id
    }
  end

  defp manual_external_invoices_count(scope, inserted_from, inserted_to) do
    %{inserted_from: inserted_from, inserted_to: inserted_to, source: :manual_import}
    |> Invoicing.query_to_list_cost_invoices(scope: scope)
    |> Ash.Query.filter(is_ksef_imported == false)
    |> Ash.count!(scope: scope)
  end

  # Accounts the plan limit paused do not count; manually added ones never do.
  defp synced_bank_accounts_query(scope) do
    %{}
    |> Finances.query_to_list_bank_accounts(scope: scope)
    |> Ash.Query.filter(not is_nil(gocardless_id) and is_nil(suspended_by_plan_at))
  end

  @doc """
  Returns the query of the accounts that make up the synchronized banks the
  plans limit: synchronized through GoCardless, not paused by the plan limit and
  of a known bank (`institution_id`).
  """
  @spec synced_bank_institution_accounts_query(Scope.t()) :: Ash.Query.t()
  def synced_bank_institution_accounts_query(scope) do
    scope
    |> synced_bank_accounts_query()
    |> Ash.Query.filter(not is_nil(institution_id))
  end

  defp active_non_owner_users_count(scope, owner_id) do
    %{status: :active}
    |> Core.query_to_list_users(scope: scope)
    |> Ash.Query.filter(id != ^owner_id)
    |> Ash.count!(scope: scope)
  end

  defp active_projects_count(scope) do
    %{status: :active}
    |> Timetracker.query_to_list_projects(scope: scope)
    |> Ash.count!(scope: scope)
  end

  defp normalize_month(month), do: Month.normalize(month)

  defp warsaw_month_utc_bounds(month) do
    local_start =
      month |> NaiveDateTime.new!(~T[00:00:00]) |> DateTime.from_naive!(@warsaw_timezone)

    local_end =
      month
      |> Date.end_of_month()
      |> Date.add(1)
      |> NaiveDateTime.new!(~T[00:00:00])
      |> DateTime.from_naive!(@warsaw_timezone)

    {DateTime.shift_zone!(local_start, "Etc/UTC"), DateTime.shift_zone!(local_end, "Etc/UTC")}
  end
end
