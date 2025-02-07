defmodule FirmowidWeb.SettingsLive.Index do
  alias Firmowid.Blobs
  alias Firmowid.Accounts.Organization
  alias Firmowid.BankData
  alias Firmowid.Finances

  use FirmowidWeb, :live_view
  alias Ecto.Changeset
  alias Firmowid.Accounts
  import FirmowidWeb.SettingsLive.EditButton

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

  def mount(_params, _session, socket) do
    bank_accounts =
      if Bodyguard.permit?(BankData, :read_bank_accounts, socket.assigns.current_user) do
        BankData.list_bank_accounts()
      else
        []
      end

    org = Map.put(socket.assigns.current_org, :is_editing, false)

    socket =
      if Bodyguard.permit?(Accounts, :update_organization, socket.assigns.current_user) do
        socket
        |> assign(
          :company_form,
          to_form(form_basic_info_changeset(org))
        )
        |> assign(
          :correspondence_form,
          to_form(form_correspondence_changeset(org))
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

    {:noreply, socket |> assign(:current_user, Accounts.get_user_with_avatar(updated))}
  end

  def handle_avatar_upload(:organization_avatar, blob_id, socket) do
    {:ok, updated} = Accounts.update_organization_avatar(socket.assigns.current_org, blob_id)

    LiveToast.send_toast(:info, "Zdjęcie zostało zaktualizowane.")
    new_socket = socket |> assign(:current_org, Accounts.get_organization_with_avatar(updated))

    {:noreply, new_socket}
  end

  defp handle_progress(name, entry, socket) when name in [:organization_avatar, :user_avatar] do
    if name == :organization_avatar do
      Bodyguard.permit!(Organization, :update_organization, socket.assigns.current_org)
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

        {:noreply,
         socket
         |> redirect(to: ~p"/")}

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
        {:noreply, socket |> assign(:current_user, user)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_bank_account", %{"account_id" => account_id}, socket) do
    Bodyguard.permit!(BankData, :delete_bank_account, socket.assigns.current_user)

    case Finances.delete_bank_account(account_id) do
      {:ok, _} ->
        LiveToast.send_toast(:info, "Konto bankowe zostało usunięte.")
        {:noreply, socket |> assign(:bank_accounts, BankData.list_bank_accounts())}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas usuwania konta bankowego.")
        {:noreply, socket}
    end
  end

  def handle_event("make_default_account", %{"account_id" => account_id}, socket) do
    Bodyguard.permit!(BankData, :update_bank_account, socket.assigns.current_user)

    case Finances.make_account_default(account_id) do
      {:ok, _} ->
        {:noreply, socket |> assign(:bank_accounts, BankData.list_bank_accounts())}

      {:error, _} ->
        LiveToast.send_toast(
          :error,
          "Wystąpił błąd podczas ustawiania konta bankowego jako domyślne."
        )

        {:noreply, socket}
    end
  end

  def handle_event("save", %{"organization" => organization}, socket) do
    Bodyguard.permit!(Accounts, :update_organization, socket.assigns.current_user)

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
        {:noreply, socket |> assign(:correspondence_form, to_form(changeset))}
    end
  end
end
