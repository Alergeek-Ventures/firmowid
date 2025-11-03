defmodule Firmowid.Accounts do
  @moduledoc """
  The Accounts context.
  """

  @behaviour Bodyguard.Policy

  import Ecto.Query, warn: false

  alias Firmowid.Accounts.Organization
  alias Firmowid.Accounts.OrganizationInvites
  alias Firmowid.Accounts.User
  alias Firmowid.Accounts.UserNotifier
  alias Firmowid.Accounts.UserToken
  alias Firmowid.Blobs
  alias Firmowid.Repo

  def authorize(:create_organization_invite, %{role: :admin}, _), do: true
  def authorize(:read_organization_invites, %{role: :admin}, _), do: true
  def authorize(:delete_organization_invite, %{role: :admin}, _), do: true

  def authorize(:update_organization, %{role: :admin, organization_id: org_id}, %Organization{id: org_id}), do: true

  def authorize(_, _, _), do: false

  def list_organizations do
    Repo.all(Organization, skip_organization_id: true)
  end

  @doc """
  Gets a single organization by ID.

  Returns `{:ok, %Organization{}}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_organization("123e4567-e89b-12d3-a456-426614174000")
      {:ok, %Organization{}}

      iex> get_organization("invalid-uuid")
      {:error, :not_found}

  """
  def get_organization(id) do
    case Repo.get(Organization, id, skip_organization_id: true) do
      nil -> {:error, :not_found}
      org -> {:ok, org}
    end
  end

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, [email: email], skip_organization_id: true)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, [email: email], skip_organization_id: true)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id, skip_organization_id: true)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query, skip_organization_id: true),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset, skip_organization_id: true)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, [context]),
      skip_organization_id: true
    )
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/ustawienia/uzytkownik/potwierdz/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset, skip_organization_id: true)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, :all),
      skip_organization_id: true
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token, skip_organization_id: true)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)

    query
    |> Repo.one(skip_organization_id: true)
    |> Repo.preload(:organization, skip_organization_id: true)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"),
      skip_organization_id: true
    )

    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/potwierdz/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/potwierdz/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token, skip_organization_id: true)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query, skip_organization_id: true),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user), skip_organization_id: true)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, ["confirm"]),
      skip_organization_id: true
    )
  end

  ## Reset password

  @doc ~S"""
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &url(~p"/resetuj-haslo/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token, skip_organization_id: true)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query, skip_organization_id: true) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs), skip_organization_id: true)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, :all),
      skip_organization_id: true
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Creates an organization with the given attributes and sets the owner.

  ## Examples

      iex> create_organization(%{field: value}, owner)
      {:ok, %Organization{}}

      iex> create_organization(%{field: bad_value}, owner)
      {:error, %Ecto.Changeset{}}

  """
  def create_organization(attrs \\ %{}, owner) do
    # Generate unique nickname with retry logic
    organization = create_organization_with_nickname(attrs, owner, 10)

    owner
    |> User.organization_changeset(%{organization_id: organization.id})
    |> Repo.update!()
    |> update_user(%{role: :admin})

    {:ok, organization}
  end

  defp create_organization_with_nickname(_attrs, _owner, 0) do
    raise "Failed to create organization with unique nickname after 10 attempts"
  end

  defp create_organization_with_nickname(attrs, owner, attempts_left) do
    nickname = HumanIDs.generate()

    try do
      %Organization{}
      |> Organization.changeset(
        attrs
        |> Map.put("owner_id", owner.id)
        |> Map.put("allowed_sender_emails", [owner.email])
        |> Map.put("inbound_email_nickname", nickname)
      )
      |> Repo.insert!(skip_organization_id: true)
    rescue
      Ecto.ConstraintError ->
        # Nickname collision, retry with new nickname
        create_organization_with_nickname(attrs, owner, attempts_left - 1)
    end
  end

  @doc """
  Deletes an organization.

  ## Examples

      iex> delete_organization(organization)
      {:ok, %Organization{}}

      iex> delete_organization(organization)
      {:error, %Ecto.Changeset{}}

  """
  def delete_organization(organization_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.update_all(
      :update_users,
      from(u in User, where: u.organization_id == ^organization_id),
      [set: [organization_id: nil]],
      skip_organization_id: true
    )
    |> Ecto.Multi.delete(
      :delete_org,
      Repo.get!(Organization, organization_id, skip_organization_id: true)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{delete_org: org}} -> {:ok, org}
      {:error, _operation, value, _changes} -> {:error, value}
    end
  end

  @doc """
  Updates an organization with the given attributes.

  ## Examples

      iex> update_organization(organization, %{field: new_value})
      {:ok, %Organization{}}

      iex> update_organization(organization, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_organization(%Organization{} = organization, attrs) do
    organization
    |> Organization.changeset(attrs)
    |> Repo.update(skip_organization_id: true)
  end

  def update_organization_avatar(%Organization{} = organization, blob_id) do
    {:ok, result} =
      Repo.transaction(fn ->
        {:ok, new_org} = update_organization(organization, %{avatar_blob_id: blob_id})

        if organization.avatar_blob_id do
          Blobs.delete_blob(organization.avatar_blob_id)
        end

        {:ok, new_org}
      end)

    result
  end

  def get_organization_with_avatar(%Organization{} = organization) do
    avatar_url =
      case organization.avatar_blob_id do
        nil -> nil
        id -> Blobs.get_blob_url(id)
      end

    Map.put(organization, :avatar_url, avatar_url)
  end

  @doc """
  Adds an email to the organization's allowed sender list if not already present.

  ## Examples

      iex> add_email_to_org_allowlist(org_id, "user@example.com")
      {:ok, %Organization{}}

  """
  def add_email_to_org_allowlist(org_id, email) when is_binary(email) do
    org = Repo.get!(Organization, org_id, skip_organization_id: true)

    updated_emails =
      if email in org.allowed_sender_emails do
        org.allowed_sender_emails
      else
        org.allowed_sender_emails ++ [email]
      end

    org
    |> Ecto.Changeset.change(allowed_sender_emails: updated_emails)
    |> Repo.update(skip_organization_id: true)
  end

  @doc """
  Removes an email from the organization's allowed sender list.

  ## Examples

      iex> remove_email_from_org_allowlist(org_id, "user@example.com")
      {:ok, %Organization{}}

  """
  def remove_email_from_org_allowlist(org_id, email) when is_binary(email) do
    org = Repo.get!(Organization, org_id, skip_organization_id: true)

    updated_emails = Enum.reject(org.allowed_sender_emails, &(&1 == email))

    org
    |> Ecto.Changeset.change(allowed_sender_emails: updated_emails)
    |> Repo.update(skip_organization_id: true)
  end

  @doc """
  Returns the list of organization_invites.

  ## Examples

      iex> list_organization_invites()
      [%OrganizationInvites{}, ...]

  """
  def list_organization_invites(organization_id) do
    OrganizationInvites
    |> Repo.all(organization_id: organization_id)
    |> Repo.preload(:issued_by, organization_id: organization_id)
    |> Repo.preload(:consumed_by, organization_id: organization_id)
  end

  @doc """
  Gets a single organization_invites.

  Raises `Ecto.NoResultsError` if the Organization invites does not exist.

  ## Examples

      iex> get_organization_invites!(123)
      %OrganizationInvites{}

      iex> get_organization_invites!(456)
      ** (Ecto.NoResultsError)

  """
  def get_organization_invites!(id, organization_id),
    do: Repo.get!(OrganizationInvites, id, organization_id: organization_id)

  @doc """
  Creates a organization_invites.

  ## Examples

      iex> create_organization_invites(%{field: value})
      {:ok, %OrganizationInvites{}}

      iex> create_organization_invites(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_organization_invites(organization_id, issued_by_id) do
    random_code = 20 |> :crypto.strong_rand_bytes() |> Base.url_encode64()

    %OrganizationInvites{}
    |> OrganizationInvites.changeset(%{
      issued_by_id: issued_by_id,
      organization_id: organization_id,
      invite_code: random_code,
      expires_at: DateTime.add(DateTime.utc_now(), 7, :day)
    })
    |> Repo.insert(organization_id: organization_id)
  end

  @doc """
  Updates a organization_invites.

  ## Examples

      iex> update_organization_invites(organization_invites, %{field: new_value})
      {:ok, %OrganizationInvites{}}

      iex> update_organization_invites(organization_invites, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_organization_invites(organization_id, %OrganizationInvites{} = organization_invites, attrs) do
    organization_invites
    |> OrganizationInvites.changeset(attrs)
    |> Repo.update(organization_id: organization_id)
  end

  def consume_organization_invite(invite_code, user_id) do
    query =
      from o in OrganizationInvites,
        where:
          o.invite_code == ^invite_code and is_nil(o.consumed_by_id) and
            o.expires_at > ^DateTime.utc_now() and is_nil(o.consumed_at)

    organization_invite = Repo.one(query, skip_organization_id: true)

    case organization_invite do
      nil ->
        {:error, "Invalid invite code"}

      _ ->
        organization_id = organization_invite.organization_id
        user = Repo.get_by(User, [id: user_id], skip_organization_id: true)

        user
        |> User.organization_changeset(%{
          organization_id: organization_id
        })
        |> Repo.update!(skip_organization_id: true)

        organization_invite
        |> OrganizationInvites.changeset(%{
          consumed_by_id: user_id,
          consumed_at: DateTime.utc_now()
        })
        |> Repo.update(organization_id: organization_id)

        {:ok, organization_id}
    end
  end

  @doc """
  Deletes a organization_invites.

  ## Examples

      iex> delete_organization_invites(organization_invites)
      {:ok, %OrganizationInvites{}}

      iex> delete_organization_invites(organization_invites)
      {:error, %Ecto.Changeset{}}

  """
  def delete_organization_invites(organization_id, %OrganizationInvites{} = organization_invites) do
    Repo.delete(organization_invites, organization_id: organization_id)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking organization_invites changes.

  ## Examples

      iex> change_organization_invites(organization_invites)
      %Ecto.Changeset{data: %OrganizationInvites{}}

  """
  def change_organization_invites(%OrganizationInvites{} = organization_invites, attrs \\ %{}) do
    OrganizationInvites.changeset(organization_invites, attrs)
  end

  @doc """
  Deletes a user account after verifying the password.

  Returns {:ok, %User{}} if successful, {:error, :invalid_password} if password is wrong
  """
  def delete_user(user, password) do
    if User.valid_password?(user, password) do
      Repo.delete(user, skip_organization_id: true)
    else
      {:error, :invalid_password}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for deleting user account.

  ## Examples

      iex> change_user_delete_account(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_delete_account(user, attrs \\ %{}) do
    User.delete_account_changeset(user, attrs)
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.update_changeset(attrs)
    |> Repo.update()
  end

  def update_user_avatar(%User{} = user, blob_id) do
    {:ok, result} =
      Repo.transaction(fn ->
        {:ok, _new_user} = result = update_user(user, %{avatar_blob_id: blob_id})

        if user.avatar_blob_id do
          Blobs.delete_blob(user.avatar_blob_id)
        end

        result
      end)

    result
  end

  def get_user_with_avatar(%User{} = user) do
    avatar_url =
      case user.avatar_blob_id do
        nil -> nil
        blob_id -> Blobs.get_blob_url(blob_id)
      end

    Map.put(user, :avatar_url, avatar_url)
  end

  @doc """
  Generates a unique inbound email nickname for an organization.

  Retries up to 10 times if there's a collision.

  ## Examples

      iex> generate_unique_nickname(org_id)
      "cool-tiger-42"

  """
  def generate_unique_nickname(org_id) do
    generate_unique_nickname(org_id, 10)
  end

  defp generate_unique_nickname(_org_id, 0) do
    raise "Failed to generate unique inbound email nickname after 10 attempts"
  end

  defp generate_unique_nickname(org_id, attempts_left) do
    nickname = HumanIDs.generate()

    # Check if nickname already exists
    exists? =
      Organization
      |> where([o], o.inbound_email_nickname == ^nickname)
      |> Repo.exists?(organization_id: org_id)

    if exists? do
      generate_unique_nickname(org_id, attempts_left - 1)
    else
      nickname
    end
  end

  @doc """
  Regenerates the inbound email nickname for an organization.

  Returns `{:ok, %Organization{}}` on success, `{:error, %Ecto.Changeset{}}` on failure.

  ## Examples

      iex> regenerate_organization_nickname(org_id)
      {:ok, %Organization{inbound_email_nickname: "new-nickname-42"}}

  """
  def regenerate_organization_nickname(org_id) do
    org = Repo.get!(Organization, org_id, skip_organization_id: true)
    new_nickname = generate_unique_nickname(org_id)

    org
    |> Organization.changeset(%{inbound_email_nickname: new_nickname})
    |> Repo.update(skip_organization_id: true)
  end
end
