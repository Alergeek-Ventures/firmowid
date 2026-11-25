defmodule Firmowid.Taxes.Partner do
  @moduledoc """
  An owner who pays their own income tax and ZUS on the company's profit in a
  tax year: the owner of a sole proprietorship or a civil partnership partner.

  Partners are team members and are saved through the tax year's `partners`
  argument, matched by `member_id`.
  """
  use Ash.Resource,
    domain: Firmowid.Taxes,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  use Gettext, backend: Firmowid.Gettext

  alias Firmowid.Checks.ActorRole
  alias Firmowid.Checks.AtLeastRole
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Core.Validations.MemberInOrganization
  alias Firmowid.Resource

  require Resource

  # The rates of the lump sum on recorded revenue (ryczałt od przychodów
  # ewidencjonowanych), art. 12 of the flat-rate income tax act.
  @lump_sum_rates Enum.map(~w(2 3 5.5 8.5 10 12 12.5 14 15 17), &Decimal.new/1)

  @settings [
    :profit_share,
    :income_tax,
    :lump_sum_rate,
    :pit_advances,
    :social_insurance,
    :voluntary_sickness
  ]

  postgres do
    table "tax_year_partners"
    repo Firmowid.Repo

    references do
      reference :organization, on_delete: :delete
      reference :tax_year, on_delete: :delete
      # Like every other member reference: a member row is deleted only with its
      # account or organization (leaving the team archives it), and a restriction
      # would block both, including the organization cleanup that destroys members.
      reference :member, on_delete: :delete
    end
  end

  @doc "The lump sum rates in percent a partner may choose."
  @spec lump_sum_rates() :: [Decimal.t()]
  def lump_sum_rates, do: @lump_sum_rates

  # The tax year's `partners` argument manages partners through these primary actions;
  # the project's Credo check requires every action to have a code interface.
  code_interface do
    define :read, action: :read
    define :create, action: :create
    define :update, action: :update
    define :destroy, action: :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      description "Add a team member as a partner of the tax year."
      primary? true
      accept [:member_id | @settings]
    end

    update :update do
      description "Change a partner's share and how they pay income tax and ZUS."
      primary? true
      accept @settings
    end
  end

  policies do
    bypass [{SystemActorRole, roles: [:tax_forecaster]}, action_type(:read)] do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if {AtLeastRole, role: :accountant}
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {ActorRole, role: :admin}
    end
  end

  validations do
    validate present(:lump_sum_rate),
      where: [attribute_equals(:income_tax, :lump_sum)],
      message: gettext_noop("Choose the lump sum rate.")

    validate absent(:lump_sum_rate),
      where: [attribute_does_not_equal(:income_tax, :lump_sum)],
      message: gettext_noop("Only the lump sum on revenue has a rate to choose.")

    validate one_of(:lump_sum_rate, @lump_sum_rates)

    # Without own social contributions there is no sickness insurance to join.
    validate attribute_equals(:voluntary_sickness, false),
      where: [attribute_in(:social_insurance, [:start_relief, :none])],
      message: gettext_noop("Voluntary sickness insurance needs own social contributions.")

    # Read once before saving, not on every form validation.
    validate MemberInOrganization, on: [:create], before_action?: true
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :profit_share, :decimal,
      allow_nil?: false,
      public?: true,
      description: "The partner's share of the profit in percent.",
      constraints: [greater_than: 0, max: 100]

    attribute :income_tax, :atom,
      allow_nil?: false,
      public?: true,
      description: "The income tax form: the tax scale, the 19% flat tax or the lump sum on revenue.",
      constraints: [one_of: [:tax_scale, :flat_tax, :lump_sum]]

    attribute :lump_sum_rate, :decimal,
      public?: true,
      description: "The lump sum rate in percent; only with the lump sum on revenue."

    attribute :pit_advances, :atom,
      allow_nil?: false,
      public?: true,
      description: "How often the partner pays income tax advances, due on the 20th.",
      constraints: [one_of: [:monthly, :quarterly]]

    attribute :social_insurance, :atom,
      allow_nil?: false,
      public?: true,
      description:
        "The partner's own ZUS social contributions: start relief (health only for 6 months), preferential, " <>
          "Mały ZUS Plus, full, or none (insured elsewhere, e.g. employed at least at the minimum wage or " <>
          "retired). The health contribution is due in every case.",
      constraints: [one_of: [:start_relief, :preferential, :small_plus, :full, :none]]

    attribute :voluntary_sickness, :boolean,
      allow_nil?: false,
      public?: true,
      default: false,
      description: "Whether the partner pays the voluntary sickness insurance."

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Core.Organization do
      allow_nil? false
    end

    belongs_to :tax_year, Firmowid.Taxes.TaxYear do
      allow_nil? false
    end

    belongs_to :member, Firmowid.Core.Member do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_member, [:tax_year_id, :member_id]
  end
end
