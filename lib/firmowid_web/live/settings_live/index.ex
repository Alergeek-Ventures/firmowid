defmodule FirmowidWeb.SettingsLive.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.SettingsLive.EditButton

  alias Ecto.Changeset
  alias Firmowid.Accounts
  alias Firmowid.Accounts.Organization
  alias Firmowid.BankData
  alias Firmowid.Blobs
  alias Firmowid.Finances

  def form_basic_info_changeset(organization, attrs \\ %{}) do
    organization
    |> Organization.basic_info_changeset(attrs)
    |> Changeset.cast(
      attrs,
      [:is_basic_info_editing]
    )
  end

  def form_correspondence_changeset(organization, attrs \\ %{}) do
    organization
    |> Organization.correspondence_changeset(attrs)
    |> Changeset.cast(
      attrs,
      [:is_correspondence_editing]
    )
  end

  def form_user_changeset(user, attrs \\ %{}) do
    Changeset.cast(user, attrs, [
      :name,
      :employment_date,
      :is_personal_info_editing
    ])
  end

  def mount(_params, _session, socket) do
    bank_accounts =
      if Bodyguard.permit?(Finances, :read_bank_accounts, socket.assigns.current_user) do
        BankData.list_bank_accounts()
      else
        []
      end

    socket =
      if Bodyguard.permit?(
           Accounts,
           :update_organization,
           socket.assigns.current_user,
           socket.assigns.current_org
         ) do
        socket
        |> assign(
          :company_form,
          to_form(form_basic_info_changeset(socket.assigns.current_org))
        )
        |> assign(
          :correspondence_form,
          to_form(form_correspondence_changeset(socket.assigns.current_org))
        )
        |> allow_upload(:organization_avatar,
          accept: ~w(.jpg .jpeg .png),
          max_entries: 1,
          auto_upload: true,
          progress: &handle_progress/3
        )
      else
        socket
      end

    socket = assign(socket, :user_form, to_form(form_user_changeset(socket.assigns.current_user)))

    {:ok,
     socket
     |> assign(
       :tab,
       "konto"
     )
     |> assign(
       :delete_account_form,
       to_form(Accounts.change_user_delete_account(socket.assigns.current_user))
     )
     |> assign(:bank_accounts, bank_accounts)
     |> assign(:bank_account_statuses, derive_statuses(bank_accounts))
     |> assign(:uploaded_files, [])
     |> allow_upload(:user_avatar,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       auto_upload: true,
       progress: &handle_progress/3
     )
     |> assign(:current_user, Accounts.get_user_with_avatar(socket.assigns.current_user))
     |> assign(:current_org, Accounts.get_organization_with_avatar(socket.assigns.current_org))
     |> assign(:main_class, "bg-white")}
  end

  def handle_params(%{"tab" => tab}, _uri, socket) do
    {:noreply, assign(socket, tab: tab)}
  end

  def handle_params(_unsigned_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_avatar_upload(:user_avatar, blob_id, socket) do
    {:ok, updated} = Accounts.update_user_avatar(socket.assigns.current_user, blob_id)

    LiveToast.send_toast(:info, "Zdjęcie zostało zaktualizowane.")

    {:noreply, assign(socket, :current_user, Accounts.get_user_with_avatar(updated))}
  end

  def handle_avatar_upload(:organization_avatar, blob_id, socket) do
    {:ok, updated} = Accounts.update_organization_avatar(socket.assigns.current_org, blob_id)

    LiveToast.send_toast(:info, "Zdjęcie zostało zaktualizowane.")
    new_socket = assign(socket, :current_org, Accounts.get_organization_with_avatar(updated))

    {:noreply, new_socket}
  end

  defp handle_progress(name, entry, socket) when name in [:organization_avatar, :user_avatar] do
    if name == :organization_avatar do
      Bodyguard.permit!(
        Accounts,
        :update_organization,
        socket.assigns.current_user,
        socket.assigns.current_org
      )
    end

    if entry.done? do
      case consume_uploaded_entry(socket, entry, fn %{path: path} ->
             {:ok, Blobs.create_blob(path, entry.client_type, entry.client_name)}
           end) do
        {:ok, blob} ->
          handle_avatar_upload(name, blob.id, socket)

        {:error, _err} ->
          LiveToast.send_toast(:error, "Wystąpił błąd podczas aktualizacji zdjęcia.")
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_account", %{"user" => params}, socket) do
    case Accounts.delete_user(socket.assigns.current_user, params["current_password"]) do
      {:ok, _} ->
        LiveToast.send_toast(:info, "Konto zostało usunięte.")

        {:noreply, redirect(socket, to: ~p"/")}

      {:error, :invalid_password} ->
        LiveToast.send_toast(:error, "Nieprawidłowe hasło")
        {:noreply, socket}

      {:error, error} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas usuwania konta")
        Sentry.capture_exception(error)

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

    case Accounts.update_user(socket.assigns.current_user, %{
           marketing_consent: consent
         }) do
      {:ok, user} ->
        {:noreply, assign(socket, :current_user, user)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_bank_account", %{"account_id" => account_id}, socket) do
    bank_account = Finances.get_bank_account!(account_id)
    Bodyguard.permit!(Finances, :delete_bank_account, socket.assigns.current_user, bank_account)

    case Finances.delete_bank_account(account_id) do
      {:ok, _} ->
        LiveToast.send_toast(:info, "Konto bankowe zostało usunięte.")
        bank_accounts = BankData.list_bank_accounts()

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
    bank_account = Finances.get_bank_account!(account_id)
    Bodyguard.permit!(Finances, :update_bank_account, socket.assigns.current_user, bank_account)

    case Finances.make_account_default(account_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:bank_accounts, BankData.list_bank_accounts())
         |> assign(:bank_account_statuses, derive_statuses(BankData.list_bank_accounts()))}

      {:error, _} ->
        LiveToast.send_toast(
          :error,
          "Wystąpił błąd podczas ustawiania konta bankowego jako domyślne."
        )

        {:noreply, socket}
    end
  end

  def handle_event("save", %{"organization" => organization}, socket) do
    Bodyguard.permit!(
      Accounts,
      :update_organization,
      socket.assigns.current_user,
      socket.assigns.current_org
    )

    case Accounts.update_organization(
           socket.assigns.current_org,
           organization
         ) do
      {:ok, updated_org} ->
        {:noreply,
         socket
         |> assign(
           :correspondence_form,
           to_form(Organization.correspondence_changeset(Map.merge(organization, updated_org)))
         )
         |> assign(
           :company_form,
           to_form(Organization.basic_info_changeset(Map.merge(organization, updated_org)))
         )
         |> assign(:current_org, updated_org)}

      {:error, changeset} ->
        {:noreply, assign(socket, :correspondence_form, to_form(changeset))}
    end
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.update_user(socket.assigns.current_user, user_params) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(:current_user, updated_user)
         |> assign(:user_form, to_form(form_user_changeset(Map.merge(user_params, updated_user))))}

      {:error, changeset} ->
        {:noreply, assign(socket, :user_form, to_form(changeset))}
    end
  end

  def handle_event("rename_bank_account", %{"account_id" => account_id, "name" => name}, socket) do
    bank_account = Finances.get_bank_account!(account_id)
    Bodyguard.permit!(Finances, :update_bank_account, socket.assigns.current_user, bank_account)

    case Finances.rename_bank_account(account_id, name) do
      {:ok, _} ->
        LiveToast.send_toast(:info, "Nazwa konta została zmieniona.")
        accounts = BankData.list_bank_accounts()

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
    bank_account = Finances.get_bank_account!(account_id)
    Bodyguard.permit!(BankData, :create_requisition, socket.assigns.current_user)

    # If the account doesn't have an institution associated (legacy/imported),
    # redirect the user to the standard bank connection flow.
    if is_nil(bank_account.institution_id) do
      {:noreply, push_navigate(socket, to: ~p"/ustawienia/bank/dodaj")}
    else
      organization_id = socket.assigns.current_user.organization_id
      redirect_url = FirmowidWeb.Endpoint.url() <> "/ustawienia/bank/dodaj"

      # Determine the correct transaction horizon for this institution (as in /dodaj)
      transaction_days =
        case Firmowid.BankData.ApiClient.get_institution(bank_account.institution_id) do
          {:ok, %{"transaction_total_days" => days}} when is_integer(days) -> days
          _ -> 90
        end

      case BankData.create_requisition(
             bank_account.institution_id,
             transaction_days,
             organization_id,
             redirect_url
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
    Bodyguard.permit!(Finances, :create_bank_account, socket.assigns.current_user)

    org_id = socket.assigns.current_user.organization_id

    attrs = %{
      iban: params["iban"],
      name: params["name"],
      currency: params["currency"],
      organization_id: org_id,
      institution_name: "Manual"
    }

    case Finances.create_manual_bank_account(attrs) do
      %Finances.BankAccount{} ->
        LiveToast.send_toast(:info, "Konto zostało dodane.")
        accounts = BankData.list_bank_accounts()

        {:noreply,
         socket
         |> assign(:bank_accounts, accounts)
         |> assign(:bank_account_statuses, derive_statuses(accounts))}

      _ ->
        LiveToast.send_toast(:error, "Nie udało się dodać konta.")
        {:noreply, socket}
    end
  end

  def handle_event("regenerate_inbound_nickname", _params, socket) do
    Bodyguard.permit!(
      Accounts,
      :update_organization,
      socket.assigns.current_user,
      socket.assigns.current_org
    )

    org_id = socket.assigns.current_user.organization_id

    case Accounts.regenerate_organization_nickname(org_id) do
      {:ok, updated_org} ->
        LiveToast.send_toast(:info, "Nowy adres e-mail został wygenerowany.")

        {:noreply, assign(socket, :current_org, updated_org)}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas generowania nowego adresu.")
        {:noreply, socket}
    end
  end

  defp derive_statuses(bank_accounts) do
    Map.new(bank_accounts, fn account ->
      status =
        cond do
          # Manual accounts (no backend link) or accounts with no successful sync yet
          is_nil(account.gocardless_id) ->
            :processing

          not BankData.bank_account_has_success?(account.id) ->
            :processing

          account.requisition && account.requisition.status == :rejected ->
            :disconnected

          BankData.bank_account_broken?(account.id) ->
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
