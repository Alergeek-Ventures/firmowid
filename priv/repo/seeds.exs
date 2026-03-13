# Seed data for the Firmowid development environment.
#
# The seed modules are organized by concern:
#
#   seeds/helpers.exs    — date utilities, idempotent insert helpers
#   seeds/bytecraft.exs  — Bytecraft Collective org, users, counterparties, projects, bank accounts
#   seeds/month_m2.exs   — 2 months ago: fully matched revenue, costs, THB, tags
#   seeds/month_m1.exs   — 1 month ago: fully matched revenue, costs, THB, tags
#   seeds/month_m0.exs   — current month: unmatched transactions, KSeF showcase, 1 matched entry
#   seeds/timetracker.exs — salaries, time tracking sessions, hours records
#   seeds/voidstack.exs  — VoidStack Labs evil org for authorization testing
#
# Run with: mix run priv/repo/seeds.exs
# Idempotent — safe to re-run without duplicating data.

alias Firmowid.Repo
alias Firmowid.Seeds.Bytecraft
alias Firmowid.Seeds.MonthM0
alias Firmowid.Seeds.MonthM1
alias Firmowid.Seeds.MonthM2
alias Firmowid.Seeds.Timetracker, as: TimetrackerSeeds
alias Firmowid.Seeds.Voidstack

seeds_dir = Path.join(__DIR__, "seeds")

for file <- ~w(helpers bytecraft month_m2 month_m1 month_m0 timetracker voidstack) do
  Code.require_file("#{file}.exs", seeds_dir)
end

Repo.transaction(fn ->
  # — Primary organization: Bytecraft Collective —
  ctx = Bytecraft.seed!()

  # — Monthly financial data (newest → oldest for tagging context) —
  MonthM2.seed!(ctx)
  MonthM1.seed!(ctx)
  MonthM0.seed!(ctx)

  # — Timetracker: salaries, sessions, hours records —
  TimetrackerSeeds.seed!(ctx)

  # — Evil org: VoidStack Labs —
  Voidstack.seed!()
end)
