defmodule FirmowidWeb.SettingsLive.Index do
  alias Firmowid.Accounts.Organization
  alias Firmowid.BankData
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
      BankData.list_bank_accounts()

    org = Map.put(socket.assigns.current_org, :is_editing, false)

    {:ok,
     socket
     |> assign(:tab, "company")
     |> assign(
       :company_form,
       to_form(form_basic_info_changeset(org))
     )
     |> assign(
       :correspondence_form,
       to_form(form_correspondence_changeset(org))
     )
     |> assign(
       :delete_account_form,
       to_form(Accounts.change_user_delete_account(socket.assigns.current_user))
     )
     |> assign(:bank_accounts, bank_accounts)}
  end

  def handle_params(%{"tab" => tab}, _uri, socket) do
    {:noreply, assign(socket, tab: tab)}
  end

  def handle_params(_unsigned_params, _uri, socket) do
    {:noreply, socket}
  end

  def handle_event("delete_account", %{"user" => params}, socket) do
    case Accounts.delete_user(socket.assigns.current_user, params["current_password"]) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Konto zostało usunięte.")
         |> redirect(to: ~p"/")}

      {:error, :invalid_password} ->
        {:noreply,
         socket
         |> put_flash(:error, "Nieprawidłowe hasło")}

      {:error, error} ->
        Sentry.capture_exception(error)

        {:noreply,
         socket
         |> put_flash(:error, "Wystąpił błąd podczas usuwania konta")}
    end
  end

  def handle_event("save", %{"organization" => organization}, socket) do
    case Accounts.update_organization(
           socket.assigns.current_org,
           organization
         ) do
      {:ok, updated_org} ->
        dbg(updated_org)

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
