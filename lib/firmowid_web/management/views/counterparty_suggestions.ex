defmodule FirmowidWeb.Management.Views.CounterpartySuggestions do
  @moduledoc """
  Buyers of issued invoices without a counterparty, each with a proposal to
  link an existing counterparty or create one prefilled from the invoices and
  the VAT white list. Part of the new interface behind the `inbox` flag.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.Badge
  import FirmowidWeb.DesignSystem.Components.IconButton
  import FirmowidWeb.Infrastructure.Flags, only: [flag_enabled?: 2]
  import Phoenix.Component, except: [link: 1]

  alias Ash.Error.Invalid
  alias Firmowid.Invoicing.Services.CounterpartyDetection
  alias FirmowidUI.Components.Inputs
  alias FirmowidWeb.Management.Utilities.CounterpartyHelpers
  alias FirmowidWeb.Management.Utilities.Navigation

  on_mount {FirmowidWeb.Infrastructure.Hooks.RequireAdmin, :default}

  @editable ~w(display_name full_name given_name surname tax_id address email)

  @impl true
  def mount(_params, _session, socket) do
    if flag_enabled?(:inbox, socket.assigns) do
      {:ok,
       socket
       |> assign(:page_title, gettext("Counterparties to review"))
       |> assign(:create_instead, MapSet.new())
       |> assign(:edits, %{})
       |> load_groups()}
    else
      {:ok, push_navigate(socket, to: Navigation.counterparties_path(:index))}
    end
  end

  @impl true
  def handle_async(:registry, {:ok, {:ok, registry}}, socket) do
    groups = Enum.map(socket.assigns.groups, &%{&1 | registry: registry[&1.key]})
    {:noreply, socket |> assign(:groups, groups) |> assign(:registry_state, :loaded)}
  end

  def handle_async(:registry, _failed, socket) do
    {:noreply, assign(socket, :registry_state, :failed)}
  end

  def handle_async(:proposals, {:ok, cleaned}, socket) do
    groups = Enum.map(socket.assigns.groups, &%{&1 | cleaned: cleaned[&1.key]})
    {:noreply, socket |> assign(:groups, groups) |> assign(:names_state, :loaded)}
  end

  def handle_async(:proposals, _failed, socket) do
    {:noreply, assign(socket, :names_state, :loaded)}
  end

  @impl true
  def handle_event(event, %{"key" => key}, socket) when event in ["link", "create"] do
    case find_group(socket, key) do
      # A second click, or a click on a row "accept ready" already saved.
      nil -> {:noreply, socket}
      group when event == "link" -> link(group, socket)
      group -> create(group, socket)
    end
  end

  def handle_event("edit", %{"key" => key, "counterparty" => params}, socket) do
    {:noreply, update(socket, :edits, &Map.put(&1, key, Map.take(params, @editable)))}
  end

  def handle_event("clear_field", %{"key" => key, "field" => field}, socket) when field in @editable do
    {:noreply,
     update(socket, :edits, fn edits ->
       Map.update(edits, key, %{field => ""}, &Map.put(&1, field, ""))
     end)}
  end

  def handle_event("create_instead", %{"key" => key}, socket) do
    {:noreply, update(socket, :create_instead, &MapSet.put(&1, key))}
  end

  def handle_event("skip", %{"key" => key}, socket) do
    {:noreply, drop_group(socket, key)}
  end

  def handle_event("accept_all", _params, socket) do
    scope = socket.assigns.ash_scope

    results =
      socket.assigns.groups
      |> Enum.map(&with_edits(&1, socket.assigns.edits))
      |> Enum.filter(&is_nil(attention(&1, socket.assigns)))
      |> Enum.map(fn group ->
        case proposal(group, socket.assigns.create_instead) do
          :link ->
            {group.key, CounterpartyDetection.link(group, group.match.counterparty.id, scope)}

          :create ->
            {group.key, CounterpartyDetection.create_and_link(group, scope)}
        end
      end)

    # Validation failures stay on the list for review. Anything else is a bug and raises
    # here, after the other groups were saved; the remount then lists only what is left.
    Enum.each(results, fn
      {_key, {:error, error}} -> validation_message!(error)
      _done -> :ok
    end)

    done = for {key, result} <- results, result == :ok or match?({:ok, _}, result), do: key
    failed = length(results) - length(done)

    socket = Enum.reduce(done, socket, &drop_group(&2, &1))

    socket =
      if failed == 0,
        do: LiveToast.put_toast(socket, :success, gettext("Ready counterparties saved")),
        else:
          put_flash(
            socket,
            :error,
            gettext("Some counterparties could not be saved. Review them below.")
          )

    {:noreply, socket}
  end

  defp link(group, socket) do
    case CounterpartyDetection.link(group, group.match.counterparty.id, socket.assigns.ash_scope) do
      :ok ->
        {:noreply,
         socket
         |> drop_group(group.key)
         |> LiveToast.put_toast(
           :success,
           gettext("Invoices linked to %{name}", name: group.match.counterparty.display_label)
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, validation_message!(error))}
    end
  end

  defp create(group, socket) do
    case CounterpartyDetection.create_and_link(group, socket.assigns.ash_scope) do
      {:ok, counterparty} ->
        {:noreply,
         socket
         |> drop_group(group.key)
         |> LiveToast.put_toast(
           :success,
           gettext("Counterparty %{name} created", name: counterparty.display_name)
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, validation_message!(error))}
    end
  end

  # The proposal goes through the same validations as the counterparty form, so a
  # failure the user can fix is shown as such; any other error is unexpected and raises.
  defp validation_message!(%Invalid{errors: [%{message: message} = error | _rest]}) when is_binary(message) do
    Inputs.translate_error({message, Map.get(error, :vars, [])})
  end

  # Some validation errors, such as a missing required country, carry no message of their own.
  defp validation_message!(%Invalid{errors: [error | _rest]}), do: Exception.message(error)

  defp validation_message!(error), do: raise(Ash.Error.to_error_class(error))

  defp load_groups(socket) do
    scope = socket.assigns.ash_scope
    groups = CounterpartyDetection.list(scope)

    socket
    |> assign(:groups, groups)
    |> assign(:registry_state, :loading)
    |> assign(:names_state, :loading)
    |> start_async(:registry, fn -> CounterpartyDetection.registry_data(groups) end)
    |> start_async(:proposals, fn ->
      # The cleanup reads the register too, so it does not wait for the badges.
      registry =
        case CounterpartyDetection.registry_data(groups) do
          {:ok, registry} -> registry
          {:error, _reason} -> %{}
        end

      CounterpartyDetection.cleaned_proposals(groups, registry, scope)
    end)
  end

  defp find_group(socket, key) do
    case Enum.find(socket.assigns.groups, &(&1.key == key)) do
      nil -> nil
      group -> with_edits(group, socket.assigns.edits)
    end
  end

  # Fields the user corrected in the expanded row win over the proposal.
  defp with_edits(group, edits) do
    overrides =
      Map.new(Map.get(edits, group.key, %{}), fn {field, value} ->
        {String.to_existing_atom(field), value}
      end)

    Map.put(group, :overrides, overrides)
  end

  defp drop_group(socket, key), do: update(socket, :groups, fn groups -> Enum.reject(groups, &(&1.key == key)) end)

  defp proposal(%{match: nil}, _create_instead), do: :create

  defp proposal(group, create_instead) do
    if MapSet.member?(create_instead, group.key), do: :create, else: :link
  end

  # What needs a look before accepting: a match by name only, a different name
  # for the NIP in the VAT white list, or a Polish NIP the white list does not know.
  defp attention(group, assigns) do
    attention(group, proposal(group, assigns.create_instead), assigns.registry_state)
  end

  defp attention(%{match: %{reason: :name}}, :link, _registry_state), do: :name
  defp attention(_group, :link, _registry_state), do: nil

  defp attention(group, :create, registry_state) do
    cond do
      registry_name_differs?(group) -> :registry_name
      registry_state == :loaded and missing_from_registry?(group) -> :registry_missing
      true -> nil
    end
  end

  defp missing_from_registry?(group), do: is_nil(group.registry) and not is_nil(CounterpartyDetection.registry_nip(group))

  @impl true
  def render(assigns) do
    {review, ready} =
      assigns.groups
      |> Enum.map(&with_edits(&1, assigns.edits))
      |> Enum.split_with(&attention(&1, assigns))

    assigns = assign(assigns, review: review, ready: ready)

    ~H"""
    <div class="mx-auto flex w-full max-w-7xl flex-1 flex-col gap-6 pb-4">
      <%!-- Same header geometry as the counterparty list, so switching tabs does not jump. --%>
      <div class="sticky top-navbar-collapsed z-10 flex flex-col gap-6 bg-grey-100 py-4 max-md:static max-md:z-auto">
        <%!-- The button overlaps the row's margins, so the tabs sit where the list has them. --%>
        <div class="flex h-8 items-center justify-between gap-4">
          <.filter_tabs label={gettext("Counterparty scope")}>
            <:tab navigate={Navigation.counterparties_path(:index)}>
              {pgettext("people list tab", "Active")}
            </:tab>
            <:tab navigate={Navigation.counterparties_path(:archive)}>
              {pgettext("people list tab", "Archived")}
            </:tab>
            <:tab navigate={Navigation.counterparty_suggestions_path()} active count={length(@groups)}>
              {pgettext("people list tab", "To review")}
            </:tab>
          </.filter_tabs>
          <%!-- Rows can still move to "Check first" or get tidied names until both lookups finish. --%>
          <.button
            :if={@ready != [] and @registry_state == :loaded and @names_state == :loaded}
            type="button"
            variant="special"
            class="-my-1.5"
            phx-click="accept_all"
          >
            <Lucideicons.check_check /> {gettext("Accept ready (%{count})", count: length(@ready))}
          </.button>
        </div>
      </div>

      <div
        :if={@groups == []}
        class="flex flex-1 flex-col items-center justify-center gap-4 rounded-lg border border-grey-200 p-6"
      >
        <Lucideicons.circle_check class="size-26 text-grey-300" />
        <p class="text-sm/snug text-grey-700">
          {gettext("Every buyer of your issued invoices has a counterparty.")}
        </p>
      </div>

      <section :if={@review != []} class="mb-2 flex flex-col gap-3">
        <.section_header
          title={gettext("Check first")}
          count={length(@review)}
          hint={gettext("Something does not add up. Decide before saving.")}
          attention
        />
        <div class="overflow-hidden rounded-md bg-white">
          <.row
            :for={group <- @review}
            group={group}
            kind={proposal(group, @create_instead)}
            attention={attention(group, assigns)}
          />
        </div>
      </section>

      <section :if={@ready != []} class="flex flex-col gap-3">
        <.section_header
          title={gettext("Ready")}
          count={length(@ready)}
          hint={gettext("The data matches. Accept them one by one or all at once.")}
        />
        <div class="overflow-hidden rounded-md bg-white">
          <.row
            :for={group <- @ready}
            group={group}
            kind={proposal(group, @create_instead)}
            attention={nil}
          />
        </div>
      </section>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :count, :integer, required: true
  attr :hint, :string, required: true
  attr :attention, :boolean, default: false

  defp section_header(assigns) do
    ~H"""
    <div class="flex items-baseline gap-2">
      <h2 class="text-caps-sm font-medium tracking-wide text-grey-900 uppercase">{@title}</h2>
      <span class={[
        "rounded-full px-1.5 text-xs font-medium",
        if(@attention, do: "bg-brick-200 text-brick-800", else: "bg-grey-200 text-grey-700")
      ]}>
        {@count}
      </span>
      <p class="truncate text-xs text-grey-500 max-md:hidden">{@hint}</p>
    </div>
    """
  end

  attr :group, :map, required: true
  attr :kind, :atom, required: true
  attr :attention, :atom, default: nil

  defp row(assigns) do
    assigns =
      assign(assigns, :attributes, CounterpartyDetection.proposed_attributes(assigns.group))

    ~H"""
    <article
      id={"suggestion-#{:erlang.phash2(@group.key)}"}
      class="flex items-start gap-4 border-b border-grey-200 px-5 py-3 last:border-b-0 max-md:flex-col max-md:items-start max-md:gap-3 max-md:px-4"
    >
      <span class="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-md bg-grey-200 text-grey-800 max-md:hidden">
        <.icon name={CounterpartyHelpers.type_icon_name(@group.buyer)} class="size-4" />
      </span>
      <%!-- Keeps the row open while edits re-render it. --%>
      <details
        class="group min-w-0 flex-1 max-md:w-full"
        phx-mounted={JS.ignore_attributes(["open"])}
      >
        <summary class="flex cursor-pointer list-none flex-col gap-0.5 [&::-webkit-details-marker]:hidden">
          <span class="flex min-w-0 items-center gap-2">
            <h3 class="truncate text-sm font-medium text-grey-900">
              {title(@group, @kind, @attributes)}
            </h3>
            <.badge :if={@attention == :name} tone="danger">
              {gettext("Only the name matches")}
            </.badge>
            <.badge :if={@attention == :registry_name} tone="danger">
              {gettext("Different name in the VAT white list")}
            </.badge>
            <.badge :if={@attention == :registry_missing}>
              {gettext("Not in the VAT white list")}
            </.badge>
            <Lucideicons.chevron_down
              class="size-4 shrink-0 text-grey-500 transition group-open:rotate-180"
              aria-hidden="true"
            />
          </span>
          <p class="truncate text-sm text-grey-600">
            <.summary group={@group} kind={@kind} attributes={@attributes} />
            · {ngettext(
              "%{count} invoice",
              "%{count} invoices",
              length(@group.invoice_ids)
            )} · {Enum.map_join(@group.totals, " + ", &Money.to_string!(&1, fractional_digits: 2))}
          </p>
        </summary>
        <div class="mt-4 flex flex-col gap-4 pb-2 text-base/snug">
          <%!-- Only what cannot be edited is shown as text; the rest are the fields below. --%>
          <dl class="grid grid-cols-[12rem_minmax(0,1fr)] gap-x-4 gap-y-1.5">
            <dt :if={@group.registry} class="text-grey-500">{gettext("VAT white list")}</dt>
            <dd :if={@group.registry} class="text-grey-900">
              {@group.registry.name} · {@group.registry.vat_status}
            </dd>
            <dt class="text-grey-500">{gettext("Invoices")}</dt>
            <dd class="text-grey-900">{Enum.join(@group.invoice_numbers, ", ")}</dd>
            <%= if @kind == :link do %>
              <dt class="text-grey-500">{gettext("Existing counterparty")}</dt>
              <dd class="text-grey-900">
                {Enum.join(
                  Enum.reject(
                    [
                      @group.match.counterparty.display_label,
                      present(CounterpartyHelpers.full_name(@group.match.counterparty)),
                      present(CounterpartyHelpers.identifier(@group.match.counterparty))
                    ],
                    &is_nil/1
                  )
                  |> Enum.uniq(),
                  " · "
                )}
              </dd>
            <% end %>
          </dl>

          <.form
            :let={f}
            :if={@kind == :create}
            for={edit_form(@group, @attributes)}
            phx-change="edit"
            phx-submit="create"
            class="grid grid-cols-[12rem_minmax(0,1fr)] items-center gap-x-4 gap-y-2 border-t border-grey-200 pt-4"
          >
            <input type="hidden" name="key" value={@group.key} />
            <label for={f[:display_name].id} class="font-medium text-grey-900">
              {gettext("Display name")}
            </label>
            <.input field={f[:display_name]} phx-debounce="300" />
            <%= if @group.buyer.type == :company do %>
              <label for={f[:full_name].id} class="text-grey-700">
                {pgettext("counterparty", "Full name")}
              </label>
              <.input field={f[:full_name]} phx-debounce="300" />
              <label for={f[:tax_id].id} class="text-grey-700">{gettext("Identifier")}</label>
              <div class="relative">
                <.input field={f[:tax_id]} phx-debounce="300" input_class="pr-10" />
                <.icon_button
                  :if={@group.buyer.country != "PL" and f[:tax_id].value not in [nil, ""]}
                  label={gettext("Clear the identifier")}
                  class="absolute top-1/2 right-1 -translate-y-1/2"
                  phx-click="clear_field"
                  phx-value-key={@group.key}
                  phx-value-field="tax_id"
                >
                  <Lucideicons.x />
                </.icon_button>
              </div>
            <% else %>
              <label for={f[:given_name].id} class="text-grey-700">{gettext("First name")}</label>
              <.input field={f[:given_name]} phx-debounce="300" />
              <label for={f[:surname].id} class="text-grey-700">{gettext("Last name")}</label>
              <.input field={f[:surname]} phx-debounce="300" />
            <% end %>
            <label for={f[:address].id} class="text-grey-700">{gettext("Address")}</label>
            <.input field={f[:address]} phx-debounce="300" />
            <label for={f[:email].id} class="text-grey-700">{gettext("Email")}</label>
            <.input field={f[:email]} type="email" phx-debounce="300" />
          </.form>
        </div>
      </details>
      <div class="mt-1 flex shrink-0 items-center gap-2">
        <.button
          :if={@attention == :name}
          type="button"
          size="small"
          variant="outline"
          phx-click="create_instead"
          phx-value-key={@group.key}
        >
          {gettext("Create new")}
        </.button>
        <.button
          type="button"
          size="small"
          variant="secondary"
          class="min-w-28"
          phx-click={if @kind == :link, do: "link", else: "create"}
          phx-value-key={@group.key}
        >
          <Lucideicons.check class="size-4" aria-hidden="true" />
          {if @kind == :link, do: gettext("Link"), else: gettext("Create")}
        </.button>
        <.icon_button label={gettext("Skip")} phx-click="skip" phx-value-key={@group.key}>
          <Lucideicons.x />
        </.icon_button>
      </div>
    </article>
    """
  end

  attr :group, :map, required: true
  attr :kind, :atom, required: true
  attr :attributes, :map, required: true

  defp summary(%{kind: :link} = assigns) do
    ~H"""
    <%= if @group.match.reason == :name do %>
      {gettext("Same name as")}
      <.link
        kind="unstyled"
        navigate={Navigation.counterparty_path(@group.match.counterparty.id)}
        class="font-medium text-grey-800 hover:underline"
      >{@group.match.counterparty.display_label}</.link>
    <% else %>
      {gettext("Link with")}
      <.link
        kind="unstyled"
        navigate={Navigation.counterparty_path(@group.match.counterparty.id)}
        class="font-medium text-grey-800 hover:underline"
      >{@group.match.counterparty.display_label}</.link>
      · {gettext("same identifier")}
    <% end %>
    """
  end

  defp summary(%{kind: :create} = assigns) do
    ~H"""
    {gettext("New counterparty")}<span :if={@attributes[:tax_id]}> · {@attributes[:tax_id]}</span>
    """
  end

  # A new counterparty is named as it will be saved; a link keeps the invoice's buyer.
  defp title(_group, :create, attributes), do: attributes[:display_name] || CounterpartyHelpers.full_name(attributes)

  defp title(group, :link, _attributes), do: group.buyer.label

  defp registry_name_differs?(%{registry: %{name: name}, buyer: buyer}) when is_binary(name) do
    CounterpartyDetection.normalize_name(name) !=
      CounterpartyDetection.normalize_name(buyer.full_name)
  end

  defp registry_name_differs?(_group), do: false

  # Form params are string-keyed; the display name falls back to the row title.
  defp edit_form(group, attributes) do
    attributes
    |> Map.take(Enum.map(@editable, &String.to_existing_atom/1))
    |> Map.put_new(:display_name, title(group, :create, attributes))
    # A one-line input would glue the lines of an invoice address together.
    |> Map.update(:address, nil, &(&1 && String.replace(&1, ~r/\s*\n\s*/, ", ")))
    |> Map.new(fn {field, value} -> {Atom.to_string(field), value} end)
    |> to_form(as: "counterparty", id: "edit-#{:erlang.phash2(group.key)}")
  end

  defp present(value) when value in [nil, "", "—"], do: nil
  defp present(value), do: value
end
