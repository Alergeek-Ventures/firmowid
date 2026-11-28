defmodule FirmowidWeb.Settings.Views.Index do
  @moduledoc """
  Settings: the member's account, HR details, documents and business trips, and
  for an admin the company details, KSeF and bank accounts, and for the owner the
  subscription, each on a page of its own.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.Delegations.Components.DelegationsList
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [guard_upload_progress: 2]
  import FirmowidWeb.Settings.Components.AccountTab
  import FirmowidWeb.Settings.Components.CompanyTab

  import FirmowidWeb.Settings.Components.Integrations,
    only: [integrations_index: 1, integration_logo: 1]

  import FirmowidWeb.Settings.Components.McpIntegration
  import FirmowidWeb.Settings.Components.ProfileTab
  import FirmowidWeb.Settings.Components.SettingsPage
  import FirmowidWeb.Settings.Components.SubscriptionTab
  import Phoenix.Component, except: [link: 1]

  alias Ash.Error.Forbidden.Policy
  alias Ash.Error.Invalid
  alias Ash.Notifier.Notification
  alias Firmowid.Billing
  alias Firmowid.Billing.Month
  alias Firmowid.Billing.PlanCatalog
  alias Firmowid.Blobs
  alias Firmowid.Blobs.Blob
  alias Firmowid.Core
  alias Firmowid.Delegations
  alias Firmowid.ErrorKind
  alias Firmowid.Finances
  alias Firmowid.Finances.GoCardless.ApiClient
  alias Firmowid.Finances.Requisition
  alias Firmowid.Ksef.Credential
  alias Firmowid.Payroll
  alias Firmowid.Timetracker
  alias FirmowidUI.Components.Inputs
  alias FirmowidUI.Ksef.Connection
  alias FirmowidUI.Utilities.ForbiddenError
  alias FirmowidWeb.Billing.Utilities.MonthContext
  alias FirmowidWeb.Billing.Utilities.Navigation, as: BillingNavigation
  alias FirmowidWeb.Billing.Utilities.OcrLimit
  alias FirmowidWeb.Billing.Utilities.PlanOffer
  alias FirmowidWeb.Billing.Utilities.Worksheet
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Documents.Components.DocumentsSection
  alias FirmowidWeb.Inbox.Components.SidebarNav
  alias FirmowidWeb.Infrastructure.Components.BlobProcessingToasts
  alias FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents
  alias FirmowidWeb.Settings.Components.ApiKeysSection
  alias FirmowidWeb.Settings.Components.Integrations
  alias FirmowidWeb.Settings.Components.StripeSection
  alias FirmowidWeb.Settings.Utilities.Navigation
  alias Phoenix.Socket.Broadcast

  require Logger

  defp form_basic_info_form(organization, scope) do
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

  defp form_member_form(member, scope) do
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

  defp form_password_form(current_user) do
    current_user
    |> AshPhoenix.Form.for_update(:change_password,
      domain: Core,
      as: "user",
      actor: current_user
    )
    |> to_form()
  end

  defp form_email_form(current_user, scope) do
    current_user
    |> AshPhoenix.Form.for_update(:change_email,
      scope: scope,
      domain: Core,
      as: "user"
    )
    |> to_form()
  end

  def mount(_params, _session, socket) do
    %{current_user: current_user, current_org: current_org, ash_scope: scope} = socket.assigns
    admin? = current_user.member.role == :admin

    subscribe_to_admin_updates(socket, current_org.id, admin?)

    if connected?(socket) do
      Endpoint.subscribe("blob:created:#{current_org.id}")
      Endpoint.subscribe("blob:updated:#{current_org.id}")
      Endpoint.subscribe("blob:destroyed:#{current_org.id}")
      # VatIdCheckWorker checks a saved NIP right away; show its result when it lands.
      Endpoint.subscribe("organization:nip_checked:#{current_org.id}")
    end

    socket =
      if admin? do
        socket
        |> allow_upload(:organization_avatar,
          accept: ~w(.jpg .jpeg .png),
          max_entries: 1,
          auto_upload: true,
          progress: guard_upload_progress(&handle_progress/3, :ash_scope)
        )
        |> allow_upload(:document_upload,
          accept: ~w(.pdf .doc .docx),
          max_entries: 1,
          auto_upload: true,
          progress: guard_upload_progress(&handle_progress/3, :ash_scope)
        )
      else
        socket
      end

    {:ok,
     socket
     |> assign(:editing_account_name, false)
     |> assign(:editing_profile_employment, false)
     |> assign(:editing_profile_finance, false)
     |> assign(:editing_profile_contact, false)
     |> assign(:editing_credentials, false)
     |> assign(:settings_tab, :account)
     |> assign(:subscription_worksheet, nil)
     |> assign(:ocr_documents_row, nil)
     |> assign(:active_subscription, nil)
     |> assign(:plan_granted?, false)
     |> assign(:plan_purchase, nil)
     |> assign(:member_form, form_member_form(current_user.member, scope))
     |> allow_upload(:user_avatar,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       auto_upload: true,
       progress: guard_upload_progress(&handle_progress/3, :ash_scope)
     )
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
     |> assign(:current_org, Ash.load!(current_org, [avatar_blob: [:url]], scope: scope))
     |> assign(:main_class, "bg-white")}
  end

  # A page loads what it shows once, when it first opens.
  defp assign_tab_data(socket, tab) when tab in [:organization, :ksef, :bank_accounts],
    do: load_once(socket, :company_form, &assign_company/1)

  defp assign_tab_data(socket, :account), do: load_once(socket, :email_form, &assign_account/1)

  defp assign_tab_data(socket, tab) when tab in [:profile, :documents, :delegations, :leaves],
    do: load_once(socket, :leave_requests, &assign_profile/1)

  defp assign_tab_data(socket, :subscription), do: socket

  # The catalog shows how many API keys the member sees; it is read again on every visit, so it
  # counts the keys created or revoked on the API subpage.
  defp assign_tab_data(socket, :integrations),
    do: assign(socket, :api_key_count, length(Core.list_api_keys!(scope: socket.assigns.ash_scope)))

  defp load_once(socket, loaded_key, load) do
    if Map.has_key?(socket.assigns, loaded_key), do: socket, else: load.(socket)
  end

  defp assign_company(socket) do
    %{current_org: current_org, ash_scope: scope} = socket.assigns

    socket
    |> assign_bank_accounts()
    |> Connection.init(scope)
    |> assign(:company_form, form_basic_info_form(current_org, scope))
    # The taxes card picks the company's partners from its members.
    |> assign(
      :organization_users,
      Core.list_users!(%{status: :active}, load: [member: [avatar_blob: [:url]]], scope: scope)
    )
  end

  defp assign_account(socket) do
    %{current_user: current_user, ash_scope: scope} = socket.assigns

    {:ok, google_identities} =
      Core.read_user_identity_for_strategy(
        current_user.id,
        "google",
        scope: scope
      )

    socket
    |> assign(:owned_organizations, Core.list_owned_organizations(current_user))
    |> assign(:current_password, nil)
    |> assign(:password_form, form_password_form(current_user))
    |> assign(:email_form, form_email_form(current_user, scope))
    |> assign(:google_connected?, google_identities != [])
  end

  defp assign_delegations(socket) do
    %{current_user: current_user, ash_scope: scope} = socket.assigns

    assign(
      socket,
      :delegations,
      Delegations.list_delegations_for_member!(current_user.member.id,
        scope: scope,
        load: [:order_editable?]
      )
    )
  end

  defp assign_profile(socket) do
    %{current_user: current_user, ash_scope: scope} = socket.assigns
    member_id = current_user.member.id

    leave_days =
      current_user.member
      |> Ash.load!([accepted_leave_days_for_year: %{year: Date.utc_today().year}], scope: scope)
      |> Map.fetch!(:accepted_leave_days_for_year)

    socket
    |> assign(:leave_requests, list_leave_requests(member_id, scope))
    |> assign_delegations()
    |> assign(:leave_days, leave_days || 0)
    |> assign(:leave_search, "")
    |> assign(:leave_request_form, leave_request_form(current_user, scope))
    |> assign_contracts()
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

  def handle_params(%{"integration" => slug}, _uri, socket) do
    role = socket.assigns.current_user.member.role

    with {:ok, integration} <- Navigation.resolve_integration(slug),
         true <- integration in Navigation.integrations(role) do
      # Every member sees the integrations page, so the section always opens here.
      {:noreply, socket} =
        handle_resolved_section(
          :integrations,
          %{canonical?: true, canonical_path: Navigation.integration_path(integration)},
          socket
        )

      {:noreply,
       socket
       |> assign(:integration, integration)
       |> assign(:page_title, Navigation.integration_title(integration))}
    else
      _unknown_or_not_allowed ->
        {:noreply, push_patch(socket, to: Navigation.canonical_path(:integrations))}
    end
  end

  def handle_params(%{"section" => section}, _uri, socket) do
    case Navigation.resolve_section(section) do
      {:ok, %{id: tab} = resolved} ->
        handle_resolved_section(tab, resolved, socket)

      :error ->
        {:noreply, push_patch(socket, to: Navigation.default_path())}
    end
  end

  defp handle_avatar_upload(:user_avatar, blob_id, socket) do
    current_user = socket.assigns.current_user

    case Core.update_member_avatar(current_user.member, %{avatar_blob_id: blob_id}, scope: socket.assigns.ash_scope) do
      {:ok, updated} ->
        updated_with_avatar =
          Ash.load!(updated, [avatar_blob: [:url]], scope: socket.assigns.ash_scope)

        LiveToast.send_toast(:info, gettext("The picture has been updated."))

        {:noreply, assign(socket, :current_user, %{current_user | member: updated_with_avatar})}

      {:error, %Invalid{}} ->
        document_not_picture(socket)
    end
  end

  defp handle_avatar_upload(:organization_avatar, blob_id, socket) do
    current_org = socket.assigns.current_org

    case Core.update_organization_avatar(current_org, %{avatar_blob_id: blob_id}, scope: socket.assigns.ash_scope) do
      {:ok, updated} ->
        updated_with_avatar =
          Ash.load!(updated, [avatar_blob: [:url]], scope: socket.assigns.ash_scope)

        LiveToast.send_toast(:info, gettext("The picture has been updated."))

        {:noreply,
         socket
         |> assign(:current_org, updated_with_avatar)
         |> assign_subscription_preview_if_visible()}

      {:error, %Invalid{}} ->
        document_not_picture(socket)
    end
  end

  # Uploads reuse a stored file with the same contents, so a picture identical
  # to a document comes back as that document, which cannot become an avatar.
  defp document_not_picture(socket) do
    LiveToast.send_toast(
      :error,
      gettext("This file is already saved as a document. Choose another picture.")
    )

    {:noreply, socket}
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
        LiveToast.send_toast(:success, gettext("The file has been sent."))

      {:error, err} ->
        if Blobs.ocr_limit_error?(err) do
          OcrLimit.toast_refusal(err, entry.client_name)
        else
          Logger.warning("Employment contract upload failed", error_kind: ErrorKind.classify(err))
          LiveToast.send_toast(:error, gettext("An error occurred while sending the file."))
        end
    end

    {:noreply, socket}
  end

  defp handle_progress(name, %{done?: false}, socket) when name in [:organization_avatar, :user_avatar] do
    {:noreply, socket}
  end

  defp handle_progress(name, entry, socket) when name in [:organization_avatar, :user_avatar] do
    if name == :organization_avatar do
      if socket.assigns.current_user.member.role != :admin do
        raise ForbiddenError, gettext("Only an administrator can change the organization logo.")
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
        LiveToast.send_toast(:error, gettext("An error occurred while updating the picture."))
        {:noreply, socket}
    end
  end

  def handle_event("delete_account", _params, socket) do
    case Core.destroy_user(socket.assigns.current_user, scope: socket.assigns.ash_scope) do
      :ok ->
        {:noreply, redirect(socket, to: ~p"/")}

      # The sign-in grew stale while the page was open: reloading it shows the way to
      # sign in again (see the User destroy policy).
      {:error, %Policy{}} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Log in again to close your account."))
         |> push_navigate(to: Navigation.canonical_path(:account))}

      {:error, error} ->
        LiveToast.send_toast(:error, gettext("An error occurred while deleting the account"))

        Logger.error("Failed to delete user account",
          error_kind: ErrorKind.classify(error)
        )

        {:noreply, socket}
    end
  end

  def handle_event("purchase-period", %{"value" => period}, socket) do
    billing_period = Enum.find(PlanCatalog.billing_periods(), &(Atom.to_string(&1) == period))

    {:noreply, update(socket, :plan_purchase, &%{&1 | billing_period: billing_period})}
  end

  # Stripe Checkout takes the card; the plan turns on when Stripe reports the subscription.
  def handle_event("purchase", %{"plan" => plan}, socket) do
    plan = Enum.find(PlanCatalog.paid_plans(), &(Atom.to_string(&1) == plan))

    case Billing.start_subscription(
           Map.merge(
             %{plan: plan, billing_period: socket.assigns.plan_purchase.billing_period},
             BillingNavigation.checkout_return_urls(Navigation.canonical_path(:subscription))
           ),
           scope: socket.assigns.ash_scope
         ) do
      {:ok, url} ->
        {:noreply, redirect(socket, external: url)}

      # A purchase refused with a reason the owner can act on, such as a plan bought meanwhile.
      {:error, %Invalid{errors: [%{message: message} = error | _rest]}} ->
        LiveToast.send_toast(:error, Inputs.translate_error({message, Map.get(error, :vars, [])}))
        {:noreply, assign_subscription_preview(socket)}

      {:error, error} ->
        raise error
    end
  end

  # Card, plan and cancellation are managed in Stripe's customer portal.
  def handle_event("manage-payments", _params, socket) do
    url =
      Billing.open_subscription_portal!(
        %{return_url: BillingNavigation.portal_return_url()},
        scope: socket.assigns.ash_scope
      )

    {:noreply, redirect(socket, external: url)}
  end

  def handle_event("upload", _, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_delegation", %{"id" => id}, socket) do
    case Delegations.cancel_delegation(id, scope: socket.assigns.ash_scope) do
      {:ok, _delegation} ->
        LiveToast.send_toast(:info, gettext("The business trip has been cancelled."))
        {:noreply, assign_delegations(socket)}

      {:error, _error} ->
        LiveToast.send_toast(:error, gettext("Could not cancel the business trip."))
        {:noreply, assign_delegations(socket)}
    end
  end

  def handle_event("delete_delegation", %{"id" => id}, socket) do
    case Delegations.destroy_delegation(id, scope: socket.assigns.ash_scope) do
      :ok ->
        LiveToast.send_toast(:info, gettext("The business trip has been deleted."))
        {:noreply, assign_delegations(socket)}

      {:error, _error} ->
        LiveToast.send_toast(:error, gettext("Could not delete the business trip."))
        {:noreply, assign_delegations(socket)}
    end
  end

  def handle_event("delete_bank_account", %{"account_id" => account_id}, socket) do
    scope = socket.assigns.ash_scope
    bank_account = Finances.get_bank_account!(account_id, scope: scope)

    case Finances.destroy_bank_account(bank_account, scope: scope) do
      :ok ->
        LiveToast.send_toast(:info, gettext("The bank account has been deleted."))

        {:noreply, assign_bank_accounts(socket)}

      {:error, _} ->
        LiveToast.send_toast(
          :error,
          gettext("An error occurred while deleting the bank account.")
        )

        {:noreply, socket}
    end
  end

  def handle_event("make_default_account", %{"account_id" => account_id}, socket) do
    scope = socket.assigns.ash_scope

    bank_account = Finances.get_bank_account!(account_id, scope: scope)

    case Finances.update_bank_account(bank_account, %{is_default: true}, scope: scope) do
      {:ok, _} ->
        {:noreply, assign_bank_accounts(socket)}

      {:error, _} ->
        LiveToast.send_toast(
          :error,
          gettext("An error occurred while setting the bank account as the default.")
        )

        {:noreply, socket}
    end
  end

  def handle_event("save", %{"organization" => org_params}, socket) do
    current_user = socket.assigns.current_user
    scope = socket.assigns.ash_scope

    if current_user.member.role != :admin do
      raise ForbiddenError, gettext("Only an administrator can update the organization.")
    end

    case AshPhoenix.Form.submit(socket.assigns.company_form, params: org_params, scope: scope) do
      {:ok, updated_org} ->
        # Read anew: the form holds the organization as it was at mount, which keeps
        # stale the register check that arrived meanwhile.
        updated_with_avatar =
          Core.get_organization!(updated_org.id, scope: scope, load: [avatar_blob: [:url]])

        # The details are edited in place, so nothing else confirms the save. The sidebar
        # counts a contradiction with the registers, which the VAT payer setting decides.
        LiveToast.send_toast(:success, gettext("Changes saved"))
        send_update(SidebarNav, id: SidebarNav.id(), refresh: true)

        {:noreply,
         socket
         |> assign(:company_form, form_basic_info_form(updated_with_avatar, scope))
         |> assign(:current_org, updated_with_avatar)
         |> assign_subscription_preview_if_visible()}

      {:error, form} ->
        {:noreply, assign(socket, :company_form, form)}
    end
  end

  # The taxes card saves the legal form at once, since its other rows depend on it.
  def handle_event("set_legal_form", %{"legal_form" => legal_form}, socket) do
    %{current_org: organization, ash_scope: scope} = socket.assigns

    case Core.update_organization(organization, %{legal_form: legal_form}, scope: scope) do
      {:ok, updated} ->
        send_update(SidebarNav, id: SidebarNav.id(), refresh: true)
        {:noreply, assign(socket, :current_org, %{organization | legal_form: updated.legal_form})}

      {:error, _error} ->
        LiveToast.send_toast(
          :error,
          gettext("Could not save the changes. Refresh the page and try again.")
        )

        {:noreply, socket}
    end
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    save_member_form(socket, merge_user_name_params(user_params), :editing_account_name)
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
    current_user = socket.assigns.current_user

    # Only an account without a password is refused, when its sign-in is not recent
    # (see the User `:change_email` policy).
    if Ash.can?({current_user, :change_email}, current_user) do
      change_email(socket, user_params)
    else
      LiveToast.send_toast(:error, gettext("Log in again to change your email address."))
      {:noreply, socket}
    end
  end

  def handle_event("rename_bank_account", %{"account_id" => account_id, "name" => name}, socket) do
    scope = socket.assigns.ash_scope
    bank_account = Finances.get_bank_account!(account_id, scope: scope)

    # Enter in the card's name field sends the change on blur and then the submit;
    # the second one finds the name already saved.
    if bank_account.name == name do
      {:noreply, socket}
    else
      rename_bank_account(bank_account, name, scope, socket)
    end
  end

  def handle_event("reconnect_bank_account", %{"account_id" => account_id}, socket) do
    scope = socket.assigns.ash_scope
    bank_account = Finances.get_bank_account!(account_id, scope: scope)

    # Without a known bank there is nothing to reconnect, so the bank connection starts anew.
    if is_nil(bank_account.institution_id) do
      {:noreply, push_navigate(socket, to: ~p"/ustawienia/bank/dodaj")}
    else
      # The institution's transaction horizon, as the bank connection screen uses it.
      transaction_days =
        case ApiClient.get_institution(bank_account.institution_id) do
          {:ok, %{"transaction_total_days" => days}} when is_integer(days) -> days
          _ -> 90
        end

      case Finances.create_requisition(
             bank_account.institution_id,
             transaction_days,
             Endpoint.url() <> ~p"/ustawienia/bank/dodaj",
             scope: scope
           ) do
        {:ok, link} ->
          {:noreply, redirect(socket, external: link)}

        {:error, _} ->
          LiveToast.send_toast(:error, gettext("Could not start reconnecting."))
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
        LiveToast.send_toast(:info, gettext("The account has been added."))

        {:noreply, assign_bank_accounts(socket)}

      {:error, _} ->
        LiveToast.send_toast(:error, gettext("Could not add the account."))
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
         |> put_flash(:info, gettext("The password has been changed successfully."))
         |> push_navigate(to: Navigation.canonical_path(:account))}

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
        LiveToast.send_toast(:error, gettext("Could not change the Google account."))
        {:noreply, socket}
    end
  end

  def handle_event("unlink_google_account", _params, socket) do
    user = socket.assigns.current_user

    case Core.unlink_google_account(user, scope: socket.assigns.ash_scope) do
      {:ok, updated_user} ->
        LiveToast.send_toast(:info, gettext("The Google account has been disconnected."))
        {:noreply, assign(socket, :current_user, updated_user)}

      {:error, error} ->
        message =
          case error do
            %{errors: [%{message: msg, vars: vars}]} -> translate_error({msg, vars})
            _ -> gettext("An error occurred while disconnecting the Google account.")
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
        {:noreply,
         socket
         |> assign(
           :leave_requests,
           list_leave_requests(socket.assigns.current_user.member.id, scope)
         )
         |> assign(:leave_request_form, leave_request_form(socket.assigns.current_user, scope))
         |> PosthogBusinessEvents.capture(:leave_request_created)
         |> push_event("js-exec", %{to: "#leave-request-modal", attr: "data-cancel"})}

      {:error, %Invalid{} = error} ->
        form =
          socket.assigns.leave_request_form.source
          |> AshPhoenix.Form.validate(params)
          |> AshPhoenix.Form.add_error(error)

        {:noreply, assign(socket, :leave_request_form, to_form(form))}

      {:error, _reason} ->
        LiveToast.send_toast(:error, gettext("Could not submit the request."))
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
            LiveToast.send_toast(:success, gettext("The contract has been signed successfully."))

            current_user =
              Core.get_user!(socket.assigns.current_user.id,
                scope: scope,
                load: [:member],
                actor: socket.assigns.current_user
              )

            {:noreply, refresh_profile_assigns(socket, current_user)}

          {:error, _error} ->
            LiveToast.send_toast(:error, gettext("Could not upload the contract. Try again."))
            {:noreply, socket}
        end

      {_, [_ | _]} ->
        LiveToast.send_toast(:error, gettext("The file is still being uploaded."), title: gettext("Upload error"))

        {:noreply, socket}

      {[], []} ->
        LiveToast.send_toast(:error, gettext("Choose a file to upload."), title: gettext("No file"))

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

  defp rename_bank_account(bank_account, name, scope, socket) do
    case Finances.update_bank_account(bank_account, %{name: name}, scope: scope) do
      {:ok, _} ->
        LiveToast.send_toast(:info, gettext("The account name has been changed."))

        {:noreply,
         socket
         |> assign_bank_accounts()
         |> push_event("js-exec", %{
           to: "#manual_bank_account_modal_company",
           attr: "data-cancel"
         })}

      {:error, _} ->
        LiveToast.send_toast(
          :error,
          gettext("An error occurred while changing the account name.")
        )

        {:noreply, socket}
    end
  end

  def handle_info(%Broadcast{topic: "organization:nip_checked:" <> _, payload: %Notification{data: checked}}, socket) do
    current_org = %{
      socket.assigns.current_org
      | nip_status: checked.nip_status,
        nip_checked_at: checked.nip_checked_at,
        nip_registers: checked.nip_registers
    }

    # The inbox sidebar counts a contradiction with the registers.
    send_update(SidebarNav, id: SidebarNav.id(), refresh: true)

    {:noreply, assign(socket, :current_org, current_org)}
  end

  def handle_info(%Broadcast{topic: "credential:" <> _, payload: %Notification{resource: Credential}} = message, socket) do
    Connection.handle_info(message, socket, socket.assigns.ash_scope)
  end

  # Handle Ash native PubSub broadcasts for requisition status changes
  def handle_info(
        %Broadcast{topic: "requisition:" <> _, payload: %Notification{resource: Requisition, action: %{name: action}}},
        socket
      ) do
    {toast_type, message} =
      case action do
        :accept ->
          {:success, gettext("The bank account has been connected successfully!")}

        :reject ->
          {:error, gettext("The bank connection was rejected. Try again.")}

        _ ->
          {:info, gettext("The bank connection status has been updated.")}
      end

    LiveToast.send_toast(toast_type, message)

    {:noreply, assign_bank_accounts(socket)}
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
    LiveToast.send_toast(:error, notification.data.original_filename, title: gettext("Could not upload the file"))

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
      gettext(
        "File %{filename} does not contain the required data. Make sure you are uploading a contract.",
        filename: notification.data.original_filename
      ),
      title: gettext("Invalid document")
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
      title={@page_title}
      back={
        @settings_tab == :integrations && @integration && Navigation.canonical_path(:integrations)
      }
      description={
        @settings_tab == :integrations && @integration && Integrations.description(@integration)
      }
    >
      <:icon :if={@settings_tab == :integrations && @integration}>
        <.integration_logo integration={@integration} />
      </:icon>
      <:actions :if={@settings_tab == :delegations}>
        <.plan_business_trip_link current_org={@current_org} />
      </:actions>
      <.settings_avatar
        :if={@settings_tab == :organization}
        upload={@uploads.organization_avatar}
        name={@current_org.display_name}
        blob={@current_org.avatar_blob}
        label={gettext("Change organization logo")}
        class="rounded-md bg-white p-5"
      />
      <.settings_avatar
        :if={@settings_tab == :account}
        upload={@uploads.user_avatar}
        name={@current_user.member.name || @current_user.email}
        blob={@current_user.member.avatar_blob}
        label={gettext("Change profile picture")}
      />
      <%= case @settings_tab do %>
        <% section when section in [:organization, :ksef, :bank_accounts] -> %>
          <.company_tab
            section={@settings_tab}
            company_form={@company_form}
            ksef_credential={@ksef_credential}
            ksef_auth_method={@ksef_auth_method}
            ksef_auth_status={@ksef_auth_status}
            ksef_failure={@ksef_failure}
            ksef_fetching?={@ksef_fetching?}
            bank_accounts={@bank_accounts}
            bank_institutions={@bank_institutions}
            pending_requisitions={@pending_requisitions}
            uploads={@uploads}
            current_org={@current_org}
            organization_users={@organization_users}
            scope={@ash_scope}
          />
        <% :subscription -> %>
          <.subscription_tab
            worksheet={@subscription_worksheet}
            ocr_documents_row={@ocr_documents_row}
            subscription={@active_subscription}
            plan_granted?={@plan_granted?}
            purchase={@plan_purchase}
          />
        <% :integrations -> %>
          <.integrations_index
            :if={is_nil(@integration)}
            integrations={Navigation.integrations(@current_user.member.role)}
            api_key_count={@api_key_count}
          />
          <.mcp_integration
            :if={@integration == :mcp}
            mcp_url={FirmowidWeb.Core.Endpoint.url() <> "/mcp"}
          />
          <.live_component
            :if={@integration == :api}
            module={ApiKeysSection}
            id="api-keys-section"
            scope={@ash_scope}
          />
          <.live_component
            :if={@integration == :stripe}
            module={StripeSection}
            id="stripe-section"
            scope={@ash_scope}
          />
        <% :account -> %>
          <.account_tab
            current_user={@current_user}
            owned_organizations={@owned_organizations}
            editing_account_name={@editing_account_name}
            member_form={@member_form}
            editing_credentials={@editing_credentials}
            email_form={@email_form}
            google_connected?={@google_connected?}
            password_form={@password_form}
            current_password={@current_password}
          />
        <% :delegations -> %>
          <.delegations_list delegations={@delegations} />
        <% :leaves -> %>
          <.leave_section
            current_org={@current_org}
            leave_requests={@leave_requests}
            leave_request_form={@leave_request_form}
            leave_request_upload={@uploads.leave_request_attachment}
            leave_search={@leave_search}
            leave_days={@leave_days}
          />
        <% :documents -> %>
          <.live_component
            module={DocumentsSection}
            id="profile-documents"
            current_org={@current_org}
            user={@current_user}
            scope={@ash_scope}
            feature_flags={@feature_flags}
            variant={:profile}
            current_contract_id={@current_contract && @current_contract.id}
          />
        <% :profile -> %>
          <.profile_tab
            current_user={@current_user}
            current_org={@current_org}
            ash_scope={@ash_scope}
            member_form={@member_form}
            contract_form={@contract_form}
            editing_profile_employment={@editing_profile_employment}
            editing_profile_finance={@editing_profile_finance}
            editing_profile_contact={@editing_profile_contact}
            pending_contract={@pending_contract}
            current_contract={@current_contract}
            signed_contract_upload={@uploads.signed_contract}
            document_upload={Map.get(@uploads, :document_upload)}
          />
      <% end %>
    </.settings_page>
    """
  end

  # Every change to the bank accounts refreshes the list, the banks behind it, the
  # connection being set up and the usage the subscription tab shows.
  defp assign_bank_accounts(socket) do
    scope = socket.assigns.ash_scope
    bank_accounts = list_bank_accounts(scope)

    socket
    |> assign(:bank_accounts, bank_accounts)
    |> assign(
      :bank_institutions,
      list_bank_institutions(socket.assigns.current_user, bank_accounts)
    )
    |> assign(
      :pending_requisitions,
      Finances.list_requisitions!(%{status: :pending}, scope: scope)
    )
    |> assign_subscription_preview_if_visible()
  end

  defp list_bank_accounts(scope) do
    accounts =
      Finances.list_bank_accounts!(
        scope: scope,
        load: [:sync_stopped?, :has_successful_sync?, :requisition]
      )

    accounts
    # Keep the latest outcome independent of the last-success aggregate's filter.
    |> Ash.load!(:latest_successful_sync_at, scope: scope)
    |> Enum.sort_by(&{&1.iban, &1.id})
  end

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

  defp handle_resolved_section(tab, %{canonical?: canonical?, canonical_path: canonical_path}, socket) do
    cond do
      not Navigation.visible?(tab, %{
        current_user: socket.assigns.current_user,
        current_org: socket.assigns.current_org
      }) ->
        {:noreply, push_patch(socket, to: Navigation.default_path())}

      tab == :delegations and not flag_enabled?(:delegations, socket.assigns) ->
        {:noreply, push_patch(socket, to: Navigation.default_path())}

      # Roles and invitations are managed on the team page.
      tab == :roles ->
        {:noreply, push_navigate(socket, to: canonical_path)}

      not canonical? ->
        {:noreply, push_patch(socket, to: canonical_path)}

      true ->
        {:noreply,
         socket
         |> assign_tab_data(tab)
         |> assign(:settings_tab, tab)
         |> assign(:integration, nil)
         |> assign(:main_class, main_class(tab))
         |> assign(:page_title, Navigation.page_title(tab))
         |> assign_subscription_preview_if_visible()}
    end
  end

  # The company pages show white cards on the grey background of the company layer.
  defp main_class(tab) when tab in [:organization, :ksef, :bank_accounts], do: nil
  defp main_class(_tab), do: "bg-white"

  defp assign_subscription_preview_if_visible(%{assigns: %{settings_tab: :subscription}} = socket) do
    assign_subscription_preview(socket)
  end

  defp assign_subscription_preview_if_visible(socket), do: socket

  defp assign_subscription_preview(socket) do
    month = Month.current()
    current_org = socket.assigns.current_org
    current_user = socket.assigns.current_user

    if current_org.owner_id == current_user.id do
      scope = socket.assigns.ash_scope

      worksheet =
        current_org
        |> MonthContext.load(month, current_user, current_month: month)
        |> Map.fetch!(:worksheet)

      %{plan_granted?: plan_granted?} = Ash.load!(current_org, :plan_granted?, scope: scope)

      # Read from Stripe when the owner opens the tab, so it shows what Stripe reports now.
      subscription = Billing.get_subscription_details!(scope: scope)

      socket
      |> assign(:subscription_worksheet, worksheet)
      |> assign(
        :ocr_documents_row,
        Worksheet.ocr_documents_row(OcrLimit.usage(scope, current_org))
      )
      |> assign(:active_subscription, subscription)
      |> assign(:plan_granted?, plan_granted?)
      |> assign(
        :plan_purchase,
        plan_purchase(current_org, subscription, plan_granted?, scope)
      )
    else
      assign(socket, :subscription_worksheet, nil)
    end
  end

  # A company that neither pays nor was granted a plan can buy one, except the one that sells
  # Firmowid.
  defp plan_purchase(organization, nil = _subscription, false = _plan_granted?, scope) do
    if organization.id != Billing.seller_organization_id() do
      %{
        billing_period: :monthly,
        free_trial?: Billing.subscription_trial_available?(scope: scope),
        quotas: PlanOffer.quotas()
      }
    end
  end

  defp plan_purchase(_organization, _subscription, _plan_granted?, _scope), do: nil

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

    socket
    |> assign(:current_user, current_user)
    |> assign(:member_form, form_member_form(current_user.member, scope))
    |> assign_contracts()
  end

  defp assign_contracts(socket) do
    scope = socket.assigns.ash_scope
    member_id = socket.assigns.current_user.member.id

    {:ok, pending_contract} = Payroll.load_pending_contract(member_id, scope: scope)
    {:ok, current_contract} = Payroll.load_current_contract(member_id, scope: scope)

    socket
    |> assign(:pending_contract, pending_contract)
    |> assign(:current_contract, current_contract)
    |> assign(:contract_form, form_contract_form(current_contract, scope))
  end

  defp list_leave_requests(member_id, scope) do
    Timetracker.list_leave_requests!(%{member_id: member_id},
      scope: scope,
      query: [sort: [inserted_at: :desc]]
    )
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

  defp default_leave_reason, do: :rest

  defp form_contract_form(nil, _scope), do: nil

  defp form_contract_form(contract, scope),
    do: contract |> AshPhoenix.Form.for_update(:update, domain: Payroll, scope: scope, as: "contract") |> to_form()

  defp change_email(socket, user_params) do
    case AshPhoenix.Form.submit(socket.assigns.email_form, params: user_params) do
      {:ok, user} ->
        LiveToast.send_toast(
          :info,
          gettext("We have sent a confirmation link to the new email address.")
        )

        {:noreply,
         socket
         |> assign(:editing_credentials, false)
         |> assign(:current_user, user)
         |> assign(:current_password, nil)
         |> assign(:password_form, form_password_form(user))
         |> assign(:email_form, form_email_form(user, socket.assigns.ash_scope))}

      {:error, form} ->
        LiveToast.send_toast(:error, gettext("Could not send the email. Try again."))
        {:noreply, assign(socket, :email_form, form)}
    end
  end
end
