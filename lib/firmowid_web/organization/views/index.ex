defmodule FirmowidWeb.Organization.Views.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.Organization
  alias Firmowid.Ash.Core.OrganizationInvite

  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @current_user.organization_id == nil do %>
      <div class="relative flex min-h-screen w-screen items-center justify-center">
        <img
          src="/images/figurine.png"
          class="fixed -top-20 left-1/2 h-[135vh] overflow-clip opacity-10"
        />
        <div class="z-10 max-w-3xl grow">
          <h1 class="mb-16 text-lg font-bold">Czas na przypisanie organizacji do Twojego konta</h1>
          <div class="flex justify-between md:flex-row">
            <div class="flex max-w-[400px] flex-col justify-between gap-4">
              <p>
                Jesteś <span class="font-bold">właścicielem przedsiębiorstwa</span>?
                Wypełnij formularz, aby utworzyć organizację wewnątrz Firmowida.
              </p>
              <.simple_form
                for={@organization_form}
                id="organization_form"
                phx-submit="create"
                phx-change="validate"
              >
                <.error :if={@check_errors}>
                  Popraw błędy w formularzu.
                </.error>

                <.input
                  field={@organization_form[:nip]}
                  type="text"
                  placeholder="Identyfikator (NIP)"
                  required
                />
                <.input
                  field={@organization_form[:name]}
                  type="text"
                  placeholder="Nazwa organizacji"
                  required
                />
                <p class="m-0">Adres przedsiębiorstwa</p>
                <div class="flex flex-row gap-2">
                  <.input
                    class="w-3/4!"
                    name="address[street]"
                    value={@address_form["street"]}
                    placeholder="Ulica"
                    type="text"
                    required
                  />
                  <.input
                    class="w-1/4!"
                    name="address[number]"
                    value={@address_form["number"]}
                    placeholder="/"
                    type="text"
                    required
                  />
                </div>
                <.input
                  name="address[postal_code]"
                  value={@address_form["postal_code"]}
                  placeholder="Kod pocztowy"
                  type="text"
                  required
                />
                <.input
                  name="address[city]"
                  value={@address_form["city"]}
                  placeholder="Miasto"
                  type="text"
                  required
                />

                <:actions>
                  <.button class="w-full!" phx-disable-with="Tworzenie organizacji...">
                    Utwórz organizację
                  </.button>
                </:actions>
              </.simple_form>
            </div>

            <div class="flex max-w-[250px] flex-col justify-between">
              <div>
                <p>
                  Jesteś <span class="font-bold">współpracownikiem</span>
                  i posiadasz kod (zaproszenie)?
                </p>
                <.simple_form for={@join_form} id="join_form" phx-submit="join">
                  <.input field={@join_form[:code]} type="text" label="Kod zaproszenia" required />
                  <:actions>
                    <.button class="w-full" phx-disable-with="Dołączanie...">
                      Dołącz do organizacji
                    </.button>
                  </:actions>
                </.simple_form>
              </div>
              <div class="mt-8 mb-2.5 text-center">
                <p>
                  Nie to konto?
                  <.form for={%{}} action={~p"/wyloguj"} method="delete" class="inline">
                    <button type="submit" class="cursor-pointer underline">
                      Wyloguj
                    </button>
                  </.form>
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    <% else %>
      <h1>Do tego konta jest juz przypisana organizacja</h1>
    <% end %>
    """
  end

  @impl true
  def handle_event("validate", %{"organization" => organization, "address" => address_form}, socket) do
    form =
      socket.assigns.organization_form.source
      |> AshPhoenix.Form.validate(add_address(organization, address_form))
      |> to_form()

    socket =
      socket
      |> assign(:organization_form, form)
      |> assign(:address_form, address_form)
      |> assign(:check_errors, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("create", %{"organization" => organization, "address" => address_form}, socket) do
    user = socket.assigns.current_user

    params =
      organization
      |> add_address(address_form)
      |> Map.put("owner_id", user.id)

    case AshPhoenix.Form.submit(socket.assigns.organization_form.source,
           params: params
         ) do
      {:ok, _created_org} ->
        socket =
          socket
          |> LiveToast.put_toast(:success, "Pomyślnie utworzono organizację")
          |> redirect(to: "/")

        {:noreply, socket}

      {:error, form} ->
        socket =
          socket
          |> assign(:organization_form, to_form(form))
          |> assign(:address_form, address_form)
          |> assign(:check_errors, true)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("join", %{"code" => invite_code}, socket) do
    user = socket.assigns.current_user

    trimmed_code = String.trim(invite_code)

    Logger.metadata(user_id: user.id, user_email: user.email)

    # Find invite by code (unscoped read - invite codes are unique)
    invite =
      OrganizationInvite
      |> Ash.Query.for_read(:read_by_code, %{invite_code: trimmed_code}, actor: user)
      |> Ash.Query.load([:organization])
      |> Ash.read_one!(actor: user)

    Logger.metadata(
      user_id: user.id,
      user_email: user.email,
      organization_id: invite.organization_id,
      organization_name: invite.organization.name
    )

    # Consume the invite (scoped to the invite's organization)
    Core.consume_invite!(invite, %{user_id: user.id}, tenant: invite.organization_id, actor: user)

    {:noreply, redirect(socket, to: "/")}
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    socket = assign(socket, :no_padding, true)

    if is_nil(organization_id) do
      organization_form =
        Organization
        |> AshPhoenix.Form.for_create(:create,
          domain: Core,
          actor: user,
          as: "organization"
        )
        |> to_form()

      socket =
        socket
        |> assign(:organization_form, organization_form)
        |> assign(:address_form, %{
          "street" => "",
          "number" => "",
          "postal_code" => "",
          "city" => ""
        })
        |> assign(:check_errors, false)
        |> assign(
          :join_form,
          to_form(%{
            "code" => ""
          })
        )
        |> assign(:page_title, "Wybierz lub utwórz organizację")

      {:ok, socket}
    else
      {:ok, redirect(socket, to: "/")}
    end
  end

  defp add_address(params, %{"street" => street, "number" => number, "postal_code" => postal_code, "city" => city}) do
    Map.put(params, "address", "#{street} #{number}, #{postal_code} #{city}")
  end
end
