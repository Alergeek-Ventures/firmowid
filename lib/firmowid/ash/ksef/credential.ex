defmodule Firmowid.Ash.Ksef.Credential do
  @moduledoc """
  Ash resource for storing KSeF authentication credentials per organization.

  Credentials are stored encrypted and support token-based, uploaded-certificate,
  and Firmowid-generated certificate authentication methods.

  Table: `ksef_credentials` (already exists, `migrate?: false`).
  No multitenancy — queried by explicit `organization_id` filter, not tenant.
  Added to `@unscoped_tables` in Repo.
  """

  use Ash.Resource,
    domain: Firmowid.Ash.Ksef,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine],
    notifiers: [Ash.Notifier.PubSub]

  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Ksef.Calculations.CredentialExpiresOn
  alias Firmowid.Ash.Ksef.Validations.ValidateKsefToken
  alias Firmowid.Ash.Ksef.Validations.ValidateSignedAuthTokenRequest
  alias Firmowid.Ash.Ksef.Workers.CertificateEnrollmentWorker
  alias Firmowid.Ash.Ksef.Workers.SessionWorker

  postgres do
    table "ksef_credentials"
    repo Firmowid.Repo
  end

  state_machine do
    state_attribute :status
    initial_states [:authenticating, :authenticating_epuap]
    default_initial_state :authenticating

    transitions do
      transition :prepare_enrollment, from: :authenticating_epuap, to: :preparing_enrollment
      transition :wait_for_certificate, from: :preparing_enrollment, to: :wait_for_certificate

      transition :complete_certificate_enrollment,
        from: :wait_for_certificate,
        to: :authenticating

      transition :mark_working, from: [:authenticating, :working], to: :working
    end
  end

  code_interface do
    define :destroy
    define :prepare_enrollment
    define :wait_for_certificate
    define :complete_certificate_enrollment, args: [:credentials]
    define :mark_working
    define :delete_failed
    define :get, get?: true, not_found_error?: false
    define :get_internal, action: :internal, get?: true, not_found_error?: false
    define :all_organization_ids, action: :all_organization_ids
    define :authenticate_with_token, args: [:ksef_token]

    define :authenticate_with_uploaded_certificate,
      args: [:certificate, :private_key, :private_key_password]

    define :enroll_ksef_certificate, args: [:signed_auth_token_request, :challenge]
  end

  actions do
    # Default and lifecycle actions are internal; disconnect is exposed as Ksef.unauthenticate/1.
    defaults [:read, :destroy]

    update :prepare_enrollment do
      description "Mark generated-certificate enrollment as ready to submit a certificate request."
      require_atomic? false
      change transition_state(:preparing_enrollment)
    end

    update :wait_for_certificate do
      description "Mark generated-certificate enrollment as waiting for KSeF certificate issuance."
      require_atomic? false
      change transition_state(:wait_for_certificate)
    end

    update :complete_certificate_enrollment do
      description "Persist generated certificate material and mark the credential ready for KSeF authentication."
      primary? true
      require_atomic? false
      accept [:credentials]
      change transition_state(:authenticating)
    end

    update :mark_working do
      description "Mark a credential as connected and ready to use."
      require_atomic? false
      change transition_state(:working)
    end

    destroy :delete_failed do
      description "Delete a credential workflow after final authentication or enrollment failure."
    end

    read :get do
      description "Fetch the active KSeF credential for the current organization."
      get? true
      filter expr(organization_id == ^tenant() and status == :working)
      prepare build(load: [:expires_on])
    end

    read :internal do
      description "Fetch any internal KSeF credential for the current organization."
      get? true
      filter expr(organization_id == ^tenant())
      prepare build(load: [:expires_on])
    end

    read :all_organization_ids do
      description "List organization IDs that currently have stored KSeF credentials."
      filter expr(status == :working)
      prepare build(select: [:organization_id])
    end

    create :authenticate_with_token do
      description "Authenticate the organization with KSeF using a token."
      argument :ksef_token, :string, allow_nil?: false

      validate {ValidateKsefToken, []}

      change set_attribute(:auth_type, :token)
      change set_attribute(:organization_id, tenant())
      change set_attribute(:credentials, arg(:ksef_token))

      change after_action(fn changeset, credential, _context ->
               case SessionWorker.enqueue(credential.organization_id) do
                 {:ok, _job} -> {:ok, credential}
                 {:error, _reason} = error -> error
               end
             end)
    end

    create :authenticate_with_uploaded_certificate do
      description "Authenticate with an uploaded KSeF certificate."
      argument :certificate, :string, allow_nil?: false
      argument :private_key, :string, allow_nil?: false
      argument :private_key_password, :string, allow_nil?: true

      change set_attribute(:auth_type, :certificate)
      change set_attribute(:organization_id, tenant())

      change fn changeset, _context ->
        cert = Ash.Changeset.get_argument(changeset, :certificate)
        key = Ash.Changeset.get_argument(changeset, :private_key)
        password = Ash.Changeset.get_argument(changeset, :private_key_password)

        credentials =
          Jason.encode!(%{
            "certificate" => cert,
            "private_key" => key,
            "private_key_password" => password
          })

        Ash.Changeset.force_change_attribute(changeset, :credentials, credentials)
      end

      change after_action(fn changeset, credential, _context ->
               case SessionWorker.enqueue(credential.organization_id) do
                 {:ok, _job} -> {:ok, credential}
                 {:error, _reason} = error -> error
               end
             end)
    end

    create :enroll_ksef_certificate do
      description "Enqueue externally signed XAdES authentication and KSeF certificate enrollment."
      argument :signed_auth_token_request, :string, allow_nil?: false
      argument :challenge, :string, allow_nil?: false

      validate {ValidateSignedAuthTokenRequest, []}

      change set_attribute(:auth_type, :generated_certificate)
      change set_attribute(:status, :authenticating_epuap)
      change set_attribute(:organization_id, tenant())

      change after_action(fn changeset, credential, _context ->
               signed_xml = Ash.Changeset.get_argument(changeset, :signed_auth_token_request)
               org_id = credential.organization_id

               case CertificateEnrollmentWorker.enqueue(signed_xml, org_id) do
                 {:ok, _job} -> {:ok, credential}
                 {:error, _reason} = error -> error
               end
             end)
    end
  end

  policies do
    bypass actor_attribute_equals(:role, :admin) do
      authorize_if always()
    end

    # ksef_session: manage the current organization's credential
    bypass {SystemActorRole, roles: [:ksef_session]} do
      authorize_if action([
                     :destroy,
                     :prepare_enrollment,
                     :wait_for_certificate,
                     :complete_certificate_enrollment,
                     :mark_working,
                     :delete_failed,
                     :get,
                     :internal
                   ])
    end

    # cross_tenant_reader: enumerate org ids only
    bypass {SystemActorRole, roles: [:cross_tenant_reader]} do
      authorize_if action(:all_organization_ids)
    end

    # Other actors: no access
    policy always() do
      forbid_if always()
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "credential"

    publish :authenticate_with_token, ["authenticating", :organization_id]
    publish :authenticate_with_uploaded_certificate, ["authenticating", :organization_id]
    publish :enroll_ksef_certificate, ["authenticating_epuap", :organization_id]

    publish :prepare_enrollment, ["preparing_enrollment", :organization_id]
    publish :wait_for_certificate, ["wait_for_certificate", :organization_id]
    publish :complete_certificate_enrollment, ["authenticating", :organization_id]
    publish :mark_working, ["working", :organization_id]
    publish :delete_failed, ["failed", :organization_id]
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :status, :atom,
      constraints: [
        one_of: [
          :authenticating_epuap,
          :preparing_enrollment,
          :wait_for_certificate,
          :authenticating,
          :working
        ]
      ],
      default: :authenticating,
      allow_nil?: false,
      public?: false

    attribute :auth_type, :atom do
      constraints one_of: [:token, :certificate, :generated_certificate]
      allow_nil? false
      public? true
    end

    attribute :credentials, Firmowid.Ash.Ksef.EncryptedBinaryType do
      allow_nil? true
      sensitive? true
      public? false
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? false
      attribute_writable? true
    end
  end

  calculations do
    calculate :expires_on, :date, CredentialExpiresOn do
      public? true
    end
  end

  identities do
    identity :unique_organization, [:organization_id]
  end
end
