defmodule Firmowid.Ash.Core do
  @moduledoc """
  Core domain — identity and authentication.

  Owns the User, Organization, OrganizationInvite, Token, and UserIdentity resources.
  Authentication flows (password, Google OAuth, confirmation, password reset)
  are handled by `ash_authentication` on the User resource.

  Organization is fully writable with create, update, and destroy actions.
  OrganizationInvite handles invite creation, consumption, and expiry.
  """
  use Ash.Domain, extensions: [AshPhoenix]

  resources do
    resource Firmowid.Ash.Core.Organization do
      define :get_organization, action: :read, get_by: [:id]
      define :get_organization_by_nickname, action: :read, get_by: [:inbound_email_nickname]
      define :create_organization, action: :create
      define :update_organization, action: :update
      define :update_basic_info, action: :update_basic_info
      define :update_correspondence, action: :update_correspondence
      define :update_organization_avatar, action: :update_avatar
      define :add_sender_email, action: :add_sender_email
      define :remove_sender_email, action: :remove_sender_email
      define :regenerate_nickname, action: :regenerate_nickname
      define :destroy_organization, action: :destroy
    end

    resource Firmowid.Ash.Core.User do
      define :register_with_password, action: :register_with_password
      define :get_user, action: :read, get_by: [:id]
      define :get_user_by_email, action: :read, get_by: [:email]
      define :list_users, action: :list
      define :update_profile, action: :update_profile
      define :update_role, action: :update_role
      define :set_organization, action: :set_organization
      define :clear_organization, action: :clear_organization
      define :update_user_avatar, action: :update_avatar
      define :destroy_user, action: :destroy
      define :request_confirmation, action: :request_confirmation
      define :unlink_google_account, action: :unlink_google
      define :change_password, action: :change_password
    end

    resource Firmowid.Ash.Core.Token

    resource Firmowid.Ash.Core.UserIdentity

    resource Firmowid.Ash.Core.OrganizationInvite do
      define :list_invites, action: :read
      define :create_invite, action: :create
      define :get_invite, action: :read, get_by: [:id]
      define :read_invite_by_code, action: :read_by_code
      define :consume_invite, action: :consume
      define :destroy_invite, action: :destroy
    end
  end

  authorization do
    authorize :by_default
  end
end
