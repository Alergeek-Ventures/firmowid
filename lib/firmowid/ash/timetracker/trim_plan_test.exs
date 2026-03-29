defmodule Firmowid.Ash.Timetracker.TrimPlanTest do
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Timetracker.TrimPlan

  defp session(id, start, end_dt, opts \\ []) do
    %{
      id: id,
      title: opts[:title] || "Session #{id}",
      start_datetime: start,
      end_datetime: end_dt,
      project_id: opts[:project_id] || "proj-1",
      is_remote: opts[:is_remote] || false,
      user_id: opts[:user_id] || "user-1",
      lockdown: opts[:lockdown] || false
    }
  end

  describe "compute/3 — end trim" do
    test "trims existing session's end to new session's start" do
      # Existing: 08:00-12:00, New: 10:00-14:00
      existing = session("s1", ~U[2026-01-01 08:00:00Z], ~U[2026-01-01 12:00:00Z])

      assert {:ok, [{:trim_end, ^existing, ~U[2026-01-01 10:00:00Z]}]} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], ~U[2026-01-01 14:00:00Z], [existing])
    end

    test "trims running session's end (sets end_datetime)" do
      # Existing: 08:00-nil (running), New: 10:00-12:00
      # Running session fully contains new -> split, not end-trim
      # Use a case where running starts before and new also runs: 08:00-nil vs 10:00-nil
      existing = session("s1", ~U[2026-01-01 08:00:00Z], nil)

      assert {:ok, [{:trim_end, ^existing, ~U[2026-01-01 10:00:00Z]}]} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], nil, [existing])
    end
  end

  describe "compute/3 — start trim" do
    test "trims existing session's start to new session's end" do
      # Existing: 12:00-16:00, New: 10:00-14:00
      existing = session("s1", ~U[2026-01-01 12:00:00Z], ~U[2026-01-01 16:00:00Z])

      assert {:ok, [{:trim_start, ^existing, ~U[2026-01-01 14:00:00Z]}]} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], ~U[2026-01-01 14:00:00Z], [existing])
    end
  end

  describe "compute/3 — delete (fully contained)" do
    test "deletes session fully contained in new range" do
      # Existing: 11:00-13:00, New: 10:00-14:00
      existing = session("s1", ~U[2026-01-01 11:00:00Z], ~U[2026-01-01 13:00:00Z])

      assert {:ok, [{:delete, ^existing}]} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], ~U[2026-01-01 14:00:00Z], [existing])
    end

    test "deletes session when new session starts at same time" do
      # Existing: 10:00-12:00, New: 10:00-14:00
      existing = session("s1", ~U[2026-01-01 10:00:00Z], ~U[2026-01-01 12:00:00Z])

      assert {:ok, [{:delete, ^existing}]} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], ~U[2026-01-01 14:00:00Z], [existing])
    end

    test "deletes session when new session is running and existing starts after" do
      # Existing: 12:00-16:00, New: 10:00-nil (running)
      existing = session("s1", ~U[2026-01-01 12:00:00Z], ~U[2026-01-01 16:00:00Z])

      assert {:ok, [{:delete, ^existing}]} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], nil, [existing])
    end
  end

  describe "compute/3 — split (fully containing)" do
    test "splits session that fully contains new range" do
      # Existing: 08:00-16:00, New: 10:00-12:00
      existing =
        session("s1", ~U[2026-01-01 08:00:00Z], ~U[2026-01-01 16:00:00Z],
          title: "Long task",
          project_id: "proj-x",
          is_remote: true
        )

      assert {:ok, [{:split, ^existing, ~U[2026-01-01 10:00:00Z], remainder}]} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], ~U[2026-01-01 12:00:00Z], [existing])

      assert remainder.title == "Long task"
      assert remainder.project_id == "proj-x"
      assert remainder.is_remote == true
      assert remainder.start_datetime == ~U[2026-01-01 12:00:00Z]
      assert remainder.end_datetime == ~U[2026-01-01 16:00:00Z]
      assert remainder.user_id == "user-1"
    end

    test "splits running session — remainder inherits nil end" do
      # Existing: 08:00-nil (running), New: 10:00-12:00
      existing = session("s1", ~U[2026-01-01 08:00:00Z], nil)

      assert {:ok, [{:split, ^existing, ~U[2026-01-01 10:00:00Z], remainder}]} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], ~U[2026-01-01 12:00:00Z], [existing])

      assert remainder.start_datetime == ~U[2026-01-01 12:00:00Z]
      assert is_nil(remainder.end_datetime)
    end
  end

  describe "compute/3 — locked sessions" do
    test "returns error when any overlapping session is locked" do
      locked = session("s1", ~U[2026-01-01 08:00:00Z], ~U[2026-01-01 12:00:00Z], lockdown: true)
      unlocked = session("s2", ~U[2026-01-01 13:00:00Z], ~U[2026-01-01 15:00:00Z])

      assert {:error, :locked_conflict, [^locked]} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], ~U[2026-01-01 14:00:00Z], [
                 locked,
                 unlocked
               ])
    end

    test "returns all locked sessions in error" do
      locked1 = session("s1", ~U[2026-01-01 08:00:00Z], ~U[2026-01-01 12:00:00Z], lockdown: true)
      locked2 = session("s2", ~U[2026-01-01 13:00:00Z], ~U[2026-01-01 15:00:00Z], lockdown: true)

      assert {:error, :locked_conflict, locked_sessions} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], ~U[2026-01-01 14:00:00Z], [
                 locked1,
                 locked2
               ])

      assert length(locked_sessions) == 2
    end
  end

  describe "compute/3 — multiple overlaps" do
    test "handles end-trim + delete + start-trim in one pass" do
      before_s = session("sa", ~U[2026-01-01 08:00:00Z], ~U[2026-01-01 11:00:00Z])
      middle_s = session("sb", ~U[2026-01-01 11:00:00Z], ~U[2026-01-01 13:00:00Z])
      after_s = session("sc", ~U[2026-01-01 13:00:00Z], ~U[2026-01-01 16:00:00Z])

      assert {:ok, actions} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], ~U[2026-01-01 14:00:00Z], [
                 before_s,
                 middle_s,
                 after_s
               ])

      assert [
               {:trim_end, ^before_s, ~U[2026-01-01 10:00:00Z]},
               {:delete, ^middle_s},
               {:trim_start, ^after_s, ~U[2026-01-01 14:00:00Z]}
             ] = actions
    end

    test "handles split + delete in one pass" do
      # Big session: 08:00-18:00, small inside: 11:00-12:00
      # New: 10:00-14:00
      # Big gets split (but actually it's end-trimmed because new starts inside it
      # and ends inside it... wait, big starts at 08:00 < 10:00 and ends at 18:00 > 14:00 = split)
      # Small gets deleted (11:00-12:00 fully inside 10:00-14:00)
      big_s = session("big", ~U[2026-01-01 08:00:00Z], ~U[2026-01-01 18:00:00Z])
      small_s = session("small", ~U[2026-01-01 11:00:00Z], ~U[2026-01-01 12:00:00Z])

      assert {:ok, actions} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], ~U[2026-01-01 14:00:00Z], [
                 big_s,
                 small_s
               ])

      assert [{:split, ^big_s, ~U[2026-01-01 10:00:00Z], remainder}, {:delete, ^small_s}] =
               actions

      assert remainder.start_datetime == ~U[2026-01-01 14:00:00Z]
      assert remainder.end_datetime == ~U[2026-01-01 18:00:00Z]
    end
  end

  describe "compute/3 — edge cases" do
    test "returns empty list when no overlapping sessions" do
      assert {:ok, []} = TrimPlan.compute(~U[2026-01-01 10:00:00Z], ~U[2026-01-01 12:00:00Z], [])
    end

    test "exact same boundaries — existing is deleted" do
      # Existing: 10:00-12:00, New: 10:00-12:00
      existing = session("s1", ~U[2026-01-01 10:00:00Z], ~U[2026-01-01 12:00:00Z])

      assert {:ok, [{:delete, ^existing}]} =
               TrimPlan.compute(~U[2026-01-01 10:00:00Z], ~U[2026-01-01 12:00:00Z], [existing])
    end
  end
end
