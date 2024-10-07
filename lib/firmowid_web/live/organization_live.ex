defmodule FirmowidWeb.OrganizationLive do
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @current_user.organization_id == nil do %>
      <div class="flex flex-col gap-16 text-center">
        <h1 class="text-lg font-bold">Do tego konta nie przypisano jeszcze organizacji</h1>
        <p>
          Dołącz przez wpisanie kodu (jeżeli jesteś współpracownikiem), lub
          utwórz własną.
        </p>

        <div class="flex md:flex-row items-center justify-between">
          <div class="flex flex-col justify-between gap-8 max-w-[500px]">
            <p>Jesteś właścicielem przedsiębiorstwa? Wypełnij formularz,
              aby utworzyć organizację wewnątrz Firmowida.</p>
            <.simple_form for={@organization_form} id="organization_form" phx-submit="create">
              <.input
                field={@organization_form[:name]}
                type="text"
                label="Nazwa organizacji"
                required
              />
              <.input
                field={@organization_form[:identification_number]}
                type="text"
                label="Identyfikator (NIP)"
                required
              />
              <.input
                field={@organization_form[:address]}
                type="text"
                label="Adres organizacji"
                required
              />

              <:actions>
                <.button phx-disable-with="Tworzenie organizacji...">
                  Utwórz organizację
                </.button>
              </:actions>
            </.simple_form>
          </div>

          <div class="max-w-[500px]">
            <.simple_form for={@join_form} id="join_form" phx-submit="join">
              <.input field={@join_form[:code]} type="text" label="Kod organizacji" required />
              <:actions>
                <.button class="w-full" phx-disable-with="Dołączanie...">
                  Dołącz do organizacji
                </.button>
              </:actions>
            </.simple_form>
          </div>
        </div>
        <.link class="underline" href={~p"/users/log_out"} method="delete">
          Wyloguj
        </.link>
      </div>
    <% else %>
      <h1>Do tego konta jest juz przypisany organizacja</h1>
    <% end %>
    """
  end

  @impl true
  def handle_event("create", organization, socket) do
    user = socket.assigns.current_user

    dbg(organization)

    organization_slug =
      organization["name"]
      |> String.downcase()
      |> String.replace(" ", "-")
      |> String.replace(".", "-")
      |> String.replace("/", "-")
      |> String.replace(",", "-")
      |> String.trim()

    Map.put(organization, "slug", organization_slug)
    |> Accounts.create_organization(user)

    LiveToast.send_toast(:success, "Pomyślnie utworzono organizację")

    {:noreply, redirect(socket, to: "/")}
  end

  @impl true
  def handle_event("join", %{"code" => invite_code}, socket) do
    user = socket.assigns.current_user

    {:ok, _} =
      Accounts.consume_organization_invite(
        invite_code
        |> String.trim(),
        user.id
      )

    {:noreply, redirect(socket, to: "/")}
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    if not is_nil(organization_id) do
      {:ok, redirect(socket, to: "/")}
    else
      socket =
        socket
        |> assign(
          :organization_form,
          to_form(%{
            "name" => "",
            "identification_number" => "",
            "address" => ""
          })
        )
        |> assign(
          :join_form,
          to_form(%{
            "code" => ""
          })
        )
        |> assign(:page_title, "Wybierz lub utwórz organizację")

      {:ok, socket}
    end
  end
end
