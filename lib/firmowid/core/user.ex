# credo:disable-for-this-file AshCredo.Check.Refactor.LargeResource
defmodule Firmowid.Core.User do
  @moduledoc """
  User resource — the sole owner of the `users` table.

  Handles authentication (password + Google OAuth) and organization
  membership; the person's name, avatar, role and profile details live on the
  organization `member`.
  No multitenancy — users sit above tenancy; the account may work in the
  organization of each of its active (non-archived) members, the session
  selects which one, and an account without one is in onboarding.

  Authentication is managed by `ash_authentication`:
  - Password strategy with Argon2 hashing
  - Google OAuth2 with `UserIdentity` for provider links
  - Token-based confirmation and password reset
  """
  use Ash.Resource,
    domain: Firmowid.Core,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication],
    notifiers: [Ash.Notifier.PubSub]

  use Gettext, backend: Firmowid.Gettext

  alias AshAuthentication.Strategy.Password.PasswordValidation
  alias Firmowid.Checks.OrganizationMemberAdmin
  alias Firmowid.Checks.SystemActorRole
  alias Firmowid.Core.Changes.CaptureGoogleRegistration
  alias Firmowid.Core.Member
  alias Firmowid.Core.Secrets
  alias Firmowid.Core.Services.GoogleAvatarImporter
  alias Firmowid.Core.User.Actions.UpdateCurrentProfile
  alias Firmowid.Core.User.Changes.RevokeAuthentication
  alias Firmowid.Core.UserIdentity
  alias Firmowid.Core.UserRole
  alias Firmowid.Resource

  require Ash.Query
  require Resource

  postgres do
    table "users"
    repo Firmowid.Repo
  end

  authentication do
    tokens do
      enabled? true
      token_resource Firmowid.Core.Token
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
          sender Firmowid.Core.Senders.PasswordResetSender
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
        # Monitor email changes. The Google action also checks the returned account:
        # skipped upserts can bypass the confirmation add-on's conflict filter.
        monitor_fields [:email]

        # Google OAuth users are already verified by Google — skip the confirmation
        # flow and set confirmed_at immediately on registration.
        auto_confirm_actions [:register_with_google]

        # Keep the existing address until the new owner confirms the change.
        confirm_on_update? true

        # Required since GHSA-3988-q8q7-p787: prevents email clients / security
        # scanners from auto-confirming accounts by pre-fetching confirmation links.
        require_interaction? true

        sender Firmowid.Core.Senders.ConfirmationSender
      end
    end
  end

  code_interface do
    define :get, action: :read, get_by: [:id]
    define :destroy, action: :destroy
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
        constraints one_of: UserRole.roles()
      end

      prepare fn query, _context ->
        tenant = query.tenant || raise "User :list action requires a tenant (organization_id)"
        Ash.Query.filter(query, exists(member, organization_id == ^tenant))
      end

      prepare build(
                filter:
                  expr(
                    contains(member.name, ^arg(:search)) or
                      contains(email, ^arg(:search))
                  )
              ) do
        where present(:search)
      end

      prepare build(filter: expr(is_nil(member.archived_at))) do
        where argument_equals(:status, :active)
      end

      prepare build(filter: expr(not is_nil(member.archived_at))) do
        where argument_equals(:status, :archived)
      end

      prepare build(filter: expr(member.role == ^arg(:role))) do
        where present(:role)
      end
    end

    read :get_org_user do
      description "Fetch a single user scoped to the current organization tenant."
      get_by [:id]

      prepare fn query, _context ->
        tenant =
          query.tenant || raise "User :get_org_user action requires a tenant (organization_id)"

        Ash.Query.filter(query, exists(member, organization_id == ^tenant))
      end
    end

    # ── Auth actions (auto-generated by ash_authentication) ─────────
    # :register_with_password,
    # :request_password_reset_with_password, :password_reset_with_password
    # are generated automatically by the password strategy.

    # Read-based sign-ins keep the user locked through the token-writing hooks,
    # so archival cannot revoke sessions before a concurrent sign-in saves one.
    read :sign_in_with_password do
      description "Sign in with a password while serializing token issuance with archival."
      get? true
      transaction? true

      argument :email, :ci_string, allow_nil?: false
      argument :password, :string, allow_nil?: false, sensitive?: true

      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string, allow_nil?: false
    end

    read :sign_in_with_token do
      description "Exchange a sign-in token while serializing session issuance with archival."
      get? true
      transaction? true

      argument :token, :string, allow_nil?: false, sensitive?: true

      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string, allow_nil?: false
    end

    read :sign_in_with_remember_me do
      description "Restore a remembered session while serializing token issuance with archival."
      get? true
      transaction? true

      argument :token, :string, allow_nil?: false, sensitive?: true

      prepare AshAuthentication.Strategy.RememberMe.SignInPreparation

      metadata :token, :string, allow_nil?: false
    end

    # ── Google OAuth action ─────────────────────────────────────────
    create :register_with_google do
      description "Register or sign in a user through the Google OAuth strategy."
      primary? true
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false, sensitive?: true
      upsert? true
      upsert_identity :unique_email
      upsert_fields []
      # Existing Google identities and verified-email links must not count as new accounts.
      # A skipped conflict carries Ash's :upsert_skipped metadata on the returned user.
      upsert_condition expr(false)
      return_skipped_upsert? true

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
              message: gettext("Google sign-in failed: no email address.")
            )

          verified_email not in [true, "true", 1, "1"] ->
            Ash.Changeset.add_error(changeset,
              message: gettext("Google sign-in failed: the Google email is not verified.")
            )

          true ->
            Ash.Changeset.change_attributes(changeset, Map.take(user_info, ["email"]))
        end
      end

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn changeset, user ->
          # Check the persisted result before token issuance or identity linking,
          # independently of upsert filters (the conflict may have been skipped).
          if is_nil(user.confirmed_at) do
            {:error,
             AshAuthentication.Errors.CannotConfirmUnconfirmedUser.exception(
               resource: __MODULE__,
               confirmation_strategy: :confirm
             )}
          else
            user_info = Ash.Changeset.get_argument(changeset, :user_info)
            GoogleAvatarImporter.maybe_import(user, user_info)
          end
        end)
      end

      change AshAuthentication.GenerateTokenChange
      change AshAuthentication.Strategy.OAuth2.IdentityChange
      change CaptureGoogleRegistration
    end

    # ── Profile management ──────────────────────────────────────────
    update :change_email do
      description "Request a change to the current user's email address."
      primary? true
      accept [:email]
      require_atomic? false
      argument :current_password, :string, sensitive?: true

      # A session alone must not move the account to an address its holder controls.
      validate {PasswordValidation, strategy_name: :password, password_argument: :current_password},
        where: [attribute_does_not_equal(:hashed_password, nil)]
    end

    update :set_locale do
      description "Set the language of the current user's interface."
      accept [:locale]
    end

    update :record_sign_in do
      description "Record that the account was just signed in."
      accept []
      change set_attribute(:last_signed_in_at, &DateTime.utc_now/0)
    end

    action :update_current_profile, :struct do
      description "Update the acting user's member: name and profile details."
      transaction? true

      constraints instance_of: __MODULE__

      argument :name, :string
      argument :phone, :string
      argument :slack_url, :string
      argument :bank_account_number, :string
      argument :birthday, :date

      argument :birthday_visibility, :atom do
        constraints one_of: [:not_shared, :day_with_month, :full_date]
      end

      argument :correspondence_address, :string
      argument :residence_address, :string
      argument :is_same_correspondence_address, :boolean

      run &UpdateCurrentProfile.run/2
    end

    action :get_shared_birthday, :string do
      description "Returns the authenticated user's shared birthday (nil if not shared)."

      run fn _input, context ->
        member = Ash.load!(context.actor.member, :shared_birthday, Ash.Context.to_opts(context))
        {:ok, member.shared_birthday}
      end
    end

    update :set_organization do
      description "Assign a user to an organization."
      accept []
      require_atomic? false
      argument :organization_id, :uuid, allow_nil?: false

      argument :role, :atom do
        allow_nil? false
        constraints one_of: UserRole.roles()
      end

      argument :name, :string

      # The organization becomes the changeset's tenant, which the `joined_org`
      # topic is published under.
      change fn changeset, _context ->
        Ash.Changeset.set_tenant(
          changeset,
          Ash.Changeset.get_argument(changeset, :organization_id)
        )
      end

      change after_action(fn changeset, user, context ->
               opts = Ash.Context.to_opts(context, tenant: changeset.to_tenant)

               attributes = %{
                 user_id: user.id,
                 role: Ash.Changeset.get_argument(changeset, :role),
                 name: Ash.Changeset.get_argument(changeset, :name)
               }

               # Restoring an archived membership keeps its name unless a new one is given.
               upsert_fields =
                 if attributes.name, do: [:role, :name, :archived_at], else: [:role, :archived_at]

               with {:ok, _member} <-
                      Member.create(attributes, Keyword.put(opts, :upsert_fields, upsert_fields)) do
                 {:ok, user}
               end
             end)
    end

    update :leave_organization do
      description "Revoke the account's OAuth grants for the organization its member was archived from."
      accept []
      require_atomic? false
      argument :organization_id, :uuid, allow_nil?: false

      # Serializes with OAuth issuance, which locks the account row (see
      # `RequireActiveOauthUser`), so no grant outlives the archival.
      change get_and_lock_for_update()
      change RevokeAuthentication
    end

    destroy :destroy do
      description "Delete a user record after callsite-level verification."
      # The domain function verifies the password before invoking this action.
      require_atomic? false

      change get_and_lock_for_update()
      change RevokeAuthentication
    end

    update :change_password do
      description "Change a user's password after verifying the current password."
      accept []
      require_atomic? false
      argument :current_password, :string, sensitive?: true, allow_nil?: false
      argument :password, :string, sensitive?: true, allow_nil?: false
      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {PasswordValidation, strategy_name: :password, password_argument: :current_password}

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
            Ash.Changeset.add_error(changeset,
              message: gettext("The Google account is not connected.")
            )

          identity ->
            case Ash.destroy(identity, ash_opts) do
              :ok ->
                changeset

              {:error, _error} ->
                Ash.Changeset.add_error(changeset,
                  message: gettext("Could not disconnect the Google account.")
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
      authorize_if action(:set_organization)
      authorize_if expr(id == ^actor(:user_id))
    end

    # Default :read action — used for loading the current user and explicit admin access.
    # bypass so it short-circuits the deny catch-all below.
    bypass action(:read) do
      authorize_if expr(id == ^actor(:id))
      authorize_if OrganizationMemberAdmin
      authorize_if actor_attribute_equals(:system_role, :superuser)

      authorize_if {SystemActorRole,
                    roles: [
                      :leave_notifier,
                      :hours_record_change_notifier,
                      :document_blob_processor,
                      :employment_contract_notifier
                    ]}
    end

    # :list action — admin-only user listing, plus system actors that need
    # organization-wide factual user counts.
    bypass action(:list) do
      authorize_if OrganizationMemberAdmin
      authorize_if actor_attribute_equals(:system_role, :superuser)

      authorize_if {SystemActorRole,
                    roles: [
                      :ksef_digest,
                      :billing_snapshotter,
                      :leave_notifier,
                      :hours_record_change_notifier,
                      :employment_contract_notifier
                    ]}
    end

    # :get_org_user — admin-only, tenant-scoped user lookup
    bypass action(:get_org_user) do
      authorize_if OrganizationMemberAdmin
      authorize_if actor_attribute_equals(:system_role, :superuser)
    end

    bypass action(:change_email) do
      authorize_if expr(id == ^actor(:id))
    end

    policy action(:update_current_profile) do
      authorize_if actor_present()
    end

    policy action(:get_shared_birthday) do
      authorize_if actor_present()
    end

    # Runs after the member is archived, so the account is matched by its membership.
    policy action(:leave_organization) do
      authorize_if OrganizationMemberAdmin
    end

    policy action(:set_organization) do
      forbid_if always()
    end

    bypass action(:unlink_google) do
      authorize_if expr(id == ^actor(:id))
    end

    bypass action(:change_password) do
      authorize_if expr(id == ^actor(:id))
    end

    bypass [{SystemActorRole, roles: [:sign_in_recorder]}, action(:record_sign_in)] do
      authorize_if expr(id == ^actor(:user_id))
    end

    bypass action(:set_locale) do
      authorize_if expr(id == ^actor(:id))
    end

    bypass action_type(:destroy) do
      authorize_if expr(id == ^actor(:id))
      authorize_if {OrganizationMemberAdmin, active: true}
    end
  end

  pub_sub do
    module FirmowidWeb.Core.Endpoint
    prefix "user"

    # Used by admin employee list LiveView to refresh immediately after
    # invite consumption assigns a user to an organization.
    publish :set_organization, ["joined_org", :_tenant]
  end

  preparations do
    prepare Firmowid.Core.User.Preparations.RequireActiveAccount
  end

  changes do
    change Firmowid.Core.User.Changes.RevokeAuthenticationOnPasswordChange, on: [:update]
  end

  attributes do
    uuid_v7_primary_key :id

    # ── Auth fields ─────────────────────────────────────────────────
    attribute :email, :ci_string, public?: true, allow_nil?: false
    attribute :hashed_password, :string, sensitive?: true

    attribute :confirmed_at, :utc_datetime, public?: true

    # Set when a session is issued to the account itself (see `Token`); support
    # impersonation does not count.
    attribute :last_signed_in_at, :utc_datetime, public?: true

    attribute :system_role, :atom,
      public?: true,
      constraints: [one_of: [:user, :superuser]],
      default: :user

    # The interface language the user chose; nil until they choose one.
    attribute :locale, :atom, public?: true, constraints: [one_of: [:pl, :en, :uk]]

    Resource.firmowid_timestamps()
  end

  relationships do
    has_one :member, Member do
      public? true
      destination_attribute :user_id
    end
  end

  calculations do
    # Why the account may not use the application: none of the organizations of its
    # active members has a billing plan. The owner of one is told to renew the
    # subscription; members are not.
    #
    # Until subscription lifecycle moves into application data (it is managed outside
    # the app before Stripe), `:no_plan` deliberately serves both as the zero-plan
    # catalog entry and as the signal that organization access is blocked.
    calculate :access_block,
              :atom,
              expr(
                cond do
                  system_role == :superuser ->
                    nil

                  not exists(member, is_nil(archived_at)) ->
                    nil

                  exists(member, is_nil(archived_at) and organization.billing_plan != :no_plan) ->
                    nil

                  exists(member, is_nil(archived_at) and organization.owner_id == parent(id)) ->
                    :subscription_expired

                  true ->
                    :account_disabled
                end
              ) do
      constraints one_of: [:account_disabled, :subscription_expired]
    end
  end

  identities do
    identity :unique_email, [:email]
  end

  # Use a dedicated validation module placed next to the resource file.
  # See lib/firmowid/core/validations/not_self_archive.ex
end
