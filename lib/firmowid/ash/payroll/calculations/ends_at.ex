defmodule Firmowid.Ash.Payroll.Calculations.EndsAt do
  @moduledoc false
  use Ash.Resource.Calculation

  @impl true
  def expression(_opts, _context) do
    expr(
      fragment(
        """
        (
          SELECT s2.starts_at
          FROM user_salaries s2
          WHERE s2.user_id = ?
            AND s2.starts_at > ?
          ORDER BY s2.starts_at ASC
          LIMIT 1
        )
        """,
        user_id,
        starts_at
      )
    )
  end
end
