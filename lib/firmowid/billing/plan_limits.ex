defmodule Firmowid.Billing.PlanLimits do
  @moduledoc """
  Keeps an organization within its billing plan.

  When the organization uses more than its plan includes, its admins are told at
  once and get a decision day: the 1st of the next month the first time, today
  on every later occasion. From that day they buy a higher plan or choose what
  stays switched on (`keep/3`). Without a decision, the newest excess is switched
  off `decision_days/0` days later. Nothing is deleted: members and projects are
  archived and bank accounts stop synchronizing, all marked `suspended_by_plan_at`,
  so a higher plan brings them back (`plan_changed/2`).

  The plans limit banks, not accounts: a bank stays or goes with all its
  synchronized accounts.

  `check/2` starts and ends decisions; `Firmowid.Billing.Workers.PlanLimitsWorker`
  runs it for every organization.
  """

  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Billing.PlanLimitEmails
  alias Firmowid.Billing.SnapshotCalculator
  alias Firmowid.Core
  alias Firmowid.Core.Member
  alias Firmowid.Core.Organization
  alias Firmowid.Finances
  alias Firmowid.Finances.BankAccount
  alias Firmowid.Scope
  alias Firmowid.SystemActor
  alias Firmowid.Timetracker
  alias Firmowid.Timetracker.Project

  require Ash.Query

  @decision_days 7
  @warsaw_timezone "Europe/Warsaw"

  @typedoc "A bank the organization synchronizes, with its synchronized accounts, oldest first."
  @type bank :: %{id: String.t(), name: String.t(), accounts: [BankAccount.t(), ...]}

  @type switched_on :: %{
          users: [Member.t()],
          bank_institutions: [bank()],
          active_projects: [Project.t()]
        }

  @typedoc """
  The ids that stay switched on, per limited thing; a missing key keeps all of
  them. A bank's id is its `institution_id`.
  """
  @type kept :: %{optional(PlanCatalog.limited()) => [Ash.UUID.t() | String.t()]}

  @doc "Returns the system scope that keeps the organization within its plan."
  @spec scope(Ash.UUID.t()) :: Scope.t()
  def scope(organization_id) do
    %Scope{
      actor: %SystemActor{org_id: organization_id, role: :plan_limits},
      tenant: organization_id
    }
  end

  @doc "Returns today's date in Poland, where the decision days fall."
  @spec today() :: Date.t()
  def today, do: @warsaw_timezone |> DateTime.now!() |> DateTime.to_date()

  @doc "Returns how many days after the decision day the excess is switched off without a decision."
  @spec decision_days() :: pos_integer()
  def decision_days, do: @decision_days

  @doc "Whether the organization's admins must decide now."
  @spec decision_due?(Organization.t()) :: boolean()
  def decision_due?(%Organization{plan_limit_decision_on: nil}), do: false

  def decision_due?(%Organization{plan_limit_decision_on: day}), do: Date.compare(day, today()) != :gt

  @doc "Returns the day the excess is switched off without a decision."
  @spec switch_off_on(Organization.t()) :: Date.t()
  def switch_off_on(%Organization{plan_limit_decision_on: %Date{} = day}), do: Date.add(day, @decision_days)

  @doc "Returns what the organization uses of the things the plans limit, as billing counts it."
  @spec usage(Organization.t()) :: PlanCatalog.usage()
  def usage(%Organization{} = organization) do
    organization
    |> SnapshotCalculator.build_snapshot_attrs!(today())
    |> PlanCatalog.usage()
  end

  @doc """
  Returns everything the plans limit that is switched on, oldest first: the owner
  first among the members, the banks by their oldest account.
  """
  @spec switched_on(Organization.t(), Scope.t()) :: switched_on()
  def switched_on(%Organization{owner_id: owner_id}, scope) do
    members =
      %{status: :active}
      |> Core.list_users!(scope: scope, load: [member: [:display_name]])
      |> Enum.map(& &1.member)
      |> Enum.sort_by(&{&1.user_id != owner_id, DateTime.to_unix(&1.inserted_at, :microsecond), &1.id})

    # The same accounts the usage counts banks from.
    bank_accounts =
      scope
      |> SnapshotCalculator.synced_bank_institution_accounts_query()
      |> Ash.Query.sort(inserted_at: :asc, id: :asc)
      |> Ash.read!(scope: scope)

    projects =
      Timetracker.list_projects!(%{status: :active},
        scope: scope,
        query: [sort: [inserted_at: :asc, id: :asc]]
      )

    %{users: members, bank_institutions: banks(bank_accounts), active_projects: projects}
  end

  defp banks(bank_accounts) do
    bank_accounts
    |> Enum.group_by(& &1.institution_id)
    |> Enum.map(fn {institution_id, [oldest | _newer] = accounts} ->
      %{id: institution_id, name: oldest.institution_name, accounts: accounts}
    end)
    |> Enum.sort_by(fn %{accounts: [oldest | _newer]} ->
      {DateTime.to_unix(oldest.inserted_at, :microsecond), oldest.id}
    end)
  end

  @doc """
  Brings the organization's plan-limit decision up to date.

  Usage within the plan ends a pending decision. Usage above it starts one,
  emailing the admins first, so a failed update sends again rather than never.
  From `decision_days/0` after the decision day, the newest excess is switched off.
  Organizations without a plan are blocked and skipped.
  """
  @spec check(Organization.t(), Date.t()) :: {:ok, Organization.t()} | {:error, term()}
  def check(organization, today \\ today())

  def check(%Organization{billing_plan: :no_plan} = organization, _today), do: {:ok, organization}

  def check(%Organization{} = organization, today) do
    scope = scope(organization.id)
    usage = usage(organization)
    exceeded = PlanCatalog.exceeded(usage, organization.billing_plan)

    cond do
      exceeded == [] and is_nil(organization.plan_limit_decision_on) ->
        {:ok, organization}

      exceeded == [] ->
        Core.update_organization_plan_limit_decision(organization, %{plan_limit_decision_on: nil}, scope: scope)

      is_nil(organization.plan_limit_decision_on) ->
        start_decision(organization, usage, exceeded, today, scope)

      Date.compare(today, switch_off_on(organization)) != :lt ->
        switch_off_excess(organization, scope)

      true ->
        {:ok, organization}
    end
  end

  @doc """
  Keeps switched on only the `kept` ids and switches the rest off, then ends the
  decision. What stays must fit the plan; the owner always stays.
  """
  @spec keep(Organization.t(), kept(), Scope.t()) :: {:ok, Organization.t()} | {:error, term()}
  def keep(%Organization{} = organization, kept, scope) do
    with {:ok, organization, _switched_off} <- keep_and_count(organization, kept, scope) do
      {:ok, organization}
    end
  end

  @doc """
  Reacts to a changed plan: a plan that costs more brings back everything the
  plans switched off. A pending decision is brought up to date; a new one is
  never started here, only by `check/2` from the scheduled job.
  """
  @spec plan_changed(Organization.t(), PlanCatalog.plan()) ::
          {:ok, Organization.t()} | {:error, term()}
  def plan_changed(%Organization{} = organization, previous_plan) do
    with :ok <- maybe_restore(organization, previous_plan) do
      if organization.plan_limit_decision_on, do: check(organization), else: {:ok, organization}
    end
  end

  defp start_decision(organization, usage, exceeded, today, scope) do
    {decision_on, free_month_used_at} =
      case organization.plan_limit_free_month_used_at do
        nil -> {today |> Date.end_of_month() |> Date.add(1), DateTime.utc_now()}
        used_at -> {today, used_at}
      end

    admins = Core.list_users!(%{status: :active, role: :admin}, scope: scope)

    with {:ok, _email} <-
           PlanLimitEmails.deliver_limit_exceeded(
             admins,
             organization,
             usage,
             exceeded,
             decision_on
           ) do
      Core.update_organization_plan_limit_decision(
        organization,
        %{plan_limit_decision_on: decision_on, plan_limit_free_month_used_at: free_month_used_at},
        scope: scope
      )
    end
  end

  # Keeps the oldest of each kind, as many as the plan includes.
  defp switch_off_excess(organization, scope) do
    limits = PlanCatalog.plan!(organization.billing_plan).limits

    kept =
      organization
      |> switched_on(scope)
      |> Map.new(fn {limited, items} ->
        {limited, items |> keep_oldest(limits[limited]) |> Enum.map(& &1.id)}
      end)

    admins = Core.list_users!(%{status: :active, role: :admin}, scope: scope)

    with {:ok, organization, switched_off} <- keep_and_count(organization, kept, scope),
         {:ok, _email} <-
           PlanLimitEmails.deliver_excess_switched_off(admins, organization, switched_off) do
      {:ok, organization}
    end
  end

  defp keep_oldest(items, :unlimited), do: items
  defp keep_oldest(items, limit), do: Enum.take(items, limit)

  defp keep_and_count(organization, kept, scope) do
    splits =
      organization
      |> switched_on(scope)
      |> Map.new(fn {limited, items} ->
        {limited, split(limited, items, Map.get(kept, limited), organization.owner_id)}
      end)

    staying_usage =
      Map.new(splits, fn {limited, {staying, _leaving}} -> {limited, length(staying)} end)

    leaving = Map.new(splits, fn {limited, {_staying, leaving}} -> {limited, leaving} end)

    if PlanCatalog.exceeded(staying_usage, organization.billing_plan) == [] do
      switch_off(organization, leaving, scope)
    else
      {:error, :over_limit}
    end
  end

  # The owner always stays; without a choice for a kind, all of it stays.
  defp split(_limited, items, nil, _owner_id), do: {items, []}

  defp split(:users, members, kept_ids, owner_id) do
    Enum.split_with(members, &(&1.user_id == owner_id or &1.id in kept_ids))
  end

  defp split(_limited, items, kept_ids, _owner_id), do: Enum.split_with(items, &(&1.id in kept_ids))

  defp switch_off(organization, leaving, scope) do
    archive = &Core.archive_member(&1, %{by_plan?: true}, scope: scope)
    archive_project = &Project.archive(&1, %{by_plan?: true}, scope: scope)
    suspend = &Finances.suspend_bank_account_by_plan(&1, scope: scope)

    result =
      Ash.transact([Member, Project, BankAccount, Organization], fn ->
        with :ok <- each(leaving.users, archive),
             :ok <- each(leaving.active_projects, archive_project),
             :ok <- each(Enum.flat_map(leaving.bank_institutions, & &1.accounts), suspend),
             {:ok, organization} <- check(organization) do
          {organization, Map.new(leaving, fn {limited, items} -> {limited, length(items)} end)}
        end
      end)

    case result do
      {:ok, {organization, switched_off}} -> {:ok, organization, switched_off}
      {:error, error} -> {:error, error}
    end
  end

  defp maybe_restore(organization, previous_plan) do
    if Decimal.gt?(
         PlanCatalog.plan!(organization.billing_plan).monthly_price_pln,
         PlanCatalog.plan!(previous_plan).monthly_price_pln
       ) do
      restore(scope(organization.id))
    else
      :ok
    end
  end

  # Only what the plan switched off; what admins archived by hand stays archived.
  defp restore(scope) do
    members =
      %{status: :archived}
      |> Core.list_users!(scope: scope, load: [:member])
      |> Enum.map(& &1.member)
      |> Enum.filter(& &1.suspended_by_plan_at)

    projects =
      Timetracker.list_projects!(%{status: :archived},
        scope: scope,
        query: Ash.Query.filter(Project, not is_nil(suspended_by_plan_at))
      )

    bank_accounts =
      Finances.list_bank_accounts!(
        scope: scope,
        query: Ash.Query.filter(BankAccount, not is_nil(suspended_by_plan_at))
      )

    with :ok <- each(members, &Core.unarchive_member(&1, scope: scope)),
         :ok <- each(projects, &Project.unarchive(&1, scope: scope)) do
      each(bank_accounts, &Finances.restore_bank_account_from_plan(&1, scope: scope))
    end
  end

  defp each(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        {:ok, _result} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
