# credo:disable-for-this-file AshCredo.Check.Refactor.LargeResource
defmodule Firmowid.Ash.Core.User do
  @moduledoc """
  User resource — the sole owner of the `users` table.

  Handles authentication (password + Google OAuth), profile management,
  role assignment, and organization membership. No multitenancy — users
  sit above tenancy; `organization_id` is nullable (onboarding state).

  Authentication is managed by `ash_authentication`:
  - Password strategy with Argon2 hashing
  - Google OAuth2 with `UserIdentity` for provider links
  - Token-based confirmation and password reset
  """
  use Ash.Resource,
    domain: Firmowid.Ash.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication],
    notifiers: [Ash.Notifier.PubSub]

  alias Firmowid.Ash.Checks.SystemActorRole
  alias Firmowid.Ash.Core.Calculations.AcceptedLeaveDaysForYear
  alias Firmowid.Ash.Core.Secrets
  alias Firmowid.Ash.Core.Services.GoogleAvatarImporter
  alias Firmowid.Ash.Core.User.Actions.UpdateCurrentProfile
  alias Firmowid.Ash.Core.UserIdentity
  alias Firmowid.Ash.Resource

  require Resource

  postgres do
    table "users"
    repo Firmowid.Repo
  end

  authentication do
    tokens do
      enabled? true
      token_resource Firmowid.Ash.Core.Token
      signing_secret Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      password :password do
        identity_field :email
        hashed_password_field :hashed_password
        hash_provider AshAuthentication.Argon2Provider
        confirmation_required? false

        resettable do
          sender Firmowid.Ash.Core.Senders.PasswordResetSender
        end
      end

      google do
        client_id Secrets
        client_secret Secrets
        redirect_uri Secrets
        identity_resource UserIdentity
      end

      remember_me :remember_me do
        token_lifetime {30, :days}
      end
    end

    add_ons do
      confirmation :confirm do
        # Monitor email changes — this is what satisfies prevent_hijacking? on the
        # google strategy. At runtime it blocks upsert-via-Google over unconfirmed
        # password accounts (CannotConfirmUnconfirmedUser error).
        monitor_fields [:email]

        # Google OAuth users are already verified by Google — skip the confirmation
        # flow and set confirmed_at immediately on registration.
        auto_confirm_actions [:register_with_google]

        # Keep the existing address until the new owner confirms the change.
        confirm_on_update? true

        # Required since GHSA-3988-q8q7-p787: prevents email clients / security
        # scanners from auto-confirming accounts by pre-fetching confirmation links.
        require_interaction? true

        sender Firmowid.Ash.Core.Senders.ConfirmationSender
      end

      log_out_everywhere do
        # Revoke all active tokens when password is changed, forcing re-login
        # on all other devices/sessions. Requires store_all_tokens? true and
        # require_token_presence_for_authentication? true (both set above).
        apply_on_password_change? true
      end
    end
  end

  code_interface do
    define :destroy, action: :destroy
    define :log_out_everywhere, action: :log_out_everywhere
    define :confirm, action: :confirm
    define :sign_in_with_remember_me, action: :sign_in_with_remember_me
    define :password_reset_with_password, action: :password_reset_with_password
    define :request_password_reset_with_password, action: :request_password_reset_with_password
    define :sign_in_with_token, action: :sign_in_with_token
    define :sign_in_with_password, action: :sign_in_with_password
    define :get_by_subject, action: :get_by_subject
    define :get_by_email, action: :get_by_email
    define :register_with_google, action: :register_with_google, args: [:user_info, :oauth_tokens]
  end

  actions do
    defaults [:read]

    read :list do
      description "List organization users with search, status, and role filters."
      argument :search, :string

      argument :status, :atom do
        constraints one_of: [:active, :archived]
      end

      argument :role, :atom do
        constraints one_of: [:employee, :invoicing, :accountant, :admin]
      end

      prepare fn query, _context ->
        tenant = query.tenant || raise "User :list action requires a tenant (organization_id)"
        Ash.Query.do_filter(query, organization_id: tenant)
      end

      prepare build(
                filter:
                  expr(
                    contains(name, ^arg(:search)) or
                      contains(email, ^arg(:search))
                  )
              ) do
        where present(:search)
      end

      prepare build(filter: expr(is_nil(archived_at))) do
        where argument_equals(:status, :active)
      end

      prepare build(filter: expr(not is_nil(archived_at))) do
        where argument_equals(:status, :archived)
      end

      prepare build(filter: expr(role == ^arg(:role))) do
        where present(:role)
      end
    end

    read :get_org_user do
      description "Fetch a single user scoped to the current organization tenant."
      get_by [:id]

      prepare fn query, _context ->
        tenant =
          query.tenant || raise "User :get_org_user action requires a tenant (organization_id)"

        Ash.Query.do_filter(query, organization_id: tenant)
      end
    end

    # ── Auth actions (auto-generated by ash_authentication) ─────────
    # :register_with_password, :sign_in_with_password,
    # :request_password_reset_with_password, :password_reset_with_password
    # are generated automatically by the password strategy.

    # ── Google OAuth action ─────────────────────────────────────────
    create :register_with_google do
      description "Register or sign in a user through the Google OAuth strategy."
      primary? true
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false
      upsert? true
      upsert_identity :unique_email
      upsert_fields []

      # Canonical policy: auto-link only for provider-verified emails.
      # TODO: Make verified-email auto-linking configurable per organization
      # (opt-in policy) once org-level auth settings are introduced.

      change fn changeset, _ ->
        user_info = Ash.Changeset.get_argument(changeset, :user_info)
        email = Map.get(user_info, "email")

        verified_email =
          Map.get(user_info, "verified_email") || Map.get(user_info, "email_verified")

        cond do
          not is_binary(email) or email == "" ->
            Ash.Changeset.add_error(changeset,
              message: "Logowanie Google nie powiodło się: brak adresu email."
            )

          verified_email not in [true, "true", 1, "1"] ->
            Ash.Changeset.add_error(changeset,
              message: "Logowanie Google nie powiodło się: email Google nie jest zweryfikowany."
            )

          true ->
            Ash.Changeset.change_attributes(changeset, Map.take(user_info, ["email", "name"]))
        end
      end

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn changeset, user ->
          user_info = Ash.Changeset.get_argument(changeset, :user_info)

          GoogleAvatarImporter.maybe_import(user, user_info)
        end)
      end

      change AshAuthentication.GenerateTokenChange
      change AshAuthentication.Strategy.OAuth2.IdentityChange
    end

    # ── Profile management ──────────────────────────────────────────
    update :update_profile do
      description "Update the current user's profile fields."
      primary? true
      require_atomic? false

      accept [
        :name,
        :employment_date,
        :avatar_blob_id,
        :phone,
        :slack_url,
        :slack_id,
        :bank_account_number,
        :birthday,
        :position,
        :correspondence_street,
        :correspondence_city,
        :correspondence_code,
        :residence_street,
        :residence_city,
        :residence_code
      ]

      validate present(:name), where: [changing(:name)]

      change update_change(:bank_account_number, fn
               nil ->
                 nil

               value ->
                 case String.trim(value) do
                   "" -> nil
                   trimmed -> trimmed
                 end
             end),
             where: [changing(:bank_account_number)]
    end

    update :change_email do
      description "Request a change to the current user's email address."
      accept [:email]
      require_atomic? false
    end

    action :update_current_profile, :struct do
      description "Update profile fields for the acting user."

      constraints instance_of: __MODULE__

      argument :name, :string
      argument :employment_date, :date
      argument :phone, :string
      argument :slack_id, :string
      argument :bank_account_number, :string
      argument :position, :string
      argument :correspondence_street, :string
      argument :correspondence_city, :string
      argument :correspondence_code, :string
      argument :residence_street, :string
      argument :residence_city, :string
      argument :residence_code, :string

      run &UpdateCurrentProfile.run/2
    end

    update :update_role do
      description "Update a user's organization role."
      accept [:role]
    end

    update :set_organization do
      description "Assign a user to an organization."
      accept []
      argument :organization_id, :uuid, allow_nil?: false
      change set_attribute(:organization_id, arg(:organization_id))
    end

    update :clear_organization do
      description "Remove a user from their current organization."
      accept []
      change set_attribute(:organization_id, nil)
    end

    update :archive do
      description "Archive a user without deleting their record."
      accept []

      validate {Firmowid.Ash.Core.Validations.NotSelfArchive, []}

      change set_attribute(:archived_at, &Date.utc_today/0)
    end

    update :unarchive do
      description "Restore an archived user."
      accept []

      change set_attribute(:archived_at, nil)
    end

    update :update_avatar do
      description "Replace the user's avatar blob and clean up the previous one."
      accept [:avatar_blob_id]
      require_atomic? false

      change Firmowid.Ash.Core.Changes.CleanupOldAvatarBlob
    end

    destroy :destroy do
      description "Delete a user record after callsite-level verification."
      # Password verification is handled at the callsite (domain function)
      # before invoking this action, matching the existing pattern.
      require_atomic? false
    end

    update :change_password do
      description "Change a user's password after verifying the current password."
      accept []
      require_atomic? false
      argument :current_password, :string, sensitive?: true, allow_nil?: false
      argument :password, :string, sensitive?: true, allow_nil?: false
      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    update :unlink_google do
      description "Remove the linked Google identity from a user account."
      accept []
      require_atomic? false

      change fn changeset, context ->
        user_id = changeset.data.id
        ash_opts = [actor: context.actor]

        # Find and destroy the Google UserIdentity
        identity =
          UserIdentity
          |> Ash.read!(ash_opts)
          |> Enum.find(&(&1.user_id == user_id and &1.strategy == "google"))

        case identity do
          nil ->
            Ash.Changeset.add_error(changeset, message: "Konto Google nie jest połączone.")

          identity ->
            case Ash.destroy(identity, ash_opts) do
              :ok ->
                changeset

              {:error, _error} ->
                Ash.Changeset.add_error(changeset,
                  message: "Nie udało się odłączyć konta Google."
                )
            end
        end
      end
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    bypass {SystemActorRole, roles: [:organization_owner_setup]} do
      authorize_if action([:set_organization, :update_role])
      authorize_if expr(id == ^actor(:user_id))
    end

    # Default :read action — used for loading the current user and explicit admin access.
    # bypass so it short-circuits the deny catch-all below.
    bypass action(:read) do
      authorize_if expr(id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:system_role, :superuser)
      authorize_if {SystemActorRole, roles: [:leave_notifier]}
    end

    # :list action — admin-only user listing, plus system actors that need
    # organization-wide factual user counts.
    bypass action(:list) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:system_role, :superuser)
      authorize_if {SystemActorRole, roles: [:ksef_digest, :billing_snapshotter, :leave_notifier]}
    end

    # :get_org_user — admin-only, tenant-scoped user lookup
    bypass action(:get_org_user) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if actor_attribute_equals(:system_role, :superuser)
    end

    bypass action(:update_profile) do
      authorize_if actor_attribute_equals(:role, :admin)
      authorize_if expr(id == ^actor(:id))
    end

    bypass action(:change_email) do
      authorize_if expr(id == ^actor(:id))
    end

    policy action(:update_current_profile) do
      authorize_if actor_present()
    end

    bypass action(:update_avatar) do
      authorize_if expr(id == ^actor(:id))
    end

    bypass action(:update_role) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    bypass action(:archive) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    bypass action(:unarchive) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    bypass action(:set_organization) do
      authorize_if expr(id == ^actor(:id))
    end

    bypass action(:clear_organization) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    bypass action(:unlink_google) do
      authorize_if expr(id == ^actor(:id))
    end

    bypass action(:change_password) do
      authorize_if expr(id == ^actor(:id))
    end

    bypass action_type(:destroy) do
      authorize_if expr(id == ^actor(:id))
      authorize_if actor_attribute_equals(:role, :admin)
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "user"

    # Used by admin employee list LiveView to refresh immediately after
    # invite consumption assigns a user to an organization.
    publish :set_organization, ["joined_org", :organization_id]
  end

  attributes do
    uuid_v7_primary_key :id

    # ── Auth fields ─────────────────────────────────────────────────
    attribute :email, :ci_string, public?: true, allow_nil?: false
    attribute :hashed_password, :string, sensitive?: true

    attribute :confirmed_at, :utc_datetime, public?: true

    # ── Profile / HR fields ─────────────────────────────────────────
    attribute :name, :string, public?: true

    attribute :role, :atom,
      public?: true,
      constraints: [one_of: [:employee, :invoicing, :accountant, :admin]],
      default: :employee

    attribute :system_role, :atom,
      public?: true,
      constraints: [one_of: [:user, :superuser]],
      default: :user

    attribute :employment_date, :date, public?: true
    attribute :archived_at, :date, public?: true
    attribute :avatar_blob_id, :uuid, public?: true

    attribute :phone, :string, public?: true
    attribute :slack_url, :string, public?: true
    attribute :slack_id, :string, public?: true
    attribute :bank_account_number, :string, public?: true
    attribute :birthday, :date, public?: true
    attribute :position, :string, public?: true

    attribute :correspondence_street, :string, public?: true
    attribute :correspondence_city, :string, public?: true
    attribute :correspondence_code, :string, public?: true
    attribute :residence_street, :string, public?: true
    attribute :residence_city, :string, public?: true
    attribute :residence_code, :string, public?: true

    Resource.firmowid_timestamps()
  end

  relationships do
    belongs_to :organization, Firmowid.Ash.Core.Organization do
      allow_nil? true
      attribute_writable? true
    end

    belongs_to :avatar_blob, Firmowid.Ash.Blobs.Blob do
      allow_nil? true
      attribute_writable? true
      define_attribute? false
      source_attribute :avatar_blob_id
    end

    has_many :leave_requests, Firmowid.Ash.Timetracker.LeaveRequest
  end

  calculations do
    calculate :accepted_leave_days_for_year,
              :integer,
              {AcceptedLeaveDaysForYear, []} do
      public? true
      argument :year, :integer, allow_nil?: false
    end
  end

  identities do
    identity :unique_email, [:email]
  end

  # Use a dedicated validation module placed next to the resource file.
  # See lib/firmowid/ash/core/validations/not_self_archive.ex
end
