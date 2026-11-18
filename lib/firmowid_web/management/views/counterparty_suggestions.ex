defmodule FirmowidWeb.Management.Views.CounterpartySuggestions do
  @moduledoc """
  Buyers of issued invoices without a counterparty (Figma "Nowi kontrahenci"), each with a
  proposal to link an existing counterparty or create one prefilled from the invoices and the
  VAT white list. Skipped buyers stay below, apart from the ones waiting.
  """
  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.Fields, only: [field_row: 1]
  import FirmowidWeb.DesignSystem.Components.IconButton
  import FirmowidWeb.Management.Components.ListToolbar
  import Phoenix.Component, except: [link: 1]

  alias Ash.Error.Invalid
  alias Firmowid.Core.Nip
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.Services.CounterpartyDetection
  alias FirmowidUI.Components.Inputs
  alias FirmowidWeb.Invoicing.Utilities.Navigation, as: InvoicingNavigation
  alias FirmowidWeb.Management.Utilities.CounterpartyHelpers
  alias FirmowidWeb.Management.Utilities.Navigation

  on_mount {FirmowidWeb.Infrastructure.Hooks.RequireAdmin, :default}

  @editable ~w(display_name full_name given_name surname tax_id address email)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Counterparties to review"))
     # The page spaces itself, as the counterparty list does.
     |> assign(:no_padding, true)
     |> assign(:search, "")
     |> assign(:expanded, MapSet.new())
     |> assign(:create_instead, MapSet.new())
     |> assign(:edits, %{})
     |> load_groups()}
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
    case Invoicing.skip_counterparty_suggestion(key, scope: socket.assigns.ash_scope) do
      {:ok, skipped} -> {:noreply, update(socket, :skipped, &Map.put(&1, key, skipped))}
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end

  def handle_event("toggle_details", %{"key" => key}, socket) do
    toggle = fn expanded ->
      if MapSet.member?(expanded, key),
        do: MapSet.delete(expanded, key),
        else: MapSet.put(expanded, key)
    end

    {:noreply, update(socket, :expanded, toggle)}
  end

  def handle_event("search", %{"szukaj" => search}, socket) do
    {:noreply, assign(socket, :search, String.trim(search))}
  end

  defp link(group, socket) do
    case CounterpartyDetection.link(group, group.match.counterparty.id, socket.assigns.ash_scope) do
      :ok ->
        {:noreply,
         socket
         |> drop_group(group.key)
         |> unskip(group.key)
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
         |> unskip(group.key)
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

  # A buyer added to the counterparties has nothing left to skip.
  defp unskip(socket, key) do
    case socket.assigns.skipped[key] do
      nil ->
        socket

      skipped ->
        Invoicing.unskip_counterparty_suggestion!(skipped, scope: socket.assigns.ash_scope)
        update(socket, :skipped, &Map.delete(&1, key))
    end
  end

  defp load_groups(socket) do
    scope = socket.assigns.ash_scope
    groups = CounterpartyDetection.list(scope)

    skipped =
      scope
      |> CounterpartyDetection.skipped()
      |> Map.take(Enum.map(groups, & &1.key))

    socket
    |> assign(:groups, groups)
    |> assign(:skipped, skipped)
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
    {skipped, waiting} =
      assigns.groups
      |> Enum.map(&with_edits(&1, assigns.edits))
      |> Enum.filter(&matches_search?(&1, assigns.search))
      |> Enum.split_with(&Map.has_key?(assigns.skipped, &1.key))

    assigns =
      assign(assigns,
        waiting: waiting,
        skipped_groups: skipped,
        waiting_count: Enum.count(assigns.groups, &(not Map.has_key?(assigns.skipped, &1.key)))
      )

    ~H"""
    <div class="flex w-full flex-col px-4 py-6 md:px-10 md:pt-8 md:pb-12">
      <header class="flex items-end justify-between gap-4">
        <h1 class="text-3xl/[1.3] font-bold text-grey-900">
          {pgettext("management navigation", "Counterparties")}
        </h1>
        <.page_actions>
          <:action>
            <.link
              navigate={
                Navigation.counterparty_new_path(%{
                  powrot_do: Navigation.counterparty_suggestions_path()
                })
              }
              kind="button"
              variant="special"
              data-fab
            >
              <Lucideicons.plus class="size-5" aria-hidden="true" />
              <span class="max-md:sr-only">{gettext("Add counterparty")}</span>
            </.link>
          </:action>
        </.page_actions>
      </header>

      <%!-- The toolbar of the counterparty list, with the scope and the search only. --%>
      <div class="sticky top-0 z-10 bg-grey-100 py-6 max-md:static max-md:z-auto">
        <form class="flex items-center gap-4 max-md:flex-wrap max-md:gap-3" phx-submit="search">
          <.scope_switch label={gettext("Counterparty scope")}>
            <:option navigate={Navigation.counterparties_path(:index)} active={false}>
              {pgettext("people list tab", "Active")}
            </:option>
            <:option navigate={Navigation.counterparties_path(:archive)} active={false}>
              {pgettext("people list tab", "Archived")}
            </:option>
            <:option
              navigate={Navigation.counterparty_suggestions_path()}
              active
              count={if(@waiting_count > 0, do: @waiting_count)}
            >
              {pgettext("people list tab", "New counterparties")}
            </:option>
          </.scope_switch>
          <.expanding_search search={@search} search_label={gettext("Search counterparties")} />
        </form>
      </div>

      <div class="flex flex-col gap-6">
        <section class="flex flex-col gap-2">
          <.group_header title={pgettext("counterparty suggestions", "New counterparties")}>
            {gettext(
              "Companies from invoices that are not in your counterparties yet. Several invoices from one company make one row."
            )}
          </.group_header>

          <%!-- Figma "Pusty stan / Nowi kontrahenci". --%>
          <div
            :if={@waiting == []}
            class="flex flex-col items-center justify-center gap-4 rounded-sm border border-dashed border-grey-300 px-5 py-16 text-center text-sm"
          >
            <Lucideicons.circle_check_big class="size-6 text-moss-700" aria-hidden="true" />
            <div class="flex flex-col gap-0.5">
              <%= if @search != "" do %>
                <p class="leading-[normal] font-medium text-black">
                  {gettext("We could not find the counterparty you are looking for.")}
                </p>
              <% else %>
                <p class="leading-[normal] font-medium text-black">
                  {gettext("Every company from your invoices is already in your counterparties")}
                </p>
                <p class="leading-[1.35] text-grey-600">
                  {gettext(
                    "When an invoice from a new company appears in KSeF, you will see it here."
                  )}
                </p>
              <% end %>
            </div>
          </div>

          <.row
            :for={group <- @waiting}
            group={group}
            kind={proposal(group, @create_instead)}
            attention={attention(group, assigns)}
            expanded={MapSet.member?(@expanded, group.key)}
          />
        </section>

        <section :if={@skipped_groups != []} class="flex flex-col gap-2">
          <.group_header title={pgettext("counterparty suggestions", "Skipped")}>
            {gettext(
              "They do not count as waiting. You can add them to your counterparties at any time."
            )}
          </.group_header>
          <.row
            :for={group <- @skipped_groups}
            group={group}
            kind={proposal(group, @create_instead)}
            attention={attention(group, assigns)}
            expanded={MapSet.member?(@expanded, group.key)}
            skipped={@skipped[group.key]}
          />
        </section>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp group_header(assigns) do
    ~H"""
    <header class="flex items-center gap-2 px-4 py-1 max-md:flex-col max-md:items-start max-md:gap-1">
      <h2 class="text-caps-sm/[normal] font-medium text-grey-900 uppercase">{@title}</h2>
      <p class="text-sm/[1.35] text-grey-600">{render_slot(@inner_block)}</p>
    </header>
    """
  end

  attr :group, :map, required: true
  attr :kind, :atom, required: true
  attr :attention, :atom, default: nil
  attr :expanded, :boolean, required: true
  attr :skipped, :map, default: nil, doc: "the skip of a skipped buyer"

  # Figma "Do przejrzenia" and "Pominięte": the buyer, its invoices in one line, and the
  # decision. "Check" opens what the proposal is made of; a skipped buyer is greyed out.
  defp row(assigns) do
    assigns =
      assign(assigns, :attributes, CounterpartyDetection.proposed_attributes(assigns.group))

    ~H"""
    <article
      id={"suggestion-#{:erlang.phash2(@group.key)}"}
      class="flex flex-col rounded-sm bg-white p-4"
    >
      <div class="flex items-center gap-4 max-md:flex-wrap">
        <span class={[
          "flex size-10 shrink-0 items-center justify-center rounded-sm",
          if(@skipped, do: "bg-grey-100 text-grey-900", else: "bg-teal-200 text-grey-900")
        ]}>
          <Lucideicons.file_chart_column class="size-6" aria-hidden="true" />
        </span>

        <div class="flex min-w-0 flex-1 flex-col gap-1">
          <h3 class={[
            "truncate text-base/[normal] font-medium",
            if(@skipped, do: "text-grey-500", else: "text-black")
          ]}>
            {title(@group, @kind, @attributes)}
          </h3>
          <p class={[
            "flex flex-wrap items-center gap-x-1.5 text-sm/[1.35]",
            if(@skipped, do: "text-grey-400", else: "text-grey-600")
          ]}>
            <%= for {part, index} <- Enum.with_index(meta_parts(@group, @skipped)) do %>
              <span :if={index > 0} aria-hidden="true">·</span>
              <span>{part}</span>
            <% end %>
          </p>
        </div>

        <%!-- Figma "rozwinięty „Sprawdź”": open, the row keeps only "Collapse"; the decision moves
             to the footer, below what it is made of. --%>
        <.button
          :if={@expanded}
          type="button"
          size="small"
          variant="outline"
          class="w-[74px] justify-between transition-opacity duration-300 ease-out motion-reduce:transition-none starting:opacity-0"
          aria-expanded="true"
          aria-controls={"suggestion-details-#{:erlang.phash2(@group.key)}"}
          phx-click="toggle_details"
          phx-value-key={@group.key}
        >
          <Lucideicons.chevron_up class="size-4" aria-hidden="true" />
          {gettext("Collapse")}
        </.button>

        <div
          :if={!@expanded}
          class="flex shrink-0 items-center gap-4 transition-opacity duration-300 ease-out motion-reduce:transition-none max-md:w-full max-md:justify-end starting:opacity-0"
        >
          <div class="flex items-center gap-2">
            <.icon_button
              :if={is_nil(@skipped)}
              label={gettext("Skip")}
              variant="tertiary"
              class="w-8"
              phx-click="skip"
              phx-value-key={@group.key}
            >
              <Lucideicons.x />
            </.icon_button>
            <.button
              type="button"
              size="small"
              variant="tertiary"
              phx-click={if @kind == :link, do: "link", else: "create"}
              phx-value-key={@group.key}
            >
              <Lucideicons.plus class="size-4" aria-hidden="true" />
              {gettext("Add to counterparties")}
            </.button>
          </div>
          <.button
            type="button"
            size="small"
            variant="outline"
            aria-expanded="false"
            aria-controls={"suggestion-details-#{:erlang.phash2(@group.key)}"}
            phx-click="toggle_details"
            phx-value-key={@group.key}
          >
            {gettext("Check")}
          </.button>
        </div>
      </div>

      <%!-- Opens and closes by its height and opacity (300ms), as the landing FAQ does; while
           closed it stays in place, out of reach of the keyboard and screen readers. --%>
      <div
        id={"suggestion-details-#{:erlang.phash2(@group.key)}"}
        aria-hidden={to_string(!@expanded)}
        inert={!@expanded}
        class={[
          "grid transition-[grid-template-rows,opacity] duration-300 ease-in-out motion-reduce:transition-none",
          if(@expanded, do: "grid-rows-[1fr] opacity-100", else: "grid-rows-[0fr] opacity-0")
        ]}
      >
        <div class="min-h-0 overflow-hidden">
          <div class="pt-4 md:pl-14">
            <div class="flex flex-col gap-6 border-t border-grey-200 pt-5">
              <.notice
                :if={(@kind == :create and @group.registry) && is_nil(@attention)}
                tone="success"
                title={gettext("Data from the VAT white list")}
              >
                {gettext(
                  "We filled in the name and address from the VAT taxpayer register. VAT status: %{status}.",
                  status: @group.registry.vat_status
                )}
              </.notice>
              <.notice
                :if={@attention == :registry_missing}
                title={gettext("Not in the VAT white list")}
              >
                {gettext(
                  "We did not find this NIP in the VAT taxpayer register. Check the number before you add the counterparty."
                )}
              </.notice>
              <.notice
                :if={@attention == :registry_name}
                title={gettext("Different name in the VAT white list")}
              >
                {gettext(
                  "The VAT taxpayer register lists this NIP as %{name}. Check the data before you add the counterparty.",
                  name: @group.registry.name
                )}
              </.notice>
              <.notice :if={@attention == :name} title={gettext("Only the name matches")}>
                {gettext(
                  "%{name} is already in your counterparties, without this identifier. Adding links the invoices to it; if it is another company, create a new one.",
                  name: @group.match.counterparty.display_label
                )}
                <:action>
                  <.button
                    type="button"
                    size="small"
                    variant="outline"
                    phx-click="create_instead"
                    phx-value-key={@group.key}
                  >
                    {gettext("Create new")}
                  </.button>
                </:action>
              </.notice>

              <section :if={@kind == :create} class="flex flex-col gap-4">
                <h4 class={section_label_styles()}>
                  {pgettext("counterparty suggestions", "Counterparty details")}
                </h4>
                <.form
                  :let={f}
                  id={"edit-#{:erlang.phash2(@group.key)}"}
                  for={edit_form(@group, @attributes)}
                  phx-change="edit"
                  phx-submit="create"
                  class="grid grid-cols-2 gap-4 max-md:grid-cols-1"
                >
                  <input type="hidden" name="key" value={@group.key} />
                  <%= if @group.buyer.type == :company do %>
                    <.field label={gettext("Display name")} field={f[:display_name]} />
                    <.field label={pgettext("counterparty", "Full name")} field={f[:full_name]} />
                    <.field_row
                      label={gettext("Identifier")}
                      for={f[:tax_id].id}
                      class="gap-1.5!"
                    >
                      <div class="relative">
                        <%!-- A NIP the VAT white list confirmed stays as on the invoices. --%>
                        <.input
                          field={f[:tax_id]}
                          phx-debounce="300"
                          disabled={not is_nil(@group.registry)}
                          input_class={[
                            "pr-10 disabled:cursor-not-allowed disabled:border-grey-200 disabled:bg-grey-100 disabled:text-grey-700",
                            field_input_styles()
                          ]}
                        />
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
                    </.field_row>
                  <% else %>
                    <.field label={gettext("First name")} field={f[:given_name]} />
                    <.field label={gettext("Last name")} field={f[:surname]} />
                    <.field label={gettext("Display name")} field={f[:display_name]} />
                  <% end %>
                  <.field
                    label={gettext("Email (optional)")}
                    field={f[:email]}
                    type="email"
                    placeholder={gettext("name@company.com")}
                  />
                  <.field label={gettext("Address")} field={f[:address]} class="col-span-full" />
                </.form>
              </section>

              <section :if={@kind == :link} class="flex flex-col gap-2.5">
                <h4 class={section_label_styles()}>{gettext("Existing counterparty")}</h4>
                <.link
                  kind="unstyled"
                  navigate={Navigation.counterparty_path(@group.match.counterparty.id)}
                  class="text-base/[1.35] text-grey-900 hover:underline"
                >
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
                </.link>
              </section>

              <%!-- Figma "Faktury": the numbers as sales chips. --%>
              <section class="flex flex-col gap-2.5">
                <h4 class={section_label_styles()}>
                  {gettext("Sales invoices · %{count}", count: length(@group.invoice_numbers))}
                </h4>
                <%!-- Each chip opens its invoice in a new tab; Cmd/Ctrl-click keeps it in the background. --%>
                <ul class="flex flex-wrap gap-2">
                  <li :for={{id, number} <- Enum.zip(@group.invoice_ids, @group.invoice_numbers)}>
                    <.link
                      kind="unstyled"
                      redirect={InvoicingNavigation.sales_invoice_show_path(id)}
                      target="_blank"
                      rel="noopener"
                      class="block rounded-full bg-teal-200 px-4 py-1 text-sm/[1.35] text-teal-700 transition-colors hover:bg-teal-300 focus-visible:outline-2 focus-visible:outline-teal-700"
                    >
                      {number}
                    </.link>
                  </li>
                </ul>
              </section>

              <footer class="flex items-center justify-between gap-4 max-md:flex-col max-md:items-stretch">
                <p class="text-sm/[1.35] text-grey-500">
                  <%= if @kind == :link do %>
                    {gettext("After adding, the invoices are linked to %{name}.",
                      name: @group.match.counterparty.display_label
                    )}
                  <% else %>
                    {gettext(
                      "After adding, the counterparty goes to the active list with its invoices."
                    )}
                  <% end %>
                </p>
                <.button
                  :if={@kind == :create}
                  type="submit"
                  form={"edit-#{:erlang.phash2(@group.key)}"}
                  size="small"
                  variant="special"
                >
                  <Lucideicons.plus class="size-4" aria-hidden="true" />
                  {gettext("Add to counterparties")}
                </.button>
                <.button
                  :if={@kind == :link}
                  type="button"
                  size="small"
                  variant="special"
                  phx-click="link"
                  phx-value-key={@group.key}
                >
                  <Lucideicons.plus class="size-4" aria-hidden="true" />
                  {gettext("Add to counterparties")}
                </.button>
              </footer>
            </div>
          </div>
        </div>
      </div>
    </article>
    """
  end

  defp notice_tone_styles("neutral"), do: "bg-grey-100"
  defp notice_tone_styles("success"), do: "bg-moss-100"

  defp section_label_styles, do: "text-caps-sm/[1.35] font-medium tracking-[0.22px] text-grey-900 uppercase"

  # Figma "Pole formularza": 16px text, a teal border while focused on the sales side.
  defp field_input_styles,
    do:
      "text-base/[1.35] text-black placeholder:text-grey-500 focus:border-teal-300 focus:shadow-[inset_0_0_0_1px_var(--color-teal-300)]"

  attr :label, :string, required: true
  attr :field, Phoenix.HTML.FormField, required: true
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(type placeholder)

  # Figma "Pole formularza": the label above the field, 6px apart.
  defp field(assigns) do
    ~H"""
    <.field_row label={@label} for={@field.id} class={["gap-1.5!", @class]}>
      <.input field={@field} phx-debounce="300" input_class={field_input_styles()} {@rest} />
    </.field_row>
    """
  end

  attr :title, :string, required: true
  attr :tone, :string, values: ~w(neutral success), default: "neutral"
  slot :inner_block, required: true
  slot :action

  # Figma "Alert / Neutralny": grey fill, a 20px triangle, the title over one sentence. The
  # design system's neutral `alert` is still the older white one with an info icon. `success`
  # keeps the layout in the system's moss tone (no Figma frame for it yet).
  defp notice(assigns) do
    ~H"""
    <div
      role="status"
      class={["flex items-start gap-3 rounded-sm px-4 py-3", notice_tone_styles(@tone)]}
    >
      <Lucideicons.triangle_alert
        :if={@tone == "neutral"}
        class="size-5 shrink-0 text-black"
        aria-hidden="true"
      />
      <Lucideicons.circle_check_big
        :if={@tone == "success"}
        class="size-5 shrink-0 text-moss-700"
        aria-hidden="true"
      />
      <div class="flex min-w-0 flex-1 flex-col gap-0.5 text-sm/[1.35]">
        <p class={["font-medium", if(@tone == "success", do: "text-moss-900", else: "text-grey-900")]}>
          {@title}
        </p>
        <p class={[if(@tone == "success", do: "text-moss-900", else: "text-grey-600")]}>
          {render_slot(@inner_block)}
        </p>
        <div :if={@action != []} class="mt-2 flex flex-wrap gap-2">{render_slot(@action)}</div>
      </div>
    </div>
    """
  end

  # Figma "Do przejrzenia": the identifier, the invoices, the amount and when the last one came;
  # a skipped buyer shows when it was skipped instead.
  defp meta_parts(group, skipped) do
    count = length(group.invoice_ids)
    amount = Enum.map_join(group.totals, " + ", &Money.to_string!(&1, fractional_digits: 2))
    date = group.last_issue_date && Calendar.strftime(group.last_issue_date, "%d.%m.%Y")

    Enum.reject(
      [
        identifier_label(group.buyer),
        if(count == 1,
          do: gettext("sales invoice %{number}", number: hd(group.invoice_numbers)),
          else: ngettext("%{count} sales invoice", "%{count} sales invoices", count)
        ),
        if(count == 1, do: amount, else: gettext("%{amount} in total", amount: amount)),
        cond do
          skipped ->
            gettext("skipped %{date}", date: Calendar.strftime(skipped.skipped_on, "%d.%m.%Y"))

          is_nil(date) ->
            nil

          count == 1 ->
            gettext("KSeF, %{date}", date: date)

          true ->
            gettext("last: KSeF, %{date}", date: date)
        end
      ],
      &is_nil/1
    )
  end

  # A Polish NIP in the usual 123-456-78-90 grouping; other identifiers as on the invoice.
  defp identifier_label(%{pesel: pesel}) when pesel not in [nil, ""], do: "PESEL #{pesel}"

  defp identifier_label(%{tax_id: tax_id, country: "PL"}) when is_binary(tax_id) do
    if Nip.valid?(tax_id) do
      digits = Nip.normalize_digits(tax_id)

      "NIP " <>
        Enum.join(
          for({at, len} <- [{0, 3}, {3, 3}, {6, 2}, {8, 2}], do: String.slice(digits, at, len)),
          "-"
        )
    else
      tax_id
    end
  end

  defp identifier_label(%{tax_id: tax_id}) when tax_id not in [nil, ""], do: tax_id
  defp identifier_label(_buyer), do: nil

  defp matches_search?(_group, ""), do: true

  defp matches_search?(group, search) do
    needle = String.downcase(search)

    Enum.any?([group.buyer.label, group.buyer.tax_id, group.buyer.pesel], fn value ->
      is_binary(value) and String.contains?(String.downcase(value), needle)
    end)
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
