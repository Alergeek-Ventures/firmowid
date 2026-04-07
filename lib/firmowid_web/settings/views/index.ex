defmodule FirmowidWeb.Settings.Views.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.Settings.Components.EditButton

  alias Ash.Error.Forbidden
  alias Ash.Notifier.Notification
  alias Firmowid.Analytics
  alias Firmowid.Ash.Blobs
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.Argon2Provider
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.GoCardless.ApiClient
  alias Firmowid.Ash.Finances.Requisition
  alias Firmowid.Ash.Ksef
  alias FirmowidWeb.Core.Endpoint
  alias Phoenix.Socket.Broadcast

  def form_basic_info_form(organization) do
    organization
    |> AshPhoenix.Form.for_update(:update_basic_info,
      domain: Core,
      as: "organization"
    )
    |> to_form()
  end

  def form_correspondence_form(organization) do
    organization
    |> AshPhoenix.Form.for_update(:update_correspondence,
      domain: Core,
      as: "organization"
    )
    |> to_form()
  end

  def form_user_form(user) do
    user
    |> AshPhoenix.Form.for_update(:update_profile,
      domain: Core,
      as: "user"
    )
    |> to_form()
  end

  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user
    current_org = socket.assigns.current_org

    # Use Ash native code interface for listing bank accounts
    bank_accounts =
      if current_user.role == :admin do
        scope = socket.assigns.ash_scope

        case Finances.list_bank_accounts(scope: scope, load: [:broken?, :has_successful_sync?, :requisition]) do
          {:ok, accounts} -> accounts
          {:error, _} -> []
        end
      else
        []
      end

    # Subscribe to requisition updates for real-time bank account sync
    if connected?(socket) and current_user.role == :admin do
      Endpoint.subscribe("requisition:linked:#{current_org.id}")
      Endpoint.subscribe("requisition:rejected:#{current_org.id}")
      Endpoint.subscribe("requisition:error:#{current_org.id}")
    end

    socket =
      if current_user.role == :admin do
        socket
        |> assign(:company_form, form_basic_info_form(current_org))
        |> assign(:correspondence_form, form_correspondence_form(current_org))
        |> assign(:ksef_credential, Ksef.get_credential(socket.assigns.ash_scope))
        |> allow_upload(:organization_avatar,
          accept: ~w(.jpg .jpeg .png),
          max_entries: 1,
          auto_upload: true,
          progress: &handle_progress/3
        )
      else
        socket
      end

    socket = assign(socket, :user_form, form_user_form(current_user))

    # Security section forms - use AshPhoenix.Form with ash_auth actions
    email_form =
      current_user
      |> AshPhoenix.Form.for_update(:update_profile,
        domain: Core,
        as: "user"
      )
      |> to_form()

    password_form =
      current_user
      |> AshPhoenix.Form.for_update(:change_password,
        domain: Core,
        as: "user",
        actor: current_user
      )
      |> to_form()

    # Load avatars using Ash.load!
    org_with_avatar =
      Ash.load!(current_org, [avatar_blob: [:url]],
        tenant: current_org.id,
        authorize?: false,
        actor: %{}
      )

    {:ok,
     socket
     |> assign(:editing_basic_info, false)
     |> assign(:editing_correspondence, false)
     |> assign(:editing_personal_info, false)
     |> assign(:delete_account_form, to_form(%{"current_password" => ""}, as: "user"))
     |> assign(:current_password, nil)
     |> assign(:email_form_current_password, nil)
     |> assign(:current_email, current_user.email)
     |> assign(:email_form, email_form)
     |> assign(:password_form, password_form)
     |> assign(:bank_accounts, bank_accounts)
     |> assign(:bank_account_statuses, derive_statuses(bank_accounts))
     |> assign(:uploaded_files, [])
     |> allow_upload(:user_avatar,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       auto_upload: true,
       progress: &handle_progress/3
     )
     |> assign(:current_org, org_with_avatar)
     |> assign(:main_class, "bg-white")}
  end

  def handle_params(%{"token" => token}, _uri, %{assigns: %{live_action: :confirm_email}} = socket) do
    # Handle email change confirmation using ash_auth confirmation add-on
    strategy = AshAuthentication.Info.strategy!(Core.User, :confirm_email_update)

    socket =
      case AshAuthentication.Strategy.action(strategy, :confirm, %{"confirm" => token}) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email został zmieniony pomyślnie.")

        {:error, _error} ->
          put_flash(socket, :error, "Link do zmiany emaila jest nieprawidłowy lub wygasł.")
      end

    {:noreply, push_navigate(socket, to: ~p"/ustawienia/bezpieczenstwo")}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_avatar_upload(:user_avatar, blob_id, socket) do
    current_user = socket.assigns.current_user

    {:ok, updated} =
      Core.update_user_avatar(current_user, %{avatar_blob_id: blob_id},
        authorize?: false,
        actor: %{}
      )

    # Load avatar using Ash.load!
    updated_with_avatar =
      Ash.load!(updated, [avatar_blob: [:url]],
        tenant: updated.organization_id,
        authorize?: false,
        actor: %{}
      )

    LiveToast.send_toast(:info, "Zdjęcie zostało zaktualizowane.")

    {:noreply, assign(socket, :current_user, updated_with_avatar)}
  end

  def handle_avatar_upload(:organization_avatar, blob_id, socket) do
    current_org = socket.assigns.current_org

    {:ok, updated} =
      Core.update_organization_avatar(current_org, %{avatar_blob_id: blob_id},
        authorize?: false,
        actor: %{}
      )

    # Load avatar using Ash.load!
    updated_with_avatar =
      Ash.load!(updated, [avatar_blob: [:url]],
        tenant: updated.id,
        authorize?: false,
        actor: %{}
      )

    LiveToast.send_toast(:info, "Zdjęcie zostało zaktualizowane.")

    {:noreply, assign(socket, :current_org, updated_with_avatar)}
  end

  defp handle_progress(name, %{done?: false}, socket) when name in [:organization_avatar, :user_avatar] do
    {:noreply, socket}
  end

  defp handle_progress(name, entry, socket) when name in [:organization_avatar, :user_avatar] do
    if name == :organization_avatar do
      if socket.assigns.current_user.role != :admin do
        raise Forbidden, message: "Tylko administrator może zmienić logo organizacji."
      end
    end

    scope = socket.assigns.ash_scope

    case consume_uploaded_entry(socket, entry, fn %{path: path} ->
           Blobs.create_blob(path, entry.client_type, entry.client_name, scope: scope)
         end) do
      {:ok, blob} ->
        handle_avatar_upload(name, blob.id, socket)

      {:error, _err} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas aktualizacji zdjęcia.")
        {:noreply, socket}
    end
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_account", %{"user" => params}, socket) do
    user = socket.assigns.current_user
    password = params["current_password"]

    # Verify password at callsite before destroying user
    if Argon2Provider.valid?(password, user.hashed_password) do
      case Core.destroy_user(user, authorize?: false, actor: %{}) do
        :ok ->
          LiveToast.send_toast(:info, "Konto zostało usunięte.")
          {:noreply, redirect(socket, to: ~p"/")}

        {:error, error} ->
          LiveToast.send_toast(:error, "Wystąpił błąd podczas usuwania konta")

          exception = RuntimeError.exception("Failed to delete user account: #{inspect(error)}")
          {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
          ErrorTracker.report(exception, stacktrace)

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

  def handle_event("update_marketing_consent", params, socket) do
    consent =
      case params do
        %{"value" => _} ->
          true

        _ ->
          false
      end

    case Core.update_profile(socket.assigns.current_user, %{marketing_consent: consent},
           authorize?: false,
           actor: %{}
         ) do
      {:ok, user} ->
        {:noreply, assign(socket, :current_user, user)}

      {:error, _error} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_bank_account", %{"account_id" => account_id}, socket) do
    scope = socket.assigns.ash_scope
    bank_account = Finances.get_bank_account!(account_id, scope: scope)

    case Finances.destroy_bank_account(bank_account, scope: scope) do
      :ok ->
        LiveToast.send_toast(:info, "Konto bankowe zostało usunięte.")

        bank_accounts =
          case Finances.list_bank_accounts(scope: scope, load: [:broken?, :has_successful_sync?, :requisition]) do
            {:ok, accounts} -> accounts
            {:error, _} -> []
          end

        {:noreply,
         socket
         |> assign(:bank_accounts, bank_accounts)
         |> assign(:bank_account_statuses, derive_statuses(bank_accounts))}

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
        bank_accounts =
          case Finances.list_bank_accounts(scope: scope, load: [:broken?, :has_successful_sync?, :requisition]) do
            {:ok, accounts} -> accounts
            {:error, _} -> []
          end

        {:noreply,
         socket
         |> assign(:bank_accounts, bank_accounts)
         |> assign(:bank_account_statuses, derive_statuses(bank_accounts))}

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
    _current_org = socket.assigns.current_org

    if current_user.role != :admin do
      raise Forbidden, message: "Tylko administrator może aktualizować organizację."
    end

    # Determine which form to submit based on which fields are present
    {form_key, _action} =
      cond do
        Map.has_key?(org_params, "correspondence_name") ->
          {:correspondence_form, :update_correspondence}

        Map.has_key?(org_params, "name") or Map.has_key?(org_params, "nip") ->
          {:company_form, :update_basic_info}

        true ->
          {:company_form, :update_organization}
      end

    form = socket.assigns[form_key]

    case AshPhoenix.Form.submit(form, params: org_params) do
      {:ok, updated_org} ->
        # Load avatar using Ash.load!
        updated_with_avatar =
          Ash.load!(updated_org, [avatar_blob: [:url]],
            tenant: updated_org.id,
            authorize?: false,
            actor: %{}
          )

        {:noreply,
         socket
         |> assign(:editing_basic_info, false)
         |> assign(:editing_correspondence, false)
         |> assign(:correspondence_form, form_correspondence_form(updated_with_avatar))
         |> assign(:company_form, form_basic_info_form(updated_with_avatar))
         |> assign(:current_org, updated_with_avatar)}

      {:error, form} ->
        {:noreply, assign(socket, form_key, form)}
    end
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    form = socket.assigns.user_form

    case AshPhoenix.Form.submit(form, params: user_params) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:editing_personal_info, false)
         |> assign(:current_user, updated_user)
         |> assign(:user_form, form_user_form(updated_user))}

      {:error, form} ->
        {:noreply, assign(socket, :user_form, form)}
    end
  end

  def handle_event("rename_bank_account", %{"account_id" => account_id, "name" => name}, socket) do
    scope = socket.assigns.ash_scope
    bank_account = Finances.get_bank_account!(account_id, scope: scope)

    case Finances.update_bank_account(bank_account, %{name: name}, scope: scope) do
      {:ok, _} ->
        LiveToast.send_toast(:info, "Nazwa konta została zmieniona.")

        accounts =
          case Finances.list_bank_accounts(scope: scope, load: [:broken?, :has_successful_sync?, :requisition]) do
            {:ok, accs} -> accs
            {:error, _} -> []
          end

        {:noreply,
         socket
         |> assign(:bank_accounts, accounts)
         |> assign(:bank_account_statuses, derive_statuses(accounts))}

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
      organization_id = socket.assigns.current_user.organization_id
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

        accounts =
          case Finances.list_bank_accounts(scope: scope, load: [:broken?, :has_successful_sync?, :requisition]) do
            {:ok, accs} -> accs
            {:error, _} -> []
          end

        {:noreply,
         socket
         |> assign(:bank_accounts, accounts)
         |> assign(:bank_account_statuses, derive_statuses(accounts))}

      {:error, _} ->
        LiveToast.send_toast(:error, "Nie udało się dodać konta.")
        {:noreply, socket}
    end
  end

  def handle_event("regenerate_inbound_nickname", _params, socket) do
    current_user = socket.assigns.current_user
    current_org = socket.assigns.current_org

    if current_user.role != :admin do
      raise Forbidden, message: "Tylko administrator może zmienić adres e-mail."
    end

    case Core.regenerate_nickname(current_org, authorize?: false, actor: %{}) do
      {:ok, updated_org} ->
        # Load avatar using Ash.load!
        updated_with_avatar =
          Ash.load!(updated_org, [avatar_blob: [:url]],
            tenant: updated_org.id,
            authorize?: false,
            actor: %{}
          )

        LiveToast.send_toast(:info, "Nowy adres e-mail został wygenerowany.")
        {:noreply, assign(socket, :current_org, updated_with_avatar)}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas generowania nowego adresu.")
        {:noreply, socket}
    end
  end

  def handle_event("add_allowed_email", %{"email" => email}, socket) do
    current_user = socket.assigns.current_user
    current_org = socket.assigns.current_org

    if current_user.role != :admin do
      raise Forbidden, message: "Tylko administrator może zarządzać listą dozwolonych adresów."
    end

    case Core.add_sender_email(current_org, %{email: String.trim(email)},
           authorize?: false,
           actor: %{}
         ) do
      {:ok, updated_org} ->
        # Load avatar using Ash.load!
        updated_with_avatar =
          Ash.load!(updated_org, [avatar_blob: [:url]],
            tenant: updated_org.id,
            authorize?: false,
            actor: %{}
          )

        LiveToast.send_toast(:info, "Adres e-mail został dodany do listy dozwolonych.")
        {:noreply, assign(socket, :current_org, updated_with_avatar)}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas dodawania adresu e-mail.")
        {:noreply, socket}
    end
  end

  def handle_event("remove_allowed_email", %{"email" => email}, socket) do
    current_user = socket.assigns.current_user
    current_org = socket.assigns.current_org

    if current_user.role != :admin do
      raise Forbidden, message: "Tylko administrator może zarządzać listą dozwolonych adresów."
    end

    case Core.remove_sender_email(current_org, %{email: email},
           authorize?: false,
           actor: %{}
         ) do
      {:ok, updated_org} ->
        # Load avatar using Ash.load!
        updated_with_avatar =
          Ash.load!(updated_org, [avatar_blob: [:url]],
            tenant: updated_org.id,
            authorize?: false,
            actor: %{}
          )

        LiveToast.send_toast(:info, "Adres e-mail został usunięty z listy dozwolonych.")
        {:noreply, assign(socket, :current_org, updated_with_avatar)}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas usuwania adresu e-mail.")
        {:noreply, socket}
    end
  end

  def handle_event("save_ksef_token", %{"ksef_token" => ksef_token}, socket) do
    if socket.assigns.current_user.role != :admin do
      raise Forbidden, message: "Tylko administrator może zarządzać KSeF."
    end

    case Ksef.authenticate_with_ksef_token(ksef_token, socket.assigns.ash_scope) do
      {:ok, credential} ->
        Analytics.track_event("ksef_connect", socket.assigns.current_user, %{})

        LiveToast.send_toast(:info, "Połączono z KSeF.")
        {:noreply, assign(socket, :ksef_credential, credential)}

      {:error, :invalid_token_format} ->
        LiveToast.send_toast(:error, "Nieprawidłowy format tokenu KSeF.")
        {:noreply, socket}

      {:error, :nip_mismatch} ->
        LiveToast.send_toast(:error, "NIP w tokenie nie zgadza się z NIP organizacji.")
        {:noreply, socket}

      {:error, :already_connected} ->
        LiveToast.send_toast(:error, "Organizacja jest już połączona z KSeF.")
        {:noreply, socket}
    end
  end

  def handle_event("disconnect_ksef", _params, socket) do
    if socket.assigns.current_user.role != :admin do
      raise Forbidden, message: "Tylko administrator może zarządzać KSeF."
    end

    case Ksef.unauthenticate(socket.assigns.ash_scope) do
      {:ok, _} ->
        Analytics.track_event("ksef_disconnect", socket.assigns.current_user, %{})

        LiveToast.send_toast(:info, "Rozłączono z KSeF.")
        {:noreply, assign(socket, :ksef_credential, nil)}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas rozłączania z KSeF.")
        {:noreply, socket}
    end
  end

  def handle_event("toggle_editing_basic_info", _params, socket) do
    {:noreply, assign(socket, :editing_basic_info, !socket.assigns.editing_basic_info)}
  end

  def handle_event("toggle_editing_correspondence", _params, socket) do
    {:noreply, assign(socket, :editing_correspondence, !socket.assigns.editing_correspondence)}
  end

  def handle_event("toggle_editing_personal_info", _params, socket) do
    {:noreply, assign(socket, :editing_personal_info, !socket.assigns.editing_personal_info)}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      AshPhoenix.Form.validate(socket.assigns.email_form, user_params)

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => _password, "user" => user_params} = params

    # Email change uses the confirm_email_update confirmation add-on
    strategy = AshAuthentication.Info.strategy!(Core.User, :confirm_email_update)

    case AshAuthentication.Strategy.action(strategy, :request, %{
           "email" => user_params["email"]
         }) do
      {:ok, _user} ->
        info = "Link potwierdzający zmianę adresu email został wysłany na nowy adres."
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się zainicjować zmiany emaila.")}
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
         |> push_navigate(to: ~p"/ustawienia/bezpieczenstwo")}

      {:error, form} ->
        {:noreply, assign(socket, password_form: form)}
    end
  end

  def handle_event("link_google_account", _params, socket) do
    {:noreply, redirect(socket, external: "/auth/user/google/request")}
  end

  def handle_event("unlink_google_account", _params, socket) do
    user = socket.assigns.current_user

    case Core.unlink_google_account(user, authorize?: false, actor: %{}) do
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

  # Handle Ash native PubSub broadcasts for requisition status changes
  def handle_info(
        %Broadcast{topic: "requisition:" <> _, payload: %Notification{resource: Requisition, action: action}},
        socket
      ) do
    # Refresh bank accounts list
    scope = socket.assigns.ash_scope

    bank_accounts =
      case Finances.list_bank_accounts(scope: scope, load: [:broken?, :has_successful_sync?, :requisition]) do
        {:ok, accounts} -> accounts
        {:error, _} -> []
      end

    socket =
      socket
      |> assign(:bank_accounts, bank_accounts)
      |> assign(:bank_account_statuses, derive_statuses(bank_accounts))

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

  defp derive_statuses(bank_accounts) do
    Map.new(bank_accounts, fn account ->
      status =
        cond do
          # Manual accounts (no backend link) or accounts with no successful sync yet
          is_nil(account.gocardless_id) ->
            :processing

          not account.has_successful_sync? ->
            :processing

          account.requisition && account.requisition.status == :rejected ->
            :disconnected

          account.broken? ->
            :broken

          account.requisition && account.requisition.status == :pending ->
            :processing

          true ->
            :connected
        end

      {account.id, status}
    end)
  end
end
