defmodule Firmowid.Ash.Payroll.MemberTaxDeclaration do
  @moduledoc "Effective-dated declarations and non-effective document-import drafts for organization members."
  use Ash.Resource,
    domain: Firmowid.Ash.Payroll,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.ActorRole
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Payroll.Actions.ImportMemberTaxDeclaration
  alias Firmowid.Ash.Payroll.Validations.ImmutableAppliesFrom
  alias Firmowid.Ash.Resource

  require Resource

  @declaration_fields [
    :received_on,
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

  postgres do
    table "member_tax_declarations"
    repo Firmowid.Repo

    references do
      reference :member, on_delete: :delete
      reference :organization, on_delete: :delete
      reference :source_blob, on_delete: :nilify
    end
  end

  code_interface do
    define :read, action: :read
    define :create_tax_declaration, action: :create
    define :list_tax_declarations, action: :list
    define :correct_tax_declaration, action: :correct
    define :create_imported_tax_declaration, action: :import_create
    define :update_imported_tax_declaration, action: :import_update
    define :import_from_document, action: :import_from_document, args: [:attrs_map]
  end

  actions do
    defaults [:read]

    read :list do
      description "List declarations, optionally by member, source document or effective date."
      argument :member_id, :uuid
      argument :source_blob_id, :uuid
      argument :as_of, :date

      prepare build(sort: [applies_from: :desc_nils_last])

      prepare build(filter: expr(member_id == ^arg(:member_id))) do
        where present(:member_id)
      end

      prepare build(filter: expr(source_blob_id == ^arg(:source_blob_id))) do
        where present(:source_blob_id)
      end

      prepare build(filter: expr(not is_nil(received_on) and applies_from <= ^arg(:as_of))) do
        where present(:as_of)
      end
    end

    create :create do
      description "Create a declaration version without replacing a version with the same effective date."
      primary? true
      accept [:member_id, :applies_from | @declaration_fields]
    end

    update :correct do
      description "Complete an imported draft or correct a declaration without moving its established effective date."
      primary? true
      accept [:applies_from | @declaration_fields]
      require_atomic? false

      change {Firmowid.Ash.Payroll.Changes.CompleteImportedDeclaration, fields: @declaration_fields -- [:received_on]}

      validate {ImmutableAppliesFrom, []}
    end

    create :import_create do
      description "Create a partial declaration imported from a document."
      accept [:member_id, :source_blob_id, :applies_from | @declaration_fields]
    end

    update :import_update do
      description "Merge explicit facts from a document into an imported declaration."
      accept [:source_blob_id, :applies_from | @declaration_fields]
      require_atomic? false
      validate {ImmutableAppliesFrom, []}
    end

    action :import_from_document, :struct do
      description "Import explicit declaration facts from an employee document."
      argument :attrs_map, :map, allow_nil?: false
      run ImportMemberTaxDeclaration
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {ActorRole, role: :admin}
      authorize_if expr(member_id == ^actor([:member, :id]))
      authorize_if {SystemActorRole, roles: [:document_blob_processor]}
    end

    policy action([:create, :correct]) do
      authorize_if {ActorRole, role: :admin}
    end

    policy action([:import_from_document, :import_create, :import_update]) do
      authorize_if {ActorRole, role: :admin}
      authorize_if {SystemActorRole, roles: [:document_blob_processor]}
    end
  end

  validations do
    validate compare(:received_on, less_than_or_equal_to: :applies_from),
      on: [:create, :update],
      where: [present(:received_on), present(:applies_from)],
      message: "is invalid"

    validate present(:received_on),
      on: [:create, :update],
      where: [action_is([:create, :correct])],
      message: "can't be blank"

    validate present(:applies_from),
      on: [:create, :update],
      where: [action_is([:create, :correct])],
      message: "can't be blank"

    validate present(:request_year),
      on: [:create, :update],
      where: [action_is([:create, :correct]), attribute_equals(:tax_mode, :no_advance)],
      message: "can't be blank"

    validate present(:request_year),
      on: [:create, :update],
      where: [
        action_is([:create, :correct]),
        present(:preferential),
        attribute_does_not_equal(:preferential, :none)
      ],
      message: "can't be blank"

    validate present(:ppk_employee_rate),
      on: [:create, :update],
      where: [action_is([:create, :correct]), attribute_equals(:ppk, :participant)],
      message: "can't be blank"

    validate Firmowid.Ash.Payroll.Validations.MemberInOrganization,
      on: [:create],
      where: [present(:member_id)]

    validate Firmowid.Ash.Payroll.Validations.SourceBlobInOrganization,
      on: [:create, :update],
      where: [present(:source_blob_id)]
  end

  multitenancy do
    strategy :attribute
    attribute :organization_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :received_on, :date
    attribute :applies_from, :date
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

    belongs_to :source_blob, Firmowid.Ash.Blobs.Blob do
      allow_nil? true
      attribute_writable? true
    end
  end

  identities do
    identity :unique_member_effective_date, [:member_id, :organization_id, :applies_from], field_names: [:applies_from]

    identity :unique_source_blob, [:source_blob_id]
  end
end
