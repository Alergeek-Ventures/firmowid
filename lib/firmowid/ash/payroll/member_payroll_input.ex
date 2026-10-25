defmodule Firmowid.Ash.Payroll.MemberPayrollInput do
  @moduledoc "Stores explicitly sourced payroll facts for one organization member and salary month."

  use Ash.Resource,
    domain: Firmowid.Ash.Payroll,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Firmowid.Ash.Checks.ActorRole
  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Payroll.MemberPayrollInput.ImportFromDocument
  alias Firmowid.Ash.Payroll.Validations.MemberInOrganization
  alias Firmowid.Ash.Resource

  require Resource

  @facts [
    :payout_date,
    :payout_date_basis,
    :gross,
    :prior_taxable_income,
    :prior_social_base,
    :prior_exempt_income,
    :employer_ppk_income,
    :employer_ppk_date,
    :single_payment,
    :standard_pay,
    :insurance_unchanged,
    :source_blob_id
  ]

  postgres do
    table "member_payroll_inputs"
    repo Firmowid.Repo

    references do
      reference :member, on_delete: :delete
      reference :organization, on_delete: :delete
      reference :source_blob, on_delete: :nilify
    end
  end

  code_interface do
    define :create, action: :create
    define :update, action: :update
    define :read, action: :read
    define :list, action: :list
    define :import_from_document, action: :import_from_document, args: [:attributes]
  end

  actions do
    defaults [:read]

    create :create do
      description "Record explicit payroll facts for one member and salary month."
      primary? true
      accept [:member_id, :salary_month | @facts]
    end

    update :update do
      description "Correct sourced payroll facts without changing their member or month."
      primary? true
      accept @facts
      require_atomic? false
    end

    read :list do
      description """
      List monthly payroll facts with optional member and salary-month filters.
      """

      argument :member_id, :uuid
      argument :salary_month, :date

      prepare build(sort: [salary_month: :desc, member_id: :asc])

      prepare build(filter: expr(member_id == ^arg(:member_id))) do
        where present(:member_id)
      end

      prepare build(filter: expr(salary_month == ^arg(:salary_month))) do
        where present(:salary_month)
      end
    end

    action :import_from_document, :struct do
      description """
      Import known payroll facts from a source document, preserving prior values
      when incoming facts are absent or nil.
      """

      argument :attributes, :map, allow_nil?: false
      run ImportFromDocument
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {ActorRole, role: :admin}
      authorize_if expr(member_id == ^actor([:member, :id]))
      authorize_if {SystemActorRole, roles: [:document_blob_processor]}
    end

    policy action([:create, :update, :import_from_document]) do
      authorize_if {ActorRole, role: :admin}
      authorize_if {SystemActorRole, roles: [:document_blob_processor]}
    end
  end

  validations do
    validate fn changeset, _context ->
               case Ash.Changeset.get_attribute(changeset, :salary_month) do
                 %Date{day: 1} -> :ok
                 _ -> {:error, field: :salary_month, message: "is invalid"}
               end
             end,
             on: [:create]

    validate MemberInOrganization, on: [:create], where: [present(:member_id)]

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

    attribute :salary_month, :date do
      public? true
      allow_nil? false
      description "The first day of the month these facts describe."
    end

    attribute :payout_date, :date, public?: true

    attribute :payout_date_basis, :atom do
      public? true
      constraints one_of: [:planned, :actual]
    end

    attribute :gross, :decimal do
      public? true
      constraints min: 0, precision: 20, scale: 2
      description "Gross amount explicitly documented for this month, in PLN."
    end

    for field <- [
          :prior_taxable_income,
          :prior_social_base,
          :prior_exempt_income,
          :employer_ppk_income
        ] do
      attribute field, :decimal, public?: true, constraints: [min: 0, precision: 20, scale: 2]
    end

    attribute :employer_ppk_date, :date, public?: true

    for field <- [:single_payment, :standard_pay, :insurance_unchanged] do
      attribute field, :boolean, public?: true
    end

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
      description "The last document merged into these monthly facts; earlier files stay in the employee's documents."
      allow_nil? true
      attribute_writable? true
    end
  end

  identities do
    identity :unique_member_salary_month, [:organization_id, :member_id, :salary_month]
  end
end
