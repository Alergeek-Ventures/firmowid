defmodule FirmowidWeb.SettingsLive.Index do
  alias Firmowid.Accounts.Organization
  use FirmowidWeb, :live_view
  alias Firmowid.Accounts
  import FirmowidWeb.SettingsLive.EditButton

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:body_class, "bg-white")
     |> assign(:active_tab, "your_company")
     |> assign(:your_company_is_editing, false)
     |> assign(
       :your_company_form,
       to_form(Organization.basic_info_changeset(socket.assigns.current_org))
     )}
  end

  def handle_params(%{"active_tab" => active_tab}, _uri, socket) do
    {:noreply, assign(socket, active_tab: active_tab)}
  end

  def handle_params(_unsigned_params, _uri, socket) do
    {:noreply, socket}
  end

  @spec handle_event(<<_::32>>, map(), any()) :: {:noreply, any()}
  def handle_event("edit", %{"form" => "your_company", "enabled" => enabled}, socket) do
    {:noreply, assign(socket, your_company_is_editing: enabled == "true")}
  end

  def handle_event("save", %{"organization" => organization}, socket) do
    case Accounts.update_organization(socket.assigns.current_org, organization) do
      {:ok, updated_org} ->
        {:noreply,
         socket
         |> assign(:your_company_is_editing, false)
         |> assign(:your_company_form, to_form(Organization.basic_info_changeset(updated_org)))}

      {:error, changeset} ->
        {:noreply, socket |> assign(:your_company_form, to_form(changeset))}
    end
  end
end
