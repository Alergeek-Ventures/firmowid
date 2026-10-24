defmodule Firmowid.Ash.Payroll.MemberTaxDeclaration do
  @moduledoc "Daily versions of an organization member's tax and insurance declarations."
  use Ash.Resource,
    domain: Firmowid.Ash.Payroll,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.ActorRole
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "member_tax_declarations"
    repo Firmowid.Repo

    references do
      reference :member, on_delete: :delete
      reference :organization, on_delete: :delete
    end
  end

  code_interface do
    define :read, action: :read
    define :list_tax_declarations, action: :list
    define :save_tax_declaration, action: :save_tax_declaration
  end

  actions do
    defaults [:read]

    read :list do
      description "List a member's declarations, optionally effective on or before a date."
      argument :member_id, :uuid, allow_nil?: false
      argument :as_of, :date

      filter expr(member_id == ^arg(:member_id))
      prepare build(sort: [applies_from: :desc])

      prepare build(filter: expr(applies_from <= ^arg(:as_of))) do
        where present(:as_of)
      end
    end

    create :save_tax_declaration do
      description "Save a daily declaration version, retaining versions with other effective dates."
      primary? true
      upsert? true
      upsert_identity :unique_member_effective_date

      accept [
        :member_id,
        :received_on,
        :applies_from,
        :tax_residency,
        :pit2,
        :employee_costs,
        :youth_relief,
        :pit0,
        :tax_mode,
        :request_year,
        :preferential,
        :student,
        :student_until,
        :other_employment,
        :own_employer,
        :sickness,
        :copyright_costs,
        :ppk,
        :ppk_employee_rate
      ]

      validate compare(:received_on, less_than_or_equal_to: :applies_from), message: "is invalid"

      validate present(:request_year),
        where: [attribute_equals(:tax_mode, :no_advance)],
        message: "can't be blank"

      validate present(:request_year),
        where: [present(:preferential), attribute_does_not_equal(:preferential, :none)],
        message: "can't be blank"

      validate present(:ppk_employee_rate),
        where: [attribute_equals(:ppk, :participant)],
        message: "can't be blank"

      validate Firmowid.Ash.Payroll.Validations.TaxDeclarationMemberInOrganization
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {ActorRole, role: :admin}
      authorize_if expr(member_id == ^actor([:member, :id]))
    end

    policy action_type(:create) do
      authorize_if {ActorRole, role: :admin}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :received_on, :date, allow_nil?: false
    attribute :applies_from, :date, allow_nil?: false
    attribute :tax_residency, :atom, constraints: [one_of: [:poland, :other]]

    attribute :pit2, :atom, constraints: [one_of: [:none, :one_twelfth, :one_twenty_fourth, :one_thirty_sixth]]

    attribute :employee_costs, :atom, constraints: [one_of: [:none, :standard, :elevated]]
    attribute :youth_relief, :atom, constraints: [one_of: [:apply, :waived]]
    attribute :pit0, :atom, constraints: [one_of: [:none, :returning, :family, :senior]]
    attribute :tax_mode, :atom, constraints: [one_of: [:standard, :higher, :no_advance]]
    attribute :request_year, :integer, constraints: [min: 2022, max: 2100]

    attribute :preferential, :atom,
      constraints: [one_of: [:none, :joint_below, :joint_above, :single_below, :single_above]]

    attribute :student, :boolean
    attribute :student_until, :date

    attribute :other_employment, :atom, constraints: [one_of: [:none, :below_minimum, :at_least_minimum, :other]]

    attribute :own_employer, :boolean
    attribute :sickness, :boolean
    attribute :copyright_costs, :boolean
    attribute :ppk, :atom, constraints: [one_of: [:none, :participant]]
    attribute :ppk_employee_rate, :decimal, constraints: [min: "0.5", max: "4"]

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :member, Firmowid.Ash.Core.Member do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
    end
  end

  identities do
    identity :unique_member_effective_date, [:member_id, :organization_id, :applies_from]
  end
end
