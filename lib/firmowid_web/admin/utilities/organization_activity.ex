defmodule FirmowidWeb.Admin.Utilities.OrganizationActivity do
  @moduledoc """
  Read-only, tenant-bound traces of persisted organization activity for the superuser worksheet.

  Counts cover the rolling 30 * 24 hours ending at `now` (inclusive start, exclusive end).
  Latest timestamps are not limited to that window. These are record creation / session
  start times, not evidence of a login or of the person who performed the action.
  `last_sign_in` is the active member's account that signed in most recently, if any.
  """

  alias Firmowid.Core
  alias Firmowid.Core.OauthConsent
  alias Firmowid.Delegations
  alias Firmowid.Invoicing
  alias Firmowid.Payroll
  alias Firmowid.Timetracker

  require Ash.Query

  @doc "Returns counts and latest persisted traces for a selected organization."
  @spec load!(binary(), map(), DateTime.t()) :: map()
  def load!(organization_id, %{system_role: :superuser} = actor, now \\ DateTime.utc_now()) do
    from = DateTime.shift(now, day: -30)
    scope = %Firmowid.Scope{actor: actor, tenant: organization_id}

    inserted_window = %{inserted_from: from, inserted_to: now}
    cost_filters = %{source: :manual_import, is_ksef_imported: false}

    sales = Invoicing.list_sales_invoices!(%{}, latest_options(:inserted_at, scope))

    costs =
      Invoicing.list_cost_invoices!(
        cost_filters,
        [page: false] ++ latest_options(:inserted_at, scope)
      )

    sessions = Timetracker.list_sessions!(%{}, latest_options(:start_datetime, scope))
    latest = latest_options(:inserted_at, scope)

    %{
      leave_requests:
        inserted_summary(
          Timetracker.list_leave_requests!(%{}, latest),
          Timetracker.query_to_list_leave_requests(%{}, scope: scope),
          from,
          now,
          scope
        ),
      delegations:
        inserted_summary(
          Delegations.list_delegations!(%{}, latest),
          Delegations.query_to_list_delegations(%{}, scope: scope),
          from,
          now,
          scope
        ),
      employment_contracts:
        inserted_summary(
          Payroll.list_employment_contracts!(%{}, latest),
          Payroll.query_to_list_employment_contracts(%{}, scope: scope),
          from,
          now,
          scope
        ),
      assistant_connections:
        summary(
          OauthConsent.list!(%{}, latest_options(:granted_at, scope)),
          %{}
          |> OauthConsent.query_to_list(scope: scope)
          |> Ash.Query.filter(granted_at >= ^from and granted_at < ^now),
          :granted_at,
          scope
        ),
      last_sign_in: last_sign_in(scope),
      sales:
        summary(
          sales,
          Invoicing.query_to_list_sales_invoices(inserted_window, scope: scope),
          :inserted_at,
          scope
        ),
      costs:
        summary(
          costs,
          Invoicing.query_to_list_cost_invoices(Map.merge(cost_filters, inserted_window),
            scope: scope
          ),
          :inserted_at,
          scope
        ),
      sessions:
        summary(
          sessions,
          Timetracker.query_to_list_sessions(%{started_from: from, started_to: now},
            scope: scope
          ),
          :start_datetime,
          scope
        )
    }
  end

  defp last_sign_in(scope) do
    %{status: :active}
    |> Core.list_users!(
      scope: scope,
      load: [:member],
      query: [
        filter: [last_signed_in_at: [is_nil: false]],
        sort: [last_signed_in_at: :desc],
        limit: 1
      ]
    )
    |> List.first()
  end

  defp inserted_summary(latest_rows, query, from, now, scope) do
    recent_query = Ash.Query.filter(query, inserted_at >= ^from and inserted_at < ^now)
    summary(latest_rows, recent_query, :inserted_at, scope)
  end

  defp latest_options(field, scope) do
    [scope: scope, query: [sort: [{field, :desc}], limit: 1, select: [field]]]
  end

  defp summary(rows, recent_query, field, scope) do
    latest = List.first(rows)

    %{
      last_at: latest && Map.fetch!(latest, field),
      count_30_days: Ash.count!(recent_query, scope: scope)
    }
  end
end
