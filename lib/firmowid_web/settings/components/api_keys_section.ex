defmodule FirmowidWeb.Settings.Components.ApiKeysSection do
  @moduledoc """
  The "API keys" settings page: an admin creates keys for the organization's servers,
  sees the organization's keys and revokes them (see `Firmowid.Core.ApiKey`).

  A new key is shown once, right after it is created, until the admin closes it or
  leaves the page. Only admins reach the page.
  """
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidWeb.Infrastructure.Hooks.RequireOrganization, only: [attach_access_hook: 2]

  alias Firmowid.Core
  alias Firmowid.Core.ApiKey
  alias Firmowid.TimeFormatter

  @validity_days ["30", "90", "365"]
  @default_scopes ["sales_invoices"]

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> attach_access_hook(:scope)
     |> assign(:created_key, nil)
     |> assign(:validity, "")
     |> assign(:selected_scopes, @default_scopes)}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    if Map.has_key?(socket.assigns, :api_keys),
      do: {:ok, socket},
      else: {:ok, socket |> assign_api_keys() |> assign_form()}
  end

  @impl true
  def handle_event("validate", %{"api_key" => params} = form_params, socket) do
    scopes = selected_scopes(form_params)
    params = Map.put(params, "scopes", scopes)

    {:noreply,
     socket
     |> assign(:form, AshPhoenix.Form.validate(socket.assigns.form, params))
     |> assign(:validity, Map.get(form_params, "validity", ""))
     |> assign(:selected_scopes, scopes)}
  end

  def handle_event("create", %{"api_key" => params} = form_params, socket) do
    params =
      params
      |> Map.put("scopes", selected_scopes(form_params))
      |> Map.put("expires_at", expires_at(Map.get(form_params, "validity", "")))

    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, key} ->
        {:noreply,
         socket
         |> assign(:created_key, key.__metadata__.plaintext_api_key)
         |> assign(:validity, "")
         |> assign(:selected_scopes, @default_scopes)
         |> assign_api_keys()
         |> assign_form()}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  def handle_event("close_created_key", _params, socket) do
    {:noreply, assign(socket, :created_key, nil)}
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    with %ApiKey{} = key <- Enum.find(socket.assigns.api_keys, &(&1.id == id)),
         :ok <- Core.revoke_api_key(key, scope: socket.assigns.scope) do
      LiveToast.send_toast(:success, gettext("The key has been revoked."))
    else
      _error -> LiveToast.send_toast(:error, gettext("Could not revoke the key."))
    end

    # The new key may be the revoked one, so it is not shown any longer.
    {:noreply, socket |> assign(:created_key, nil) |> assign_api_keys()}
  end

  defp assign_api_keys(socket), do: assign(socket, :api_keys, Core.list_api_keys!(scope: socket.assigns.scope))

  defp assign_form(socket) do
    form =
      ApiKey
      |> AshPhoenix.Form.for_create(:create, scope: socket.assigns.scope, as: "api_key")
      |> to_form()

    assign(socket, :form, form)
  end

  # The scope checkboxes send `scopes[<scope>]` as "true" or "false".
  defp selected_scopes(form_params) do
    for {scope, "true"} <- Map.get(form_params, "scopes", %{}), do: scope
  end

  defp scope_options, do: Enum.map(ApiKey.scopes(), &{to_string(&1), scope_label(&1)})

  defp scope_label(:sales_invoices), do: gettext("Sales invoices: issue and read")

  defp expires_at(days) when days in @validity_days, do: DateTime.shift(DateTime.utc_now(), day: String.to_integer(days))

  defp expires_at(_days), do: nil

  defp validity_options do
    [
      {gettext("No expiry"), ""},
      {gettext("30 days"), "30"},
      {gettext("90 days"), "90"},
      {gettext("1 year"), "365"}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="flex flex-col gap-6">
      <p class="max-w-2xl text-sm/[1.35] text-grey-700">
        {gettext(
          "A key lets your company's server, such as an online store, use the Firmowid API without signing in. It acts as the administrator who created it, in this company."
        )}
      </p>

      <div
        :if={@created_key}
        id="api-key-created"
        class="flex flex-col gap-3 rounded-lg border border-moss-200 bg-moss-50 p-5"
      >
        <p class="text-sm font-medium text-grey-900">
          {gettext("Copy the key now. It will not be shown again.")}
        </p>
        <code class="rounded-md bg-white px-3 py-2 font-mono text-sm break-all text-grey-900">
          {@created_key}
        </code>
        <div class="flex flex-wrap gap-2.5">
          <.button
            id="copy-api-key"
            type="button"
            variant="primary"
            size="small"
            phx-hook="CopyToClipboard"
            data-copy-text={@created_key}
          >
            <span data-copy-label>{gettext("Copy")}</span>
            <span data-copy-done class="hidden">{gettext("Copied")}</span>
          </.button>
          <.button
            type="button"
            variant="tertiary"
            size="small"
            phx-click="close_created_key"
            phx-target={@myself}
          >
            {gettext("Close")}
          </.button>
        </div>
      </div>

      <.form
        for={@form}
        id="api-key-form"
        phx-change="validate"
        phx-submit="create"
        phx-target={@myself}
        class="flex flex-col gap-4 rounded-lg bg-white"
      >
        <div class="flex flex-col gap-4 sm:flex-row sm:items-end">
          <.input
            field={@form[:name]}
            type="text"
            label={gettext("Name")}
            placeholder={gettext("e.g. Online store")}
            maxlength="100"
            container_class="flex-1"
            input_class="w-full"
          />
          <.input
            id="api-key-validity"
            name="validity"
            type="select"
            label={gettext("Valid for")}
            value={@validity}
            options={validity_options()}
            container_class="sm:w-48"
          />
        </div>
        <fieldset class="flex flex-col gap-2">
          <legend class="mb-2 text-sm font-medium text-grey-900">{gettext("Access")}</legend>
          <.input
            :for={{scope, label} <- scope_options()}
            id={"api-key-scope-#{scope}"}
            name={"scopes[#{scope}]"}
            type="checkbox"
            label={label}
            checked={scope in @selected_scopes}
          />
          <.error :if={@form[:scopes].errors != [] and used_input?(@form[:scopes])}>
            {gettext("Choose at least one.")}
          </.error>
        </fieldset>
        <.button type="submit" variant="primary" size="small" class="self-start">
          {gettext("Create key")}
        </.button>
      </.form>

      <p :if={@api_keys == []} class="text-sm/[1.35] text-grey-700">
        {gettext("The company has no API keys yet.")}
      </p>

      <ul :if={@api_keys != []} id="api-keys" class="flex flex-col divide-y divide-grey-100">
        <li
          :for={key <- @api_keys}
          id={"klucz-api-#{key.id}"}
          class="flex flex-wrap items-center justify-between gap-4 py-3"
        >
          <div class="flex flex-col gap-1">
            <span class="font-medium text-grey-900">{key.name}</span>
            <span class="text-sm text-grey-700">
              {Enum.map_join(key.scopes, ", ", &scope_label/1)} · {gettext("Created %{date}",
                date: TimeFormatter.format_date(key.inserted_at)
              )} · {expiry(key)}
            </span>
          </div>
          <.button
            type="button"
            variant="tertiary"
            size="small"
            phx-click="revoke"
            phx-value-id={key.id}
            phx-target={@myself}
            data-confirm={
              gettext("Revoke the key %{name}? Servers that use it will lose access.", name: key.name)
            }
          >
            {gettext("Revoke")}
          </.button>
        </li>
      </ul>
    </section>
    """
  end

  defp expiry(%ApiKey{expires_at: nil}), do: gettext("No expiry")

  defp expiry(%ApiKey{expires_at: expires_at}) do
    date = TimeFormatter.format_date(expires_at)

    if DateTime.after?(expires_at, DateTime.utc_now()),
      do: gettext("Expires %{date}", date: date),
      else: gettext("Expired %{date}", date: date)
  end
end
