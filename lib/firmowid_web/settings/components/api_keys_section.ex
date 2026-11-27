defmodule FirmowidWeb.Settings.Components.ApiKeysSection do
  @moduledoc """
  The "API keys" settings page (see `Firmowid.Core.ApiKey`).

  Every member creates and revokes their personal keys, which act as them with their role. An
  admin also manages the company's keys, which act with the role the admin chose and keep
  working when that admin leaves.

  A new key is shown once, right after it is created, until the person closes it or leaves the
  page.
  """
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [attach_access_hook: 2]
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Core
  alias Firmowid.Core.ApiKey
  alias Firmowid.Core.UserRole
  alias Firmowid.LocalDate
  alias Firmowid.TimeFormatter

  @validity_presets [30, 90, 365]
  @default_validity_days 90

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> attach_access_hook(:scope)
     |> assign(:created_key, nil)
     |> assign(:form_open?, false)
     |> reset_form()}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if Map.has_key?(socket.assigns, :keys),
      do: {:ok, socket},
      else: {:ok, assign_keys(socket)}
  end

  @impl true
  def handle_event("open_form", _params, socket) do
    {:noreply, socket |> reset_form() |> assign(:form_open?, true) |> assign(:created_key, nil)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, socket |> reset_form() |> assign(:form_open?, false)}
  end

  def handle_event("kind", %{"value" => kind}, socket) when kind in ["personal", "company"] do
    {:noreply, assign(socket, :kind, kind)}
  end

  def handle_event("role", %{"role" => role}, socket) do
    {:ok, role} = UserRole.from_param(role)
    {:noreply, socket |> assign(:role, role) |> update(:errors, &List.delete(&1, :role))}
  end

  def handle_event("validate", params, socket) do
    {:noreply,
     socket
     |> assign(:name, Map.get(params, "name", ""))
     |> assign_expires_on(params)}
  end

  def handle_event("validity_preset", %{"days" => days}, socket) do
    expires_on = Date.add(LocalDate.today(), String.to_integer(days))
    {:noreply, assign(socket, expires_on: Date.to_iso8601(expires_on), no_expiry?: false)}
  end

  def handle_event("toggle_no_expiry", _params, socket) do
    {:noreply, assign(socket, :no_expiry?, not socket.assigns.no_expiry?)}
  end

  def handle_event("create", params, socket) do
    name = params |> Map.get("name", "") |> String.trim()
    socket = assign(socket, :name, name)
    expires_on = expires_on(socket.assigns)
    company? = socket.assigns.kind == "company"

    errors =
      Enum.reject(
        [
          name == "" && :name,
          (company? and is_nil(socket.assigns.role)) && :role,
          expires_on == :error && :expires_on
        ],
        &(&1 == false)
      )

    if errors == [] do
      create_key(socket, %{name: name, expires_on: expires_on}, company?)
    else
      {:noreply, assign(socket, :errors, errors)}
    end
  end

  def handle_event("close_created_key", _params, socket) do
    {:noreply, assign(socket, :created_key, nil)}
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    with %ApiKey{} = key <- Enum.find(socket.assigns.keys, &(&1.id == id)),
         :ok <- Core.revoke_api_key(key, scope: socket.assigns.scope) do
      LiveToast.send_toast(:success, gettext("The key has been revoked."))
    else
      _error -> LiveToast.send_toast(:error, gettext("Could not revoke the key."))
    end

    # The new key may be the revoked one, so it is not shown any longer.
    {:noreply, socket |> assign(:created_key, nil) |> assign_keys()}
  end

  defp create_key(socket, attrs, company?) do
    opts = [scope: socket.assigns.scope]

    result =
      if company?,
        do: Core.create_company_api_key(Map.put(attrs, :role, socket.assigns.role), opts),
        else: Core.create_api_key(attrs, opts)

    case result do
      {:ok, key} ->
        {:noreply,
         socket
         |> assign(:created_key, %{name: key.name, plaintext: key.__metadata__.plaintext_api_key})
         |> assign(:form_open?, false)
         |> reset_form()
         |> assign_keys()}

      {:error, _error} ->
        LiveToast.send_toast(:error, gettext("Could not create the key."))
        {:noreply, socket}
    end
  end

  defp assign_keys(socket), do: assign(socket, :keys, Core.list_api_keys!(scope: socket.assigns.scope))

  defp reset_form(socket) do
    assign(socket,
      kind: "personal",
      name: "",
      expires_on: Date.to_iso8601(Date.add(LocalDate.today(), @default_validity_days)),
      no_expiry?: false,
      role: nil,
      errors: []
    )
  end

  # A disabled date field is not sent, so the date chosen before "No expiry" stays.
  defp assign_expires_on(%{assigns: %{no_expiry?: true}} = socket, _params), do: socket

  defp assign_expires_on(socket, params), do: assign(socket, :expires_on, Map.get(params, "expires_on", ""))

  # The last day the key works, nil for no expiry, or :error for a date that is not after today.
  defp expires_on(%{no_expiry?: true}), do: nil

  defp expires_on(%{expires_on: expires_on}) do
    with {:ok, date} <- Date.from_iso8601(expires_on),
         true <- Date.after?(date, LocalDate.today()) do
      date
    else
      _invalid -> :error
    end
  end

  defp admin?(scope), do: scope.actor.member.role == :admin

  # A call anyone can try with their key: the first invoices the key's role may read.
  defp api_example do
    """
    curl -X POST #{FirmowidWeb.Core.Endpoint.url()}/api/v1/list_sales_invoices \\
      -H "Authorization: Bearer firmowid_…" \\
      -H "Content-Type: application/json" \\
      -d '{"limit": 5}'\
    """
  end

  defp preset_label(365), do: gettext("1 year")
  defp preset_label(days), do: ngettext("%{count} day", "%{count} days", days)

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        roles: UserRole.roles(),
        validity_presets: @validity_presets,
        admin?: admin?(assigns.scope),
        api_example: api_example(),
        company_keys: Enum.filter(assigns.keys, & &1.service_account_id),
        personal_keys: Enum.filter(assigns.keys, & &1.user_id)
      )

    ~H"""
    <section id={@id} class="flex max-w-3xl flex-col gap-10">
      <div class="flex flex-col gap-4">
        <p class="text-sm/snug text-grey-700">
          {gettext(
            "A key lets a program, such as an online store, a script or an AI assistant, use Firmowid through the API without signing in."
          )}
        </p>
        <p class="text-sm/snug text-grey-700">
          {gettext(
            "The API offers the same operations as Firmowid for AI assistants (MCP). The documentation describes each of them; send the key in the Authorization header:"
          )}
        </p>
        <pre
          id="api-example"
          class="overflow-x-auto rounded-sm bg-grey-100 p-4 font-mono text-xs/relaxed text-grey-900"
        ><%= @api_example %></pre>
        <div class="flex flex-wrap gap-2.5">
          <.button
            :if={not @form_open?}
            id="new-api-key"
            type="button"
            variant="special"
            size="small"
            phx-click="open_form"
            phx-target={@myself}
          >
            {gettext("New key")}
          </.button>
          <.link
            id="api-docs"
            kind="button"
            variant="tertiary"
            size="small"
            redirect={~p"/api/v1/docs"}
            target="_blank"
          >
            {gettext("API documentation")}
          </.link>
        </div>
      </div>

      <div
        :if={@created_key}
        id="api-key-created"
        class="flex flex-col gap-3 rounded-sm bg-moss-100 p-5"
      >
        <p class="text-sm/snug font-medium text-moss-900">
          {gettext("Copy the key %{name} now. It will not be shown again.", name: @created_key.name)}
        </p>
        <code class="font-mono text-sm break-all text-grey-900">{@created_key.plaintext}</code>
        <div class="flex flex-wrap gap-2.5">
          <.button
            id="copy-api-key"
            type="button"
            variant="tertiary"
            size="small"
            phx-hook="CopyToClipboard"
            data-copy-text={@created_key.plaintext}
          >
            <span data-copy-label>{gettext("Copy")}</span>
            <span data-copy-done class="hidden">{gettext("Copied")}</span>
          </.button>
          <.button
            type="button"
            variant="ghost"
            size="small"
            phx-click="close_created_key"
            phx-target={@myself}
          >
            {gettext("Close")}
          </.button>
        </div>
      </div>

      <form
        :if={@form_open?}
        id="api-key-form"
        phx-change="validate"
        phx-submit="create"
        phx-target={@myself}
        class="flex flex-col gap-10"
      >
        <h2 class="text-lg font-semibold text-grey-900">{gettext("New key")}</h2>

        <div class="grid grid-cols-[2.25rem_minmax(0,1fr)] items-baseline gap-y-3 sm:grid-cols-[2.25rem_10rem_minmax(0,1fr)] sm:gap-y-10">
          <.rubric number={1} label={gettext("Who the key belongs to")} />
          <div :if={@admin?} class="col-span-2 flex flex-col gap-3 sm:col-span-1">
            <.segmented_control label={gettext("Who the key belongs to")}>
              <:option
                active={@kind == "personal"}
                phx-click={JS.push("kind", value: %{value: "personal"}, target: @myself)}
              >
                {gettext("To me")}
              </:option>
              <:option
                active={@kind == "company"}
                phx-click={JS.push("kind", value: %{value: "company"}, target: @myself)}
              >
                {gettext("To the company")}
              </:option>
            </.segmented_control>
            <p class="text-sm/snug text-grey-600">
              <%= if @kind == "personal" do %>
                {gettext(
                  "It acts as you. It stops working when you leave the company or delete your account."
                )}
              <% else %>
                {gettext(
                  "It does not depend on any person: it keeps working when the person who created it leaves the company. It has the role you choose below."
                )}
              <% end %>
            </p>
          </div>
          <p :if={not @admin?} class="col-span-2 text-sm/snug text-grey-900 sm:col-span-1">
            {gettext(
              "To you. It acts as you and stops working when you leave the company or delete your account."
            )}
          </p>

          <.rubric number={2} label={gettext("Name")} for="api-key-name" />
          <div class="col-span-2 flex flex-col gap-1 sm:col-span-1">
            <input
              id="api-key-name"
              name="name"
              type="text"
              value={@name}
              maxlength="100"
              placeholder={gettext("e.g. Online store")}
              phx-debounce="200"
              class={[
                "h-8.5 w-full max-w-sm rounded-sm border bg-white px-3 text-base/tight text-grey-900 placeholder:text-grey-400 focus:border-grey-700 focus:ring-0",
                if(:name in @errors, do: "border-brick-600", else: "border-grey-200")
              ]}
            />
            <p :if={:name in @errors} class="text-sm text-brick-700">
              {gettext("Name the key, for example after the program that uses it.")}
            </p>
          </div>

          <.rubric number={3} label={gettext("Valid until")} for="api-key-expires-on" />
          <div class="col-span-2 flex flex-col gap-1 sm:col-span-1">
            <div class="flex flex-wrap items-center gap-2">
              <.input
                id="api-key-expires-on"
                name="expires_on"
                type="date"
                value={@expires_on}
                min={Date.to_iso8601(Date.add(LocalDate.today(), 1))}
                disabled={@no_expiry?}
                phx-debounce
                errors={if(:expires_on in @errors and not @no_expiry?, do: [""], else: [])}
                show_error={false}
                class="h-8 w-43 has-disabled:opacity-50"
              />
              <.button
                :for={days <- @validity_presets}
                type="button"
                size="small"
                variant="tertiary"
                class="h-8"
                phx-click="validity_preset"
                phx-value-days={days}
                phx-target={@myself}
              >
                {preset_label(days)}
              </.button>
              <.button
                id="api-key-no-expiry"
                type="button"
                size="small"
                variant={if @no_expiry?, do: "secondary", else: "outline"}
                class="h-8"
                aria-pressed={to_string(@no_expiry?)}
                phx-click="toggle_no_expiry"
                phx-target={@myself}
              >
                {gettext("No expiry")}
              </.button>
            </div>
            <p :if={:expires_on in @errors and not @no_expiry?} class="text-sm text-brick-700">
              {gettext("Choose a date after today, or a key with no expiry.")}
            </p>
          </div>

          <.rubric number={4} label={gettext("Permissions")} />
          <p :if={@kind == "personal"} class="col-span-2 text-sm/snug text-grey-900 sm:col-span-1">
            {gettext(
              "The same as yours in this company (%{role}). When your role changes, so does the key's.",
              role: UserRole.label(@scope.actor.member.role)
            )}
          </p>
          <div :if={@kind == "company"} class="col-span-2 flex flex-col gap-3 sm:col-span-1">
            <.segmented_control label={gettext("Permissions")}>
              <:option
                :for={role <- @roles}
                active={@role == role}
                phx-click={JS.push("role", value: %{role: UserRole.param(role)}, target: @myself)}
              >
                <span class="capitalize">{UserRole.label(role)}</span>
              </:option>
            </.segmented_control>
            <p :if={@role} class="text-sm/snug text-grey-600">{UserRole.description(@role)}</p>
            <p :if={:role in @errors} class="text-sm text-brick-700">
              {gettext("Choose the role whose permissions the key has.")}
            </p>
          </div>
        </div>

        <div class="flex gap-2.5 sm:ps-49">
          <.button type="submit" variant="special" size="small">{gettext("Create key")}</.button>
          <.button type="button" variant="ghost" size="small" phx-click="cancel" phx-target={@myself}>
            {gettext("Cancel")}
          </.button>
        </div>
      </form>

      <div :if={@admin?} class="flex flex-col gap-3">
        <h2 class="text-h5 font-medium text-grey-900">{gettext("Company keys")}</h2>
        <p :if={@company_keys == []} class="text-sm/snug text-grey-600">
          {gettext("The company has no keys yet.")}
        </p>
        <.key_list
          :if={@company_keys != []}
          id="company-api-keys"
          keys={@company_keys}
          myself={@myself}
        />
      </div>

      <div class="flex flex-col gap-3">
        <h2 class="text-h5 font-medium text-grey-900">{gettext("Your keys")}</h2>
        <p :if={@personal_keys == []} class="text-sm/snug text-grey-600">
          {gettext("You have no keys yet.")}
        </p>
        <.key_list
          :if={@personal_keys != []}
          id="personal-api-keys"
          keys={@personal_keys}
          myself={@myself}
        />
      </div>
    </section>
    """
  end

  attr :number, :integer, required: true
  attr :label, :string, required: true
  attr :for, :string, default: nil

  defp rubric(assigns) do
    ~H"""
    <label for={@for} class="col-span-2 mt-7 grid grid-cols-subgrid first:mt-0 sm:mt-0">
      <span class="text-sm/snug font-medium text-grey-900 tabular-nums">{@number}.</span>
      <span class="pe-6 text-sm/snug text-grey-600">{@label}</span>
    </label>
    """
  end

  attr :id, :string, required: true
  attr :keys, :list, required: true
  attr :myself, :any, required: true

  defp key_list(assigns) do
    ~H"""
    <ul id={@id} class="flex flex-col divide-y divide-grey-200 border-y border-grey-200">
      <li
        :for={key <- @keys}
        id={"klucz-api-#{key.id}"}
        class="flex items-start justify-between gap-4 py-3"
      >
        <div class="flex min-w-0 flex-col gap-1">
          <span class="text-sm font-medium text-grey-900">{key.name}</span>
          <span :if={key.service_account} class="text-sm/snug text-grey-700">
            {gettext("Role: %{role}", role: UserRole.label(key.service_account.role))}
          </span>
          <span class="text-xs text-grey-500">
            {gettext("Created on %{date}", date: TimeFormatter.format_date(key.inserted_at))} · {expiry(
              key
            )}
          </span>
        </div>
        <.button
          type="button"
          variant="ghost"
          size="small"
          phx-click="revoke"
          phx-value-id={key.id}
          phx-target={@myself}
          data-confirm={
            gettext("Revoke the key %{name}? Programs that use it will lose access.", name: key.name)
          }
        >
          {gettext("Revoke")}
        </.button>
      </li>
    </ul>
    """
  end

  defp expiry(%{expires_at: nil}), do: gettext("No expiry")

  # A key expires when its last day ends in Poland.
  defp expiry(%{expires_at: expires_at}),
    do:
      gettext("Valid through %{date}",
        date: TimeFormatter.format_date(LocalDate.of(DateTime.shift(expires_at, second: -1)))
      )
end
