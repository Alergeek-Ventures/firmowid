defmodule FirmowidWeb.OrganizationLive do
  use FirmowidWeb, :live_view

  alias Firmowid.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @current_user.organization_id == nil do %>
      <div class="w-screen h-screen overflow-clip flex relative justify-center items-center">
        <img src="/images/figurine.png" class="h-[135vh] opacity-10 absolute -top-20 left-1/2 -z-10" />
        <div class="flex-grow max-w-screen-md">
          <h1 class="text-lg font-bold mb-16">Czas na przypisanie organizacji do Twojego konta</h1>
          <div class="flex md:flex-row justify-between">
            <div class="flex flex-col justify-between gap-4 max-w-[400px]">
              <p>
                Jesteś <span class="font-bold">właścicielem przedsiębiorstwa</span>?
                Wypełnij formularz, aby utworzyć organizację wewnątrz Firmowida.
              </p>
              <.simple_form for={@organization_form} id="organization_form" phx-submit="create">
                <.input
                  field={@organization_form[:identification_number]}
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
                    class="!w-3/4"
                    field={@organization_form[:street]}
                    placeholder="Ulica"
                    type="text"
                    required
                  />
                  <.input
                    class="!w-1/4"
                    field={@organization_form[:number]}
                    placeholder="/"
                    type="text"
                    required
                  />
                </div>
                <.input
                  field={@organization_form[:postal_code]}
                  placeholder="Kod pocztowy"
                  type="text"
                  required
                />
                <.input field={@organization_form[:city]} placeholder="Miasto" type="text" required />

                <:actions>
                  <.button class="!w-full" phx-disable-with="Tworzenie organizacji...">
                    Utwórz organizację
                  </.button>
                </:actions>
              </.simple_form>
            </div>

            <div class="max-w-[250px]">
              <p>
                Jesteś <span class="font-bold">współpracownikiem</span> i posiadasz kod (zaproszenie)?
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
          </div>
          <div class="mt-8 text-center">
            <.link class="underline" href={~p"/users/log_out"} method="delete">
              Wyloguj
            </.link>
          </div>
        </div>
      </div>
    <% else %>
      <h1>Do tego konta jest juz przypisany organizacja</h1>
    <% end %>
    """
  end

  @impl true
  def handle_event("create", organization, socket) do
    user = socket.assigns.current_user

    organization_slug =
      organization["name"]
      |> String.downcase()
      |> String.replace(" ", "-")
      |> String.replace(".", "-")
      |> String.replace("/", "-")
      |> String.replace(",", "-")
      |> String.trim()

    address = %{
      street: organization["street"],
      number: organization["number"],
      postal_code: organization["postal_code"],
      city: organization["city"]
    }

    address = "#{address.street} #{address.number}, #{address.postal_code} #{address.city}"

    organization
    |> Map.put("slug", organization_slug)
    |> Map.put("address", address)
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

    socket = socket |> assign(:no_padding, true)

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
            "street" => "",
            "number" => "",
            "postal_code" => "",
            "city" => ""
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
