defmodule FirmowidWeb.Organization.Views.Index do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import Phoenix.Component, except: [link: 1]

  alias Ash.Error.Invalid
  alias Firmowid.Core
  alias Firmowid.Core.Organization
  alias FirmowidWeb.Analysis.Utilities.Industry

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        owner_parts: split_bold(gettext("Are you %{owner}?", owner: "__BOLD__")),
        partner_parts: split_bold(gettext("Are you %{partner} and have a code (invitation)?", partner: "__BOLD__"))
      )

    ~H"""
    <div class="relative flex min-h-screen w-full items-center justify-center">
      <img
        src="/images/figurine.png"
        class="fixed -top-20 left-1/2 h-[135vh] overflow-clip opacity-10"
      />
      <div class="z-10 max-w-3xl grow">
        <h1 class="mb-16 text-lg font-bold">
          <%= if @current_user.member do %>
            {gettext("Create another organization or join another one with a code")}
          <% else %>
            {gettext("Time to assign an organization to your account")}
          <% end %>
        </h1>
        <div class="flex justify-between md:flex-row">
          <div class="flex max-w-[400px] flex-col justify-between gap-4">
            <p>
              {elem(@owner_parts, 0)}<span class="font-bold">{gettext("a business owner")}</span>{elem(
                @owner_parts,
                1
              )}
              {gettext("Fill in the form to create an organization inside Firmowid.")}
            </p>
            <.simple_form
              for={@organization_form}
              id="organization_form"
              phx-submit="create"
              phx-change="validate"
            >
              <.error :if={@check_errors}>
                {gettext("Fix the errors in the form.")}
              </.error>

              <.input
                field={@organization_form[:owner_name]}
                type="text"
                placeholder={gettext("Your full name")}
                aria-label={gettext("Your full name")}
                required
              />
              <.input
                field={@organization_form[:nip]}
                type="text"
                placeholder={gettext("Identifier (NIP)")}
                aria-label={gettext("Tax ID (NIP)")}
                required
              />
              <.input
                field={@organization_form[:name]}
                type="text"
                placeholder={gettext("Organization name")}
                aria-label={gettext("Organization name")}
                required
              />
              <.input
                field={@organization_form[:industry]}
                type="select"
                label={gettext("Industry")}
                options={Industry.options()}
              />
              <p class="m-0">{gettext("Business address")}</p>
              <div class="flex flex-row gap-2">
                <.input
                  class="w-3/4!"
                  name="address[street]"
                  value={@address_form["street"]}
                  placeholder={gettext("Street")}
                  aria-label={gettext("Street")}
                  type="text"
                  required
                />
                <.input
                  class="w-1/4!"
                  name="address[number]"
                  value={@address_form["number"]}
                  placeholder="/"
                  aria-label={gettext("Building and apartment number")}
                  type="text"
                  required
                />
              </div>
              <.input
                name="address[postal_code]"
                value={@address_form["postal_code"]}
                placeholder={gettext("Postal code")}
                aria-label={gettext("Postal code")}
                type="text"
                required
              />
              <.input
                name="address[city]"
                value={@address_form["city"]}
                placeholder={pgettext("address", "City")}
                aria-label={pgettext("address", "City")}
                type="text"
                required
              />

              <:actions>
                <.button
                  variant="special"
                  class="w-full"
                  phx-disable-with={gettext("Creating organization...")}
                >
                  {gettext("Create organization")}
                </.button>
              </:actions>
            </.simple_form>
          </div>

          <div class="flex max-w-[250px] flex-col justify-between">
            <div>
              <p>
                {elem(@partner_parts, 0)}<span class="font-bold">{gettext("a collaborator")}</span>{elem(
                  @partner_parts,
                  1
                )}
              </p>
              <.simple_form for={@join_form} id="join_form" phx-submit="join">
                <.input field={@join_form[:name]} type="text" label={gettext("Full name")} required />
                <.input
                  field={@join_form[:code]}
                  type="text"
                  label={gettext("Invitation code")}
                  required
                />
                <:actions>
                  <.button variant="special" class="w-full" phx-disable-with={gettext("Joining...")}>
                    {gettext("Join organization")}
                  </.button>
                </:actions>
              </.simple_form>
            </div>
            <div class="mt-8 mb-2.5 text-center">
              <p>
                {gettext("Wrong account?")}
                <.form
                  for={%{}}
                  id="organization-logout-form"
                  action={~p"/wyloguj"}
                  method="delete"
                  class="inline"
                  data-posthog-reset-on-submit="true"
                >
                  <.button
                    type="submit"
                    variant="ghost"
                    size="small"
                    class="h-auto border-none p-0 underline hover:bg-transparent active:bg-transparent"
                  >
                    {pgettext("organization onboarding", "Log out")}
                  </.button>
                </.form>
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    <.form
      for={%{}}
      id="switch-organization-form"
      action={~p"/organizacja/przelacz"}
      phx-trigger-action={not is_nil(@switch_to)}
    >
      <input type="hidden" name="organizacja" value={@switch_to} />
    </.form>
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
    params = add_address(organization, address_form)

    case AshPhoenix.Form.submit(socket.assigns.organization_form.source,
           params: params
         ) do
      {:ok, created_org} ->
        socket =
          socket
          |> LiveToast.put_toast(:success, gettext("Organization created successfully"))
          |> assign(:switch_to, created_org.id)

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
  def handle_event("join", %{"code" => invite_code, "name" => name}, socket) do
    user = socket.assigns.current_user

    trimmed_code = String.trim(invite_code)

    Logger.metadata(user_id: user.id)

    # Find invite by code (unscoped read - invite codes are unique)
    %{invite_code: trimmed_code}
    |> Core.query_to_read_invite_by_code(actor: user)
    |> Ash.read_one!(actor: user)
    |> case do
      nil ->
        join_form =
          to_form(%{"name" => name, "code" => invite_code},
            errors: [code: {gettext("This invite code is invalid or has expired."), []}]
          )

        {:noreply, assign(socket, :join_form, join_form)}

      invite ->
        consume_invite(invite, invite_code, name, socket)
    end
  end

  defp consume_invite(invite, invite_code, name, socket) do
    user = socket.assigns.current_user

    Logger.metadata(
      user_id: user.id,
      organization_id: invite.organization_id
    )

    # Consume the invite (scoped to the invite's organization)
    case Core.consume_invite(invite, %{name: name}, tenant: invite.organization_id, actor: user) do
      {:ok, invite} ->
        {:noreply, assign(socket, :switch_to, invite.organization_id)}

      {:error,
       %Invalid{
         errors: [%Ash.Error.Changes.InvalidChanges{fields: [:organization_id], message: message}]
       }} ->
        join_form =
          to_form(%{"name" => name, "code" => invite_code}, errors: [code: {message, []}])

        {:noreply, assign(socket, :join_form, join_form)}

      {:error, %Invalid{errors: [%Ash.Error.Changes.Required{field: :name}]}} ->
        join_form =
          to_form(%{"name" => name, "code" => invite_code}, errors: [name: {"is required", []}])

        {:noreply, assign(socket, :join_form, join_form)}

      {:error, error} ->
        raise error
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # A user joining or creating another organization is prefilled with the name
    # they use in the current one.
    name = if user.member, do: user.member.name, else: ""

    socket = assign(socket, no_padding: true, switch_to: nil)

    organization_form =
      Organization
      |> AshPhoenix.Form.for_create(:create,
        domain: Core,
        actor: user,
        as: "organization",
        params: %{"owner_name" => name}
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
          "name" => name,
          "code" => ""
        })
      )
      |> assign(:page_title, gettext("Choose or create an organization"))

    {:ok, socket}
  end

  defp split_bold(text), do: List.to_tuple(String.split(text, "__BOLD__", parts: 2))

  defp add_address(params, %{"street" => street, "number" => number, "postal_code" => postal_code, "city" => city}) do
    Map.put(params, "address", "#{street} #{number}, #{postal_code} #{city}")
  end
end
