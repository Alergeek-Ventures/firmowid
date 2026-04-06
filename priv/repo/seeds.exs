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
#
# If the Bytecraft org already exists the database is considered seeded
# and the entire script is a no-op (fast early exit).

alias Firmowid.Ash.Core.Organization, as: CoreOrganization
alias Firmowid.Repo
alias Firmowid.Seeds.Bytecraft
alias Firmowid.Seeds.MonthM0
alias Firmowid.Seeds.MonthM1
alias Firmowid.Seeds.MonthM2
alias Firmowid.Seeds.Timetracker, as: TimetrackerSeeds
alias Firmowid.Seeds.Voidstack

require Ash.Query

seeds_dir = Path.join(__DIR__, "seeds")

for file <- ~w(helpers bytecraft month_m2 month_m1 month_m0 timetracker voidstack) do
  Code.require_file("#{file}.exs", seeds_dir)
end

already_seeded? =
  case Ash.read(Ash.Query.filter(CoreOrganization, nip == ^"6161525811"),
         authorize?: false,
         actor: %{}
       ) do
    {:ok, [_ | _]} -> true
    _ -> false
  end

if already_seeded? do
  IO.puts("[seeds] Database already seeded — skipping")
else
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
end

# — Feature flags (always runs, idempotent) —
FunWithFlags.enable(:analysis_dashboard, for_group: "domain:alergeek.ventures")
