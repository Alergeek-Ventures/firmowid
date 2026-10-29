alias Ash.Error.Invalid

require Logger

defmodule FirmowidWeb.Settings.Views.Index do
  @moduledoc """
  Settings page LiveView.

   TODO: This view handles ~15 distinct responsibilities (company settings,
   user profile, email/password change, account deletion, bank accounts,
   KSeF auth, inbound email, Google linking, avatars,
   requisition PubSub). Split into focused LiveComponents per section.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import FirmowidWeb.Settings.Components.AccountTab
  import FirmowidWeb.Settings.Components.CompanyTab
  import FirmowidWeb.Settings.Components.InvoicesTab
  import FirmowidWeb.Settings.Components.ProfileTab
  import FirmowidWeb.Settings.Components.SettingsPage
  import FirmowidWeb.Settings.Components.SubscriptionTab
  import Phoenix.Component, except: [link: 1]

  alias Ash.Notifier.Notification
  alias AshAuthentication.Argon2Provider
  alias Firmowid.Billing.Month
  alias Firmowid.Blobs
  alias Firmowid.Blobs.Blob
  alias Firmowid.Core
  alias Firmowid.Core.UserRole
  alias Firmowid.Delegations
  alias Firmowid.ErrorKind
  alias Firmowid.Finances
  alias Firmowid.Finances.GoCardless.ApiClient
  alias Firmowid.Finances.Requisition
  alias Firmowid.Ksef.Credential
  alias Firmowid.Payroll
  alias Firmowid.Timetracker
  alias FirmowidUI.Ksef.Connection
  alias FirmowidUI.Utilities.ForbiddenError
  alias FirmowidWeb.Billing.Utilities.MonthContext
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Documents.Components.DocumentsSection
  alias FirmowidWeb.Infrastructure.Components.BlobProcessingToasts
  alias FirmowidWeb.Settings.Utilities.Navigation
  alias Phoenix.Socket.Broadcast

  @invite_load [issued_by: [:email], consumed_by: [:email]]

  def form_basic_info_form(organization, scope) do
    organization
    |> AshPhoenix.Form.for_update(:update_basic_info,
      scope: scope,
      domain: Core,
      as: "organization",
      params: %{
        "is_same_correspondence_address" => to_string(organization.correspondence_address in [nil, ""])
      }
    )
    |> to_form()
  end

  def form_member_form(member, scope) do
    member
    |> AshPhoenix.Form.for_update(:update_profile,
      scope: scope,
      domain: Core,
      as: "user",
      params: %{
        "is_same_correspondence_address" => to_string(member.correspondence_address in [nil, ""])
      }
    )
    |> to_form()
  end

  def form_password_form(current_user) do
    current_user
    |> AshPhoenix.Form.for_update(:change_password,
      domain: Core,
      as: "user",
      actor: current_user
    )
    |> to_form()
  end

  def form_email_form(current_user, scope) do
    current_user
    |> AshPhoenix.Form.for_update(:change_email,
      scope: scope,
      domain: Core,
      as: "user"
    )
    |> to_form()
  end

  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    current_org = socket.assigns.current_org
    admin? = current_user.member.role == :admin
    scope = socket.assigns.ash_scope
    current_year = Date.utc_today().year

    # Use Ash native code interface for listing bank accounts
    bank_accounts = if(admin?, do: list_bank_accounts(scope), else: [])
    pending_requisitions = if(admin?, do: list_pending_requisitions(scope), else: [])
    organization_users = if(admin?, do: list_organization_users(scope), else: [])
    organization_invites = if(admin?, do: list_organization_invites(scope), else: [])

    bank_institutions =
      if(admin?, do: list_bank_institutions(current_user, bank_accounts), else: %{})

    leave_requests =
      Timetracker.list_leave_requests_for_member!(current_user.member.id, scope: scope)

    delegations = Delegations.list_delegations_for_member!(current_user.member.id, scope: scope)

    leave_days =
      current_user.member
      |> Ash.load!([accepted_leave_days_for_year: %{year: current_year}], scope: scope)
      |> Map.fetch!(:accepted_leave_days_for_year)

    {profile_projects, profile_projects_total, profile_projects_date} =
      load_profile_projects(current_user.id, scope)

    subscribe_to_admin_updates(socket, current_org.id, admin?)

    if connected?(socket) do
      Endpoint.subscribe("blob:created:#{current_org.id}")
      Endpoint.subscribe("blob:updated:#{current_org.id}")
      Endpoint.subscribe("blob:destroyed:#{current_org.id}")
    end

    socket =
      if admin? do
        socket
        |> Connection.init(scope)
        |> assign(:company_form, form_basic_info_form(current_org, scope))
        |> allow_upload(:organization_avatar,
          accept: ~w(.jpg .jpeg .png),
          max_entries: 1,
          auto_upload: true,
          progress: &handle_progress/3
        )
        |> allow_upload(:document_upload,
          accept: ~w(.pdf .doc .docx),
          max_entries: 1,
          auto_upload: true,
          progress: &handle_progress/3
        )
      else
        socket
      end

    socket = assign(socket, :member_form, form_member_form(current_user.member, scope))

    # Load avatars using Ash.load!
    org_with_avatar =
      Ash.load!(current_org, [avatar_blob: [:url]], scope: scope)

    {:ok, google_identities} =
      Core.read_user_identity_for_strategy(
        current_user.id,
        "google",
        scope: scope
      )

    google_connected? = google_identities != []

    {:ok, pending_contract} = Payroll.load_pending_contract(current_user.member.id, scope: scope)
    {:ok, current_contract} = Payroll.load_current_contract(current_user.member.id, scope: scope)

    {:ok,
     socket
     |> assign(:editing_basic_info, false)
     |> assign(:editing_account_name, false)
     |> assign(:editing_profile_employment, false)
     |> assign(:editing_profile_finance, false)
     |> assign(:editing_profile_contact, false)
     |> assign(:editing_credentials, false)
     |> assign(:show_active_invites, false)
     |> assign(:settings_tab, :account)
     |> assign(:subscription_month, nil)
     |> assign(:subscription_worksheet, nil)
     |> assign(:trigger_submit, false)
     |> assign(:delete_account_form, to_form(%{"current_password" => ""}, as: "user"))
     |> assign(:owned_organizations, Core.list_owned_organizations(current_user))
     |> assign(:current_password, nil)
     |> assign(:password_form, form_password_form(current_user))
     |> assign(:email_form, form_email_form(current_user, scope))
     |> assign(:bank_accounts, bank_accounts)
     |> assign(:bank_institutions, bank_institutions)
     |> assign(:pending_requisitions, pending_requisitions)
     |> assign(:organization_users, organization_users)
     |> assign(:organization_invites, organization_invites)
     |> assign(:selected_user, nil)
     |> assign(:bank_account_statuses, derive_statuses(bank_accounts))
     |> assign(:google_connected?, google_connected?)
     |> assign(:uploaded_files, [])
     |> assign(:no_padding, true)
     |> allow_upload(:user_avatar,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       auto_upload: true,
       progress: &handle_progress/3
     )
     |> assign(:leave_requests, leave_requests)
     |> assign(:delegations, delegations)
     |> assign(:leave_days, leave_days || 0)
     |> assign(:leave_search, "")
     |> assign(:leave_request_form, leave_request_form(current_user, scope))
     |> assign(:selected_leave_reason, default_leave_reason())
     |> allow_upload(:leave_request_attachment,
       accept: ~w(.pdf .jpg .jpeg .png),
       max_entries: 1,
       max_file_size: 10_000_000,
       auto_upload: true
     )
     |> allow_upload(:signed_contract,
       accept: ~w(.pdf),
       max_entries: 1,
       max_file_size: 10_000_000,
       auto_upload: true
     )
     |> assign(:projects, profile_projects)
     |> assign(:projects_total, profile_projects_total)
     |> assign(:projects_date, profile_projects_date)
     |> assign(:current_org, org_with_avatar)
     |> assign(:current_contract, current_contract)
     |> assign(:pending_contract, pending_contract)
     |> assign(:contract_form, form_contract_form(current_contract, scope))
     |> assign(:main_class, "bg-white")}
  end

  defp subscribe_to_admin_updates(socket, organization_id, true) do
    if connected?(socket) do
      Endpoint.subscribe("requisition:linked:#{organization_id}")
      Endpoint.subscribe("requisition:rejected:#{organization_id}")
      Endpoint.subscribe("requisition:expired:#{organization_id}")
    end
  end

  defp subscribe_to_admin_updates(_socket, _organization_id, _admin?), do: :ok

  def handle_params(params, _uri, socket) when map_size(params) == 0 do
    {:noreply, push_patch(socket, to: Navigation.default_path())}
  end

  def handle_params(%{"section" => section}, _uri, socket) do
    case Navigation.resolve_section(section) do
      {:ok, %{id: tab} = resolved} ->
        handle_resolved_section(tab, resolved, socket)

      :error ->
        {:noreply, push_patch(socket, to: Navigation.default_path())}
    end
  end

  def handle_avatar_upload(:user_avatar, blob_id, socket) do
    current_user = socket.assigns.current_user

    {:ok, updated} =
      Core.update_member_avatar(current_user.member, %{avatar_blob_id: blob_id}, scope: socket.assigns.ash_scope)

    # Load avatar using Ash.load!
    updated_with_avatar =
      Ash.load!(updated, [avatar_blob: [:url]], scope: socket.assigns.ash_scope)

    LiveToast.send_toast(:info, "Zdjęcie zostało zaktualizowane.")

    {:noreply, assign(socket, :current_user, %{current_user | member: updated_with_avatar})}
  end

  def handle_avatar_upload(:organization_avatar, blob_id, socket) do
    current_org = socket.assigns.current_org

    {:ok, updated} =
      Core.update_organization_avatar(current_org, %{avatar_blob_id: blob_id}, scope: socket.assigns.ash_scope)

    # Load avatar using Ash.load!
    updated_with_avatar =
      Ash.load!(updated, [avatar_blob: [:url]], scope: socket.assigns.ash_scope)

    LiveToast.send_toast(:info, "Zdjęcie zostało zaktualizowane.")

    {:noreply,
     socket
     |> assign(:current_org, updated_with_avatar)
     |> assign_subscription_preview_if_visible()}
  end

  defp handle_progress(:document_upload, %{done?: false}, socket) do
    {:noreply, socket}
  end

  defp handle_progress(:document_upload, entry, socket) do
    scope = socket.assigns.ash_scope
    member_id = socket.assigns.current_user.member.id

    case consume_uploaded_entry(socket, entry, fn %{path: path} ->
           {:ok,
            Blobs.create_blob_for_processing(
              path,
              entry.client_type,
              entry.client_name,
              :employment_contract,
              %{member_id: member_id},
              scope: scope
            )}
         end) do
      {:ok, %Blob{}} ->
        LiveToast.send_toast(:success, "Plik został wysłany.")

      {:error, err} ->
        Logger.warning("Employment contract upload failed", error_kind: ErrorKind.classify(err))
        LiveToast.send_toast(:error, "Wystąpił błąd podczas wysyłania pliku.")
    end

    {:noreply, socket}
  end

  defp handle_progress(name, %{done?: false}, socket) when name in [:organization_avatar, :user_avatar] do
    {:noreply, socket}
  end

  defp handle_progress(name, entry, socket) when name in [:organization_avatar, :user_avatar] do
    if name == :organization_avatar do
      if socket.assigns.current_user.member.role != :admin do
        raise ForbiddenError, "Tylko administrator może zmienić logo organizacji."
      end
    end

    scope = socket.assigns.ash_scope

    case consume_uploaded_entry(socket, entry, fn %{path: path} ->
           {:ok,
            Blobs.create_or_reuse_blob(
              path,
              entry.client_type,
              entry.client_name,
              scope: scope
            )}
         end) do
      {:ok, %Blob{} = blob} ->
        handle_avatar_upload(name, blob.id, socket)

      {:error, err} ->
        Logger.warning("Avatar upload failed", error_kind: ErrorKind.classify(err))
        LiveToast.send_toast(:error, "Wystąpił błąd podczas aktualizacji zdjęcia.")
        {:noreply, socket}
    end
  end

  defp list_organization_users(scope) do
    Core.list_users!(%{status: :active}, load: [member: [avatar_blob: [:url]]], scope: scope)
  end

  defp list_organization_invites(scope) do
    Core.list_invites!(load: @invite_load, scope: scope)
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_account", %{"user" => params}, socket) do
    user = socket.assigns.current_user
    password = params["current_password"]

    # Verify password at callsite before destroying user
    if Argon2Provider.valid?(password, user.hashed_password) do
      case Core.destroy_user(user, scope: socket.assigns.ash_scope) do
        :ok ->
          LiveToast.send_toast(:info, "Konto zostało usunięte.")
          {:noreply, redirect(socket, to: ~p"/")}

        {:error, error} ->
          LiveToast.send_toast(:error, "Wystąpił błąd podczas usuwania konta")

          Logger.error("Failed to delete user account",
            error_kind: ErrorKind.classify(error)
          )

          {:noreply, socket}
      end
    else
      LiveToast.send_toast(:error, "Nieprawidłowe hasło")
      {:noreply, socket}
    end
  end

  def handle_event("upload", _, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_bank_account", %{"account_id" => account_id}, socket) do
    scope = socket.assigns.ash_scope
    bank_account = Finances.get_bank_account!(account_id, scope: scope)

    case Finances.destroy_bank_account(bank_account, scope: scope) do
      :ok ->
        LiveToast.send_toast(:info, "Konto bankowe zostało usunięte.")

        bank_accounts = list_bank_accounts(scope)

        {:noreply,
         socket
         |> assign(:bank_accounts, bank_accounts)
         |> assign(
           :bank_institutions,
           list_bank_institutions(socket.assigns.current_user, bank_accounts)
         )
         |> assign(:pending_requisitions, list_pending_requisitions(scope))
         |> assign(:bank_account_statuses, derive_statuses(bank_accounts))
         |> assign_subscription_preview_if_visible()}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas usuwania konta bankowego.")
        {:noreply, socket}
    end
  end

  def handle_event("make_default_account", %{"account_id" => account_id}, socket) do
    scope = socket.assigns.ash_scope

    bank_account = Finances.get_bank_account!(account_id, scope: scope)

    case Finances.update_bank_account(bank_account, %{is_default: true}, scope: scope) do
      {:ok, _} ->
        bank_accounts = list_bank_accounts(scope)

        {:noreply,
         socket
         |> assign(:bank_accounts, bank_accounts)
         |> assign(
           :bank_institutions,
           list_bank_institutions(socket.assigns.current_user, bank_accounts)
         )
         |> assign(:pending_requisitions, list_pending_requisitions(scope))
         |> assign(:bank_account_statuses, derive_statuses(bank_accounts))
         |> assign_subscription_preview_if_visible()}

      {:error, _} ->
        LiveToast.send_toast(
          :error,
          "Wystąpił błąd podczas ustawiania konta bankowego jako domyślne."
        )

        {:noreply, socket}
    end
  end

  def handle_event("save", %{"organization" => org_params}, socket) do
    current_user = socket.assigns.current_user
    scope = socket.assigns.ash_scope

    if current_user.member.role != :admin do
      raise ForbiddenError, "Tylko administrator może aktualizować organizację."
    end

    case AshPhoenix.Form.submit(socket.assigns.company_form, params: org_params, scope: scope) do
      {:ok, updated_org} ->
        # Load avatar using Ash.load!
        updated_with_avatar =
          Ash.load!(updated_org, [avatar_blob: [:url]], scope: socket.assigns.ash_scope)

        {:noreply,
         socket
         |> assign(:editing_basic_info, false)
         |> assign(:company_form, form_basic_info_form(updated_with_avatar, scope))
         |> assign(:current_org, updated_with_avatar)
         |> assign_subscription_preview_if_visible()}

      {:error, form} ->
        {:noreply, assign(socket, :company_form, form)}
    end
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    save_member_form(socket, merge_user_name_params(user_params), :editing_account_name)
  end

  def handle_event("save_profile_contact", %{"user" => user_params}, socket) do
    save_member_form(socket, user_params, :editing_profile_contact)
  end

  def handle_event("save_profile_" <> section, %{"user" => user_params}, socket) do
    save_member_form(socket, user_params, profile_section_assign(section))
  end

  def handle_event("validate_profile_contact", %{"user" => user_params}, socket) do
    form =
      socket.assigns.member_form
      |> AshPhoenix.Form.validate(user_params)
      |> to_form()

    {:noreply, assign(socket, :member_form, form)}
  end

  def handle_event("change_email", %{"user" => user_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.email_form, params: user_params) do
      {:ok, user} ->
        LiveToast.send_toast(:info, "Wysłaliśmy link potwierdzający na nowy adres email.")

        {:noreply,
         socket
         |> assign(:editing_credentials, false)
         |> assign(:current_user, user)
         |> assign(:current_password, nil)
         |> assign(:password_form, form_password_form(user))
         |> assign(:email_form, form_email_form(user, socket.assigns.ash_scope))}

      {:error, form} ->
        LiveToast.send_toast(:error, "Nie udało się wysłać wiadomości email. Spróbuj ponownie.")
        {:noreply, assign(socket, :email_form, form)}
    end
  end

  def handle_event("open_update_role_modal", %{"user_id" => user_id}, socket) do
    case find_loaded_organization_user(socket.assigns.organization_users, user_id) do
      {:ok, user} ->
        {:noreply, assign(socket, :selected_user, user)}

      {:error, :unknown_user} ->
        LiveToast.send_toast(:error, "Nie znaleziono użytkownika w organizacji.")
        {:noreply, socket}
    end
  end

  def handle_event("clear_selected_user", _params, socket) do
    {:noreply, assign(socket, :selected_user, nil)}
  end

  def handle_event("update_user_role", %{"user_id" => user_id, "role" => role_param}, socket) do
    with {:ok, role} <- parse_role(role_param),
         {:ok, user} <- find_loaded_organization_user(socket.assigns.organization_users, user_id),
         {:ok, _member} <-
           Core.update_member_role(user.member, %{role: role}, scope: socket.assigns.ash_scope) do
      LiveToast.send_toast(:success, "Rola użytkownika została zmieniona.")

      {:noreply,
       socket
       |> assign(:organization_users, list_organization_users(socket.assigns.ash_scope))
       |> assign(:selected_user, nil)
       |> assign_subscription_preview_if_visible()}
    else
      {:error, :unknown_role} ->
        LiveToast.send_toast(:error, "Nieznana rola użytkownika.")
        {:noreply, assign(socket, :selected_user, nil)}

      {:error, :unknown_user} ->
        LiveToast.send_toast(:error, "Nie znaleziono użytkownika w organizacji.")
        {:noreply, assign(socket, :selected_user, nil)}

      {:error, _error} ->
        LiveToast.send_toast(:error, "Nie udało się zmienić roli użytkownika.")
        {:noreply, assign(socket, :selected_user, nil)}
    end
  end

  def handle_event("archive_organization_user", %{"user_id" => user_id}, socket) do
    current_user = socket.assigns.current_user

    if current_user.member.role != :admin do
      raise ForbiddenError, "Tylko administrator może archiwizować użytkowników."
    end

    with {:ok, user} <- find_loaded_organization_user(socket.assigns.organization_users, user_id),
         :ok <- prevent_self_user_management(current_user, user),
         {:ok, _member} <- Core.archive_member(user.member, scope: socket.assigns.ash_scope) do
      LiveToast.send_toast(:info, "Użytkownik został zarchiwizowany.")

      {:noreply,
       socket
       |> assign(:organization_users, list_organization_users(socket.assigns.ash_scope))
       |> assign_subscription_preview_if_visible()}
    else
      {:error, :self_user_management} ->
        LiveToast.send_toast(:error, "Nie możesz zarchiwizować własnego konta z tego miejsca.")
        {:noreply, socket}

      {:error, :unknown_user} ->
        LiveToast.send_toast(:error, "Nie znaleziono użytkownika w organizacji.")
        {:noreply, socket}

      {:error, _error} ->
        LiveToast.send_toast(:error, "Nie udało się zarchiwizować użytkownika.")
        {:noreply, socket}
    end
  end

  def handle_event("rename_bank_account", %{"account_id" => account_id, "name" => name}, socket) do
    scope = socket.assigns.ash_scope
    bank_account = Finances.get_bank_account!(account_id, scope: scope)

    case Finances.update_bank_account(bank_account, %{name: name}, scope: scope) do
      {:ok, _} ->
        LiveToast.send_toast(:info, "Nazwa konta została zmieniona.")

        accounts = list_bank_accounts(scope)

        {:noreply,
         socket
         |> assign(:bank_accounts, accounts)
         |> assign(
           :bank_institutions,
           list_bank_institutions(socket.assigns.current_user, accounts)
         )
         |> assign(:pending_requisitions, list_pending_requisitions(scope))
         |> assign(:bank_account_statuses, derive_statuses(accounts))
         |> assign_subscription_preview_if_visible()
         |> push_event("js-exec", %{
           to: "#manual_bank_account_modal_company",
           attr: "data-cancel"
         })}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas zmiany nazwy konta.")
        {:noreply, socket}
    end
  end

  def handle_event("reconnect_bank_account", %{"account_id" => account_id}, socket) do
    scope = socket.assigns.ash_scope
    bank_account = Finances.get_bank_account!(account_id, scope: scope)

    # If the account doesn't have an institution associated (legacy/imported),
    # redirect the user to the standard bank connection flow.
    if is_nil(bank_account.institution_id) do
      {:noreply, push_navigate(socket, to: ~p"/ustawienia/bank/dodaj")}
    else
      organization_id = socket.assigns.ash_scope.tenant
      redirect_url = Endpoint.url() <> "/ustawienia/bank/dodaj"

      # Determine the correct transaction horizon for this institution (as in /dodaj)
      transaction_days =
        case ApiClient.get_institution(bank_account.institution_id) do
          {:ok, %{"transaction_total_days" => days}} when is_integer(days) -> days
          _ -> 90
        end

      # Use Ash native code interface with authorization
      case Finances.create_requisition(
             bank_account.institution_id,
             transaction_days,
             redirect_url,
             tenant: organization_id,
             actor: socket.assigns.current_user,
             authorize?: true
           ) do
        {:ok, link} ->
          {:noreply, Phoenix.LiveView.redirect(socket, external: link)}

        {:error, _} ->
          LiveToast.send_toast(:error, "Nie udało się rozpocząć ponownego połączenia.")
          {:noreply, socket}
      end
    end
  end

  def handle_event("create_manual_bank_account", params, socket) do
    scope = socket.assigns.ash_scope

    attrs = %{
      iban: params["iban"],
      name: params["name"],
      currency: params["currency"],
      owner_name: params["owner_name"]
    }

    case Finances.create_manual_bank_account(attrs, scope: scope) do
      {:ok, _} ->
        LiveToast.send_toast(:info, "Konto zostało dodane.")

        accounts = list_bank_accounts(scope)

        {:noreply,
         socket
         |> assign(:bank_accounts, accounts)
         |> assign(
           :bank_institutions,
           list_bank_institutions(socket.assigns.current_user, accounts)
         )
         |> assign(:pending_requisitions, list_pending_requisitions(scope))
         |> assign(:bank_account_statuses, derive_statuses(accounts))
         |> assign_subscription_preview_if_visible()}

      {:error, _} ->
        LiveToast.send_toast(:error, "Nie udało się dodać konta.")
        {:noreply, socket}
    end
  end

  def handle_event("regenerate_inbound_nickname", _params, socket) do
    current_user = socket.assigns.current_user
    current_org = socket.assigns.current_org

    if current_user.member.role != :admin do
      raise ForbiddenError, "Tylko administrator może zmienić adres e-mail."
    end

    case Core.regenerate_nickname(current_org, scope: socket.assigns.ash_scope) do
      {:ok, updated_org} ->
        # Load avatar using Ash.load!
        updated_with_avatar =
          Ash.load!(updated_org, [avatar_blob: [:url]], scope: socket.assigns.ash_scope)

        LiveToast.send_toast(:info, "Nowy adres e-mail został wygenerowany.")

        {:noreply,
         socket
         |> assign(:current_org, updated_with_avatar)
         |> assign_subscription_preview_if_visible()}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas generowania nowego adresu.")
        {:noreply, socket}
    end
  end

  def handle_event("copy_inbound_email", %{"email" => email}, socket) do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: email})
     |> LiveToast.put_toast(:success, "Skopiowano adres odbiorczy")}
  end

  def handle_event("add_allowed_email", %{"email" => email}, socket) do
    current_user = socket.assigns.current_user
    current_org = socket.assigns.current_org

    if current_user.member.role != :admin do
      raise ForbiddenError, "Tylko administrator może zarządzać listą dozwolonych adresów."
    end

    case Core.add_sender_email(current_org, %{email: String.trim(email)}, scope: socket.assigns.ash_scope) do
      {:ok, updated_org} ->
        # Load avatar using Ash.load!
        updated_with_avatar =
          Ash.load!(updated_org, [avatar_blob: [:url]], scope: socket.assigns.ash_scope)

        LiveToast.send_toast(:info, "Adres e-mail został dodany do listy dozwolonych.")

        {:noreply,
         socket
         |> assign(:current_org, updated_with_avatar)
         |> assign_subscription_preview_if_visible()}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas dodawania adresu e-mail.")
        {:noreply, socket}
    end
  end

  def handle_event("remove_allowed_email", %{"email" => email}, socket) do
    current_user = socket.assigns.current_user
    current_org = socket.assigns.current_org

    if current_user.member.role != :admin do
      raise ForbiddenError, "Tylko administrator może zarządzać listą dozwolonych adresów."
    end

    case Core.remove_sender_email(current_org, %{email: email}, scope: socket.assigns.ash_scope) do
      {:ok, updated_org} ->
        # Load avatar using Ash.load!
        updated_with_avatar =
          Ash.load!(updated_org, [avatar_blob: [:url]], scope: socket.assigns.ash_scope)

        LiveToast.send_toast(:info, "Adres e-mail został usunięty z listy dozwolonych.")

        {:noreply,
         socket
         |> assign(:current_org, updated_with_avatar)
         |> assign_subscription_preview_if_visible()}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas usuwania adresu e-mail.")
        {:noreply, socket}
    end
  end

  def handle_event(event, params, socket)
      when event in [
             "save_ksef_token",
             "select_ksef_auth_method",
             "validate_ksef_certificate",
             "download_ksef_auth_token_request",
             "validate_signed_auth_token_request",
             "upload_signed_auth_token_request",
             "save_ksef_certificate",
             "disconnect_ksef",
             "fetch_ksef_invoices"
           ] do
    Connection.handle_event(event, params, socket, socket.assigns.ash_scope)
  end

  def handle_event("toggle_editing_basic_info", _params, socket) do
    {:noreply, assign(socket, :editing_basic_info, !socket.assigns.editing_basic_info)}
  end

  def handle_event("toggle_editing_account_name", _params, socket) do
    {:noreply, assign(socket, :editing_account_name, !socket.assigns.editing_account_name)}
  end

  def handle_event("toggle_editing_profile_employment", _params, socket) do
    {:noreply, assign(socket, :editing_profile_employment, !socket.assigns.editing_profile_employment)}
  end

  def handle_event("toggle_editing_profile_finance", _params, socket) do
    {:noreply, assign(socket, :editing_profile_finance, !socket.assigns.editing_profile_finance)}
  end

  def handle_event("toggle_editing_profile_contact", _params, socket) do
    {:noreply, assign(socket, :editing_profile_contact, !socket.assigns.editing_profile_contact)}
  end

  def handle_event("toggle_active_invites", _params, socket) do
    {:noreply, assign(socket, :show_active_invites, !socket.assigns.show_active_invites)}
  end

  def handle_event("create_organization_invite", %{"role" => role_param}, socket) do
    current_user = socket.assigns.current_user
    scope = socket.assigns.ash_scope

    case parse_role(role_param) do
      {:ok, role} ->
        invite = Core.create_invite!(%{issued_by_id: current_user.id, role: role}, scope: scope)

        LiveToast.send_toast(
          :success,
          "Kod zaproszenia został wygenerowany i skopiowany do schowka."
        )

        {:noreply,
         socket
         |> assign(:organization_invites, list_organization_invites(scope))
         |> assign(:show_active_invites, true)
         |> push_event("copy-to-clipboard", %{text: invite.invite_code})}

      {:error, :unknown_role} ->
        LiveToast.send_toast(:error, "Nieprawidłowa rola.")
        {:noreply, socket}
    end
  end

  def handle_event("copy_organization_invite", %{"code" => invite_code}, socket) do
    LiveToast.send_toast(:info, "Kod zaproszenia został skopiowany do schowka.")

    {:noreply, push_event(socket, "copy-to-clipboard", %{text: invite_code})}
  end

  def handle_event("delete_organization_invite", %{"id" => id}, socket) do
    scope = socket.assigns.ash_scope

    invite = Core.get_invite!(id, scope: scope)
    Core.destroy_invite!(invite, scope: scope)

    LiveToast.send_toast(:info, "Zaproszenie zostało usunięte.")

    {:noreply, assign(socket, :organization_invites, list_organization_invites(scope))}
  end

  def handle_event("toggle_editing_credentials", _params, socket) do
    editing_credentials? = !socket.assigns.editing_credentials

    socket = assign(socket, :editing_credentials, editing_credentials?)

    if editing_credentials? do
      {:noreply,
       assign(
         socket,
         :email_form,
         form_email_form(socket.assigns.current_user, socket.assigns.ash_scope)
       )}
    else
      {:noreply,
       socket
       |> assign(:current_password, nil)
       |> assign(:password_form, form_password_form(socket.assigns.current_user))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      AshPhoenix.Form.validate(socket.assigns.password_form, user_params)

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => _password, "user" => user_params} = params

    case AshPhoenix.Form.submit(socket.assigns.password_form, params: user_params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Hasło zostało zmienione pomyślnie.")
         |> push_navigate(to: password_return_path(socket.assigns.settings_tab))}

      {:error, form} ->
        {:noreply, assign(socket, password_form: form)}
    end
  end

  def handle_event("link_google_account", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/auth/user/google")}
  end

  def handle_event("replace_google_account", _params, socket) do
    user = socket.assigns.current_user

    case Core.unlink_google_account(user, scope: socket.assigns.ash_scope) do
      {:ok, _updated_user} ->
        {:noreply, redirect(socket, to: ~p"/auth/user/google")}

      {:error, _error} ->
        LiveToast.send_toast(:error, "Nie udało się zmienić konta Google.")
        {:noreply, socket}
    end
  end

  def handle_event("unlink_google_account", _params, socket) do
    user = socket.assigns.current_user

    case Core.unlink_google_account(user, scope: socket.assigns.ash_scope) do
      {:ok, updated_user} ->
        LiveToast.send_toast(:info, "Konto Google zostało odłączone.")
        {:noreply, assign(socket, :current_user, updated_user)}

      {:error, error} ->
        message =
          case error do
            %{errors: [%{message: msg}]} -> msg
            _ -> "Wystąpił błąd podczas odłączania konta Google."
          end

        LiveToast.send_toast(:error, message)
        {:noreply, socket}
    end
  end

  def handle_event("search_leave_requests", %{"szukaj" => search}, socket) do
    {:noreply, assign(socket, :leave_search, search)}
  end

  def handle_event("select_leave_reason", %{"reason" => reason}, socket) do
    form =
      AshPhoenix.Form.validate(
        socket.assigns.leave_request_form.source,
        Map.put(
          AshPhoenix.Form.params(socket.assigns.leave_request_form.source),
          "reason",
          reason
        )
      )

    {:noreply, assign(socket, :leave_request_form, to_form(form))}
  end

  def handle_event("create_leave_request", %{"leave_request" => params}, socket) do
    scope = socket.assigns.ash_scope

    attrs = %{
      starts_on: params["starts_on"],
      ends_on: params["ends_on"],
      reason: params["reason"],
      note: params["note"]
    }

    result =
      case uploaded_entries(socket, :leave_request_attachment) do
        {[], []} ->
          Timetracker.create_leave_request(attrs, scope: scope)

        {[entry], []} ->
          create_leave_request_with_upload(socket, entry, attrs, scope)

        {_, [_ | _]} ->
          {:error, :upload_in_progress}
      end

    case result do
      {:ok, _request} ->
        leave_requests =
          Timetracker.list_leave_requests_for_member!(
            socket.assigns.current_user.member.id,
            scope: scope
          )

        {:noreply,
         socket
         |> assign(:leave_requests, leave_requests)
         |> assign(:leave_request_form, leave_request_form(socket.assigns.current_user, scope))
         |> push_event("js-exec", %{to: "#leave-request-modal", attr: "data-cancel"})}

      {:error, %Invalid{} = error} ->
        form =
          socket.assigns.leave_request_form.source
          |> AshPhoenix.Form.validate(params)
          |> AshPhoenix.Form.add_error(error)

        {:noreply, assign(socket, :leave_request_form, to_form(form))}

      {:error, _reason} ->
        LiveToast.send_toast(:error, "Nie udało się wysłać wniosku.")
        {:noreply, socket}
    end
  end

  # LiveView requires a phx-change handler to initialize and track uploaded files.
  def handle_event("validate_leave_request_attachment", %{"leave_request" => params}, socket) do
    form =
      AshPhoenix.Form.validate(
        socket.assigns.leave_request_form.source,
        params
      )

    {:noreply, assign(socket, :leave_request_form, to_form(form))}
  end

  def handle_event("cancel_leave_request_attachment", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :leave_request_attachment, ref)}
  end

  def handle_event("submit_signed_contract", _params, socket) do
    scope = socket.assigns.ash_scope
    pending_contract = socket.assigns.pending_contract

    case uploaded_entries(socket, :signed_contract) do
      {[entry], []} ->
        case consume_uploaded_entry(socket, entry, fn %{path: path} ->
               {:ok,
                Payroll.submit_signed(pending_contract, path, entry.client_name,
                  scope: scope,
                  actor: socket.assigns.current_user
                )}
             end) do
          {:ok, _contract} ->
            LiveToast.send_toast(:success, "Umowa została pomyślnie podpisana.")

            current_user =
              Core.get_user!(socket.assigns.current_user.id,
                scope: scope,
                load: [:member],
                actor: socket.assigns.current_user
              )

            {:noreply, refresh_profile_assigns(socket, current_user)}

          {:error, _error} ->
            LiveToast.send_toast(:error, "Nie udało się przesłać umowy. Spróbuj ponownie.")
            {:noreply, socket}
        end

      {_, [_ | _]} ->
        LiveToast.send_toast(:error, "Plik jest jeszcze przesyłany.", title: "Błąd przesyłania")
        {:noreply, socket}

      {[], []} ->
        LiveToast.send_toast(:error, "Wybierz plik do przesłania.", title: "Brak pliku")
        {:noreply, socket}
    end
  end

  def handle_event("validate_signed_contract", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_signed_contract", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :signed_contract, ref)}
  end

  def handle_event("validate_company_form", %{"organization" => params}, socket) do
    form =
      AshPhoenix.Form.validate(
        socket.assigns.company_form.source,
        params
      )

    {:noreply, assign(socket, :company_form, to_form(form))}
  end

  def handle_event("save_contract_employment", %{"contract" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.contract_form,
           params: params,
           scope: socket.assigns.ash_scope
         ) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign(:editing_profile_employment, false)
         |> refresh_profile_assigns(socket.assigns.current_user)}

      {:error, form} ->
        {:noreply, assign(socket, :contract_form, form)}
    end
  end

  def handle_info(%Broadcast{topic: "credential:" <> _, payload: %Notification{resource: Credential}} = message, socket) do
    Connection.handle_info(message, socket, socket.assigns.ash_scope)
  end

  # Handle Ash native PubSub broadcasts for requisition status changes
  def handle_info(
        %Broadcast{topic: "requisition:" <> _, payload: %Notification{resource: Requisition, action: action}},
        socket
      ) do
    # Refresh bank accounts list
    scope = socket.assigns.ash_scope

    bank_accounts = list_bank_accounts(scope)

    socket =
      socket
      |> assign(:bank_accounts, bank_accounts)
      |> assign(
        :bank_institutions,
        list_bank_institutions(socket.assigns.current_user, bank_accounts)
      )
      |> assign(:pending_requisitions, list_pending_requisitions(scope))
      |> assign(:bank_account_statuses, derive_statuses(bank_accounts))
      |> assign_subscription_preview_if_visible()

    # Show toast notification
    {toast_type, message} =
      case action do
        :accept ->
          {:success, "Konto bankowe zostało pomyślnie połączone!"}

        :reject ->
          {:error, "Połączenie z bankiem zostało odrzucone. Spróbuj ponownie."}

        :handle_check_error ->
          {:error, "Wystąpił błąd podczas łączenia konta bankowego. Spróbuj ponownie."}

        _ ->
          {:info, "Status połączenia z bankiem został zaktualizowany."}
      end

    LiveToast.send_toast(toast_type, message)

    {:noreply, socket}
  end

  def handle_info(
        %Broadcast{
          payload: %Notification{
            resource: Blob,
            action: %{type: :create},
            data: %{processing_target: :employment_contract}
          }
        },
        socket
      ) do
    send_update(DocumentsSection, id: "profile-documents", refetch: true)
    {:noreply, socket}
  end

  def handle_info(
        %Broadcast{
          payload: %Notification{
            resource: Blob,
            action: %{type: :update},
            data: %{processing_target: :employment_contract} = blob
          }
        },
        socket
      ) do
    cond do
      blob.processing_state == :failed ->
        BlobProcessingToasts.show_failure_toast(blob)

      blob.processing_state == :succeeded ->
        BlobProcessingToasts.show_success_toast(blob, :employment_contract)

      true ->
        :ok
    end

    send_update(DocumentsSection, id: "profile-documents", refetch: true)

    {:noreply, refresh_profile_assigns(socket, socket.assigns.current_user)}
  end

  def handle_info(
        %Broadcast{
          payload:
            %Notification{
              resource: Blob,
              action: %{type: :destroy},
              data: %{processing_target: :employment_contract},
              metadata: %{reason: :processing_failed}
            } = notification
        },
        socket
      ) do
    LiveToast.send_toast(:error, notification.data.original_filename, title: "Nie udało się wgrać pliku")

    send_update(DocumentsSection, id: "profile-documents", refetch: true)
    {:noreply, socket}
  end

  def handle_info(
        %Broadcast{
          payload:
            %Notification{
              resource: Blob,
              action: %{type: :destroy},
              data: %{processing_target: :employment_contract},
              metadata: %{reason: :invalid_document}
            } = notification
        },
        socket
      ) do
    LiveToast.send_toast(
      :error,
      "Plik #{notification.data.original_filename} nie zawiera wymaganych danych. Upewnij się, że wgrywasz umowę.",
      title: "Nieprawidłowy dokument"
    )

    send_update(DocumentsSection, id: "profile-documents", refetch: true)
    {:noreply, socket}
  end

  def handle_info(
        %Broadcast{
          payload: %Notification{
            resource: Blob,
            data: %{processing_target: :employment_contract},
            action: %{type: :destroy}
          }
        },
        socket
      ) do
    send_update(DocumentsSection, id: "profile-documents", refetch: true)
    {:noreply, socket}
  end

  # Ignore other blob broadcasts (e.g., signed contract uploads with processing_target :none)
  def handle_info(%Broadcast{payload: %Notification{resource: Blob}}, socket) do
    {:noreply, socket}
  end

  defp create_leave_request_with_upload(socket, entry, attrs, scope) do
    consume_uploaded_entry(socket, entry, fn %{path: path} ->
      {:ok,
       Timetracker.create_leave_request_with_upload(
         Map.merge(attrs, %{
           upload_path: path,
           upload_filename: entry.client_name
         }),
         scope: scope
       )}
    end)
  end

  def render(assigns) do
    ~H"""
    <.settings_page
      current_user={@current_user}
      current_org={@current_org}
      current_tab={@settings_tab}
      user_avatar_upload={@uploads.user_avatar}
      organization_avatar_upload={Map.get(@uploads, :organization_avatar)}
    >
      <%= case @settings_tab do %>
        <% :organization -> %>
          <.company_tab
            current_user={@current_user}
            current_org={@current_org}
            company_form={@company_form}
            editing_basic_info={@editing_basic_info}
            ksef_credential={@ksef_credential}
            ksef_auth_method={@ksef_auth_method}
            ksef_auth_status={@ksef_auth_status}
            ksef_failure={@ksef_failure}
            ksef_fetching?={@ksef_fetching?}
            bank_accounts={@bank_accounts}
            bank_institutions={@bank_institutions}
            pending_requisitions={@pending_requisitions}
            organization_users={@organization_users}
            organization_invites={@organization_invites}
            show_active_invites={@show_active_invites}
            selected_user={@selected_user}
            bank_account_statuses={@bank_account_statuses}
            uploads={@uploads}
          />
        <% :invoices -> %>
          <.invoices_tab
            current_org={@current_org}
            current_user={@current_user}
            tax_prognosis?={flag_enabled?(:tax_prognosis, assigns)}
          />
        <% :subscription -> %>
          <.subscription_tab month={@subscription_month} worksheet={@subscription_worksheet} />
        <% :account -> %>
          <.account_tab
            current_user={@current_user}
            owned_organizations={@owned_organizations}
            delete_account_form={@delete_account_form}
            editing_account_name={@editing_account_name}
            member_form={@member_form}
            editing_credentials={@editing_credentials}
            email_form={@email_form}
            google_connected?={@google_connected?}
            password_form={@password_form}
            current_password={@current_password}
          />
        <% :profile -> %>
          <.profile_tab
            current_user={@current_user}
            ash_scope={@ash_scope}
            member_form={@member_form}
            contract_form={@contract_form}
            editing_profile_employment={@editing_profile_employment}
            editing_profile_finance={@editing_profile_finance}
            editing_profile_contact={@editing_profile_contact}
            leave_requests={@leave_requests}
            leave_request_form={@leave_request_form}
            leave_request_upload={@uploads.leave_request_attachment}
            leave_search={@leave_search}
            leave_days={@leave_days}
            projects={@projects}
            projects_total={@projects_total}
            projects_date={@projects_date}
            pending_contract={@pending_contract}
            current_contract={@current_contract}
            signed_contract_upload={@uploads.signed_contract}
            document_upload={Map.get(@uploads, :document_upload)}
            delegations={@delegations}
            feature_flags={@feature_flags}
          />
      <% end %>
    </.settings_page>
    """
  end

  defp derive_statuses(bank_accounts) do
    Map.new(bank_accounts, fn account ->
      requisition_status = account.requisition && account.requisition.status

      status = derive_bank_account_status(account, requisition_status)

      {account.id, status}
    end)
  end

  defp derive_bank_account_status(%{institution_name: "Manual"}, _requisition_status), do: :manual

  defp derive_bank_account_status(account, _requisition_status) when is_nil(account.gocardless_id), do: :disconnected

  defp derive_bank_account_status(account, requisition_status)
       when requisition_status in [:rejected, :expired] or account.broken?, do: :broken

  defp derive_bank_account_status(account, requisition_status)
       when requisition_status == :accepted and not account.has_successful_sync?, do: :processing

  defp derive_bank_account_status(_account, :pending), do: :processing

  defp derive_bank_account_status(account, _requisition_status) when account.has_successful_sync?, do: :connected

  defp derive_bank_account_status(_account, _requisition_status), do: :disconnected

  defp list_bank_accounts(scope) do
    case Finances.list_bank_accounts(
           scope: scope,
           load: [:broken?, :has_successful_sync?, :requisition]
         ) do
      {:ok, accounts} ->
        accounts
        # Keep the latest outcome independent of the last-success aggregate's filter.
        |> Ash.load!(:latest_successful_sync_at, scope: scope)
        |> Enum.sort_by(&bank_account_sort_key/1)

      {:error, _} ->
        []
    end
  end

  defp bank_account_sort_key(account) do
    {account.iban, account.id}
  end

  defp list_pending_requisitions(scope) do
    case Finances.list_requisitions(scope: scope) do
      {:ok, requisitions} -> Enum.filter(requisitions, &(&1.status == :pending))
      {:error, _} -> []
    end
  end

  defp list_bank_institutions(_current_user, []), do: %{}

  defp list_bank_institutions(current_user, bank_accounts) do
    institution_ids =
      bank_accounts
      |> Enum.map(& &1.institution_id)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    if MapSet.size(institution_ids) == 0 do
      %{}
    else
      case Finances.list_institutions("pl", actor: current_user) do
        {:ok, institutions} ->
          institutions
          |> Enum.filter(&MapSet.member?(institution_ids, &1.id))
          |> Map.new(&{&1.id, &1})

        {:error, error} ->
          Logger.warning("Failed to load bank institution metadata",
            error_kind: ErrorKind.classify(error)
          )

          %{}
      end
    end
  end

  defp password_return_path(_settings_tab), do: ~p"/ustawienia/konto"

  defp handle_resolved_section(tab, %{canonical?: canonical?, canonical_path: canonical_path}, socket) do
    cond do
      not Navigation.visible?(tab, %{
        current_user: socket.assigns.current_user,
        current_org: socket.assigns.current_org
      }) ->
        {:noreply, push_patch(socket, to: Navigation.default_path())}

      not canonical? ->
        {:noreply, push_patch(socket, to: canonical_path)}

      true ->
        {:noreply,
         socket
         |> assign(:settings_tab, tab)
         |> assign_subscription_preview_if_visible()}
    end
  end

  defp assign_subscription_preview_if_visible(%{assigns: %{settings_tab: :subscription}} = socket) do
    assign_subscription_preview(socket)
  end

  defp assign_subscription_preview_if_visible(socket), do: socket

  defp assign_subscription_preview(socket) do
    month = Month.current()
    current_org = socket.assigns.current_org
    current_user = socket.assigns.current_user

    worksheet =
      if current_org.owner_id == current_user.id do
        current_org
        |> MonthContext.load(month, current_user, current_month: month)
        |> Map.fetch!(:worksheet)
      end

    socket
    |> assign(:subscription_month, month)
    |> assign(:subscription_worksheet, worksheet)
  end

  defp parse_role(role_param) when is_binary(role_param) do
    case Enum.find(UserRole.roles(), &(UserRole.param(&1) == role_param)) do
      nil -> {:error, :unknown_role}
      role -> {:ok, role}
    end
  end

  defp parse_role(_role_param), do: {:error, :unknown_role}

  defp find_loaded_organization_user(users, user_id) do
    case Enum.find(users, &(to_string(&1.id) == user_id)) do
      nil -> {:error, :unknown_user}
      user -> {:ok, user}
    end
  end

  defp prevent_self_user_management(current_user, user) do
    if current_user.id == user.id do
      {:error, :self_user_management}
    else
      :ok
    end
  end

  defp save_member_form(socket, member_params, section_assign) do
    case AshPhoenix.Form.submit(socket.assigns.member_form, params: member_params) do
      {:ok, member} ->
        {:noreply,
         socket
         |> assign(section_assign, false)
         |> refresh_profile_assigns(%{socket.assigns.current_user | member: member})}

      {:error, form} ->
        {:noreply, assign(socket, :member_form, form)}
    end
  end

  defp refresh_profile_assigns(socket, user) do
    scope = socket.assigns.ash_scope
    current_user = %{user | member: Ash.load!(user.member, [avatar_blob: [:url]], scope: scope)}

    {:ok, pending_contract} = Payroll.load_pending_contract(current_user.member.id, scope: scope)
    {:ok, current_contract} = Payroll.load_current_contract(current_user.member.id, scope: scope)

    socket
    |> assign(:current_user, current_user)
    |> assign(:member_form, form_member_form(current_user.member, scope))
    |> assign(:pending_contract, pending_contract)
    |> assign(:current_contract, current_contract)
    |> assign(:contract_form, form_contract_form(current_contract, scope))
  end

  defp profile_section_assign("employment"), do: :editing_profile_employment
  defp profile_section_assign("finance"), do: :editing_profile_finance
  defp profile_section_assign("contact"), do: :editing_profile_contact

  defp merge_user_name_params(%{"first_name" => first_name, "last_name" => last_name} = params) do
    full_name =
      [String.trim(first_name || ""), String.trim(last_name || "")]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    params
    |> Map.put("name", full_name)
    |> Map.delete("first_name")
    |> Map.delete("last_name")
  end

  defp merge_user_name_params(params), do: params

  defp leave_request_form(current_user, scope) do
    Timetracker.LeaveRequest
    |> AshPhoenix.Form.for_create(:create,
      domain: Timetracker,
      as: "leave_request",
      scope: scope,
      actor: current_user
    )
    |> AshPhoenix.Form.validate(%{"reason" => to_string(default_leave_reason())})
    |> to_form()
  end

  # TODO: Branch on employment contract (UoP leave vs absence reasons).
  defp leave_reasons, do: [:indisposition, :rest, :other]

  defp default_leave_reason, do: List.first(leave_reasons())

  defp load_profile_projects(user_id, scope) do
    date = Date.utc_today()

    projects =
      user_id
      |> Timetracker.projects_duration_for_month(date, scope)
      |> Enum.filter(&(&1.duration > 0))

    total = Enum.reduce(projects, 0, fn project, acc -> acc + project.duration end)

    {projects, total, date}
  end

  defp form_contract_form(nil, _scope), do: nil

  defp form_contract_form(contract, scope),
    do: contract |> AshPhoenix.Form.for_update(:update, domain: Payroll, scope: scope, as: "contract") |> to_form()
end
