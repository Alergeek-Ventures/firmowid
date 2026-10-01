defmodule FirmowidWeb.Admin.Utilities.OrganizationActivity do
  @moduledoc """
  Read-only, tenant-bound traces of persisted organization activity for the superuser worksheet.

  Counts cover the rolling 30 * 24 hours ending at `now` (inclusive start, exclusive end).
  Latest timestamps are not limited to that window. These are record creation / session
  start times, not evidence of a login or of the person who performed the action.
  """

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Timetracker

  @doc "Returns counts and latest persisted traces for a selected organization."
  @spec load!(binary(), map(), DateTime.t()) :: map()
  def load!(organization_id, %{system_role: :superuser} = actor, now \\ DateTime.utc_now()) do
    from = DateTime.shift(now, day: -30)
    scope = %Firmowid.Ash.Scope{actor: actor, tenant: organization_id}

    inserted_window = %{inserted_from: from, inserted_to: now}
    cost_filters = %{source: :manual_import, is_ksef_imported: false}

    sales = Invoicing.list_sales_invoices!(%{}, latest_options(:inserted_at, scope))

    costs =
      Invoicing.list_cost_invoices!(
        cost_filters,
        [page: false] ++ latest_options(:inserted_at, scope)
      )

    sessions = Timetracker.list_sessions!(%{}, latest_options(:start_datetime, scope))

    %{
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
