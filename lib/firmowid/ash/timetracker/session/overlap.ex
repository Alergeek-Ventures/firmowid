defmodule Firmowid.Ash.Timetracker.Session.Overlap do
  @moduledoc """
  Builds queries that find time-tracking sessions overlapping a proposed range.

  The predicates mirror the database trigger and are used for pre-save conflict
  detection.
  """

  require Ash.Query

  # Mirrors the DB trigger: start < COALESCE(new_end, 'infinity') AND COALESCE(end, 'infinity') > new.start
  #
  # We use a far-future sentinel instead of Postgres 'infinity' because Ash expressions
  # don't support the 'infinity' timestamp literal. The sentinel must exceed any realistic
  # session end time. This is safe because the DB trigger uses actual 'infinity' as the
  # authoritative constraint — this filter is only for the pre-save overlap query.
  @open_end_sentinel ~U[9999-12-31 23:59:59Z]

  @doc "Excludes a session from an overlap query when editing that session."
  @spec maybe_exclude_id(Ash.Query.t(), Ecto.UUID.t() | nil) :: Ash.Query.t()
  def maybe_exclude_id(query, nil), do: query
  def maybe_exclude_id(query, id), do: Ash.Query.filter(query, id != ^id)

  @doc "Filters sessions that overlap a proposed start and optional end datetime."
  @spec filter(Ash.Query.t(), DateTime.t(), DateTime.t() | nil) :: Ash.Query.t()
  def filter(query, new_start, nil) do
    # New session has no end (running) — overlaps anything that hasn't ended before new_start
    Ash.Query.filter(
      query,
      # if/3 is Ash expression syntax (ternary), not Elixir's if/do — parentheses are required.
      # credo:disable-for-next-line Credo.Check.Readability.ParenthesesInCondition
      if(is_nil(end_datetime), ^@open_end_sentinel, end_datetime) > ^new_start
    )
  end

  # credo:disable-for-lines:5 Credo.Check.Readability.ParenthesesInCondition
  def filter(query, new_start, new_end) do
    Ash.Query.filter(
      query,
      start_datetime < ^new_end and
        if(is_nil(end_datetime), ^@open_end_sentinel, end_datetime) > ^new_start
    )
  end
end
