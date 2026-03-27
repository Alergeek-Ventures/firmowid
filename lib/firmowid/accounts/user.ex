defmodule Firmowid.Accounts.User do
  @moduledoc false
  use Firmowid.Schema

  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :employment_date, :date
    field :role, Ecto.Enum, values: [:employee, :admin], default: :employee

    field :system_role, Ecto.Enum, values: [:user, :superuser], default: :user
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :current_password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime

    # OAuth fields
    field :provider, :string, default: "password"
    field :provider_id, :string
    field :google_provider_id, :string

    field :removed_from_project, :boolean, virtual: true, default: false

    many_to_many :projects,
                 Firmowid.Ash.Timetracker.Project,
                 join_through: "projects_users"

    has_many :user_salaries, Firmowid.Ash.Payroll.UserSalary, on_delete: :delete_all

    has_many :sessions, Firmowid.Ash.Timetracker.Session, on_delete: :nothing

    field :marketing_consent, :boolean, default: false

    field :phone, :string
    field :slack_url, :string
    field :slack_id, :string
    field :bank_account_number, :string
    field :birthday, :date

    field :position, :string
    field :student_status_until, :date

    field :correspondence_street, :string
    field :correspondence_city, :string
    field :correspondence_code, :string
    field :residence_street, :string
    field :residence_city, :string
    field :residence_code, :string

    field :employment_contract_type, Ecto.Enum, values: [:umowa_o_prace, :umowa_zlecenie, :umowa_o_dzielo, :b2b]

    belongs_to :avatar_blob, Firmowid.Blobs.Blob
    belongs_to :organization, Firmowid.Accounts.Organization

    timestamps()
  end

  @doc """
  A user changeset for registration.

  It is important to validate the length of both email and password.
  Otherwise databases may truncate the email without warnings, which
  could lead to unpredictable or insecure behaviour. Long passwords may
  also be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.

    * `:validate_email` - Validates the uniqueness of the email, in case
      you don't want to validate the uniqueness of the email (like when
      using this changeset for validations on a LiveView form before
      submitting the form), this option can be set to `false`.
      Defaults to `true`.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email(opts)
    |> validate_password(opts)
  end

  @doc """
  A user changeset for OAuth registration (e.g., Google Sign-In).

  OAuth users don't have passwords, so we skip password validation.
  The account is automatically confirmed since the OAuth provider
  has verified the email.
  """
  def oauth_registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :provider, :provider_id])
    |> validate_required([:email, :provider, :provider_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Firmowid.Repo, repo_opts: [skip_organization_id: true])
    |> unique_constraint(:email)
    |> unique_constraint([:provider, :provider_id])
    |> put_change(:confirmed_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Argon2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Firmowid.Repo, repo_opts: [skip_organization_id: true])
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the email.

  It requires the email to change otherwise an error is added.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  @doc """
  A user changeset for changing the password.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  def organization_changeset(user, attrs) do
    cast(user, attrs, [:organization_id])
  end

  @spec delete_account_changeset(
          {map(),
           %{
             optional(atom()) =>
               atom()
               | {:array | :assoc | :embed | :in | :map | :parameterized | :supertype | :try, any()}
           }}
          | %{
              :__struct__ => atom() | %{:__changeset__ => any(), optional(any()) => any()},
              optional(atom()) => any()
            },
          %{optional(:__struct__) => none(), optional(atom() | binary()) => any()}
        ) :: Ecto.Changeset.t()
  @doc """
  A user changeset for account deletion that only validates the password.
  """
  def delete_account_changeset(user, attrs) do
    user
    |> cast(attrs, [:current_password])
    |> validate_required([:current_password])
    |> validate_current_password(attrs["current_password"])
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Argon2.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Firmowid.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Argon2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Argon2.no_user_verify()
    false
  end

  @doc """
  Validates the current password otherwise adds an error to the changeset.
  """
  def validate_current_password(changeset, password) do
    changeset = cast(changeset, %{current_password: password}, [:current_password])

    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  def update_changeset(user, attrs) do
    cast(user, attrs, [
      :marketing_consent,
      :system_role,
      :name,
      :employment_date,
      :avatar_blob_id,
      :role,
      :phone,
      :slack_url,
      :slack_id,
      :bank_account_number,
      :birthday,
      :employment_contract_type,
      :position,
      :student_status_until,
      :correspondence_street,
      :correspondence_city,
      :correspondence_code,
      :residence_street,
      :residence_city,
      :residence_code
    ])
  end

  @doc """
  A user changeset for updating safe profile fields.

  Only allows updates to fields that users should be able to modify themselves.
  Does NOT allow role or system_role changes.
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :name,
      :employment_date,
      :marketing_consent,
      :avatar_blob_id,
      :phone,
      :slack_url,
      :slack_id,
      :bank_account_number,
      :birthday,
      :employment_contract_type,
      :student_status_until,
      :correspondence_street,
      :correspondence_city,
      :correspondence_code,
      :residence_street,
      :residence_city,
      :residence_code
    ])
    |> validate_required([:name])
  end

  @doc """
  A user changeset for updating roles.

  Only allows role updates. Must be called by admin users.
  """
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, [:employee, :admin])
  end

  @doc """
  A changeset for linking a Google account to an existing user.
  """
  def link_google_changeset(user, google_provider_id) do
    user
    |> change(%{google_provider_id: google_provider_id})
    |> validate_required([:google_provider_id])
    |> unique_constraint(:google_provider_id)
  end
end

defimpl FunWithFlags.Actor, for: Firmowid.Accounts.User do
  def id(%{email: email}), do: "user:#{email}"
end

defimpl FunWithFlags.Group, for: Firmowid.Accounts.User do
  def in?(%{email: email}, group) do
    [_local, domain] = String.split(email, "@", parts: 2)
    group == "domain:#{domain}"
  end
end
