defmodule FirmowidWeb.Settings.Components.ProfileTab do
  @moduledoc """
  Function components for the profile settings route.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.Settings.Components.EditButton
  import FirmowidWeb.Timetracker.Components.DelegationsList
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter
  alias FirmowidWeb.Settings.Components.Helpers
  alias FirmowidWeb.Timetracker.Utilities.LeavePresentation
  alias FirmowidWeb.Timetracker.Utilities.Navigation
  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the self-profile route content.
  """
  @spec profile_tab(map()) :: Rendered.t()
  attr :current_user, :map, required: true
  attr :ash_scope, :map, required: true
  attr :user_form, :map, required: true
  attr :contract_form, :map, default: nil
  attr :editing_profile_employment, :boolean, required: true
  attr :editing_profile_finance, :boolean, required: true
  attr :editing_profile_contact, :boolean, required: true
  attr :leave_requests, :list, required: true
  attr :leave_request_form, :map, required: true
  attr :leave_request_upload, :map, required: true
  attr :leave_search, :string, required: true
  attr :leave_days, :integer, required: true
  attr :projects, :list, required: true
  attr :projects_total, :integer, required: true
  attr :projects_date, :any, required: true
  attr :pending_contract, :map, default: nil
  attr :latest_contract, :map, default: nil
  attr :signed_contract_upload, :map, default: nil
  attr :delegations, :list, required: true

  def profile_tab(assigns) do
    ~H"""
    <div class="grid items-start gap-8 lg:grid-cols-2 lg:gap-16">
      <div class="space-y-14">
        <.employment_section
          current_user={@current_user}
          contract_form={@contract_form}
          editing_profile_employment={@editing_profile_employment}
          pending_contract={@pending_contract}
          latest_contract={@latest_contract}
          signed_contract_upload={@signed_contract_upload}
          ash_scope={@ash_scope}
        />
        <.finance_section
          current_user={@current_user}
          user_form={@user_form}
          editing_profile_finance={@editing_profile_finance}
        />
        <.contact_section
          current_user={@current_user}
          user_form={@user_form}
          editing_profile_contact={@editing_profile_contact}
        />
      </div>

      <.projects_section
        projects={@projects}
        total_duration={@projects_total}
        date={@projects_date}
      />

      <div class="grid items-start gap-5 lg:col-span-2 lg:grid-cols-2">
        <.live_component
          module={FirmowidWeb.Documents.Components.DocumentsSection}
          id="profile-documents"
          user={@current_user}
          scope={@ash_scope}
          variant={:profile}
        />
        <.leave_section
          leave_requests={@leave_requests}
          leave_request_form={@leave_request_form}
          leave_request_upload={@leave_request_upload}
          leave_search={@leave_search}
          leave_days={@leave_days}
        />
      </div>
      <.delegations_section delegations={@delegations} />
    </div>
    """
  end

  attr :delegations, :list, required: true

  defp delegations_section(assigns) do
    ~H"""
    <section class="flex w-full flex-col gap-6 rounded-lg bg-white p-6 shadow lg:col-span-2">
      <div class="flex items-start justify-between gap-3">
        <h2 class="text-grey-900 text-base leading-none font-medium">Delegacje</h2>
        <.link
          kind="unstyled"
          navigate={~p"/delegacje/dodaj"}
          class="text-turquoise-700 inline-flex items-center gap-2 text-sm font-medium"
        >
          <.icon name="hero-map" class="size-4" /> Zaplanuj delegację
        </.link>
      </div>
      <.delegations_list delegations={@delegations} />
    </section>
    """
  end

  attr :title, :string, required: true
  attr :action, :any, default: nil
  attr :action_label, :string, default: nil
  slot :inner_block, required: true

  defp profile_section(assigns) do
    ~H"""
    <section class="space-y-4">
      <div class="flex min-h-8 items-center gap-1">
        <h2 class="text-grey-900 text-base leading-none font-medium">{@title}</h2>

        <span
          :if={@action}
          id={"settings-#{@action}-tooltip"}
          phx-hook="Tippy"
          data-tippy-content={@action_label || "Edytuj #{@title}"}
          data-tippy-delay="100"
          data-tippy-size="small"
        >
          <.edit_button
            type="button"
            phx-click={@action}
            aria-label={@action_label || "Edytuj #{@title}"}
          />
        </span>
      </div>

      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp detail_row(assigns) do
    ~H"""
    <Helpers.settings_display_field
      label={@label}
      class="justify-center"
      value_class="break-words"
    >
      {render_slot(@inner_block)}
    </Helpers.settings_display_field>
    """
  end

  attr :current_user, :map, required: true
  attr :contract_form, :map, default: nil
  attr :editing_profile_employment, :boolean, required: true
  attr :pending_contract, :map, default: nil
  attr :latest_contract, :map, default: nil
  attr :signed_contract_upload, :map, default: nil
  attr :ash_scope, :map, default: nil

  defp employment_section(assigns) do
    ~H"""
    <div
      :if={@pending_contract}
      id="contract-signing-box"
      data-expanded="false"
      class="group space-y-4"
    >
      <div class="border-turquoise-200 flex-col gap-2 rounded-lg border p-4 group-data-[expanded=false]:flex group-data-[expanded=true]:hidden">
        <h3 class="text-turquoise-700 flex items-center gap-1 text-sm font-medium">
          <Lucideicons.file_text class="size-4" /> Nowa umowa
        </h3>
        <p class="text-grey-700 text-sm">
          Czeka na ciebie nowa umowa. Podpisz ją profilem zaufanym, aby sfinalizować formalności.
        </p>
        <div class="flex items-center justify-between">
          <p class="text-grey-700 text-sm">
            Podpisz do: {present_date(@pending_contract.signed_at)}
          </p>
          <.button
            type="button"
            variant="primary"
            accent="turquoise"
            size="small"
            phx-click={
              JS.toggle_attribute({"data-expanded", "true", "false"},
                to: "#contract-signing-box"
              )
            }
          >
            Rozpocznij
          </.button>
        </div>
      </div>

      <div class="border-turquoise-200 flex flex-col gap-3 rounded-lg border p-4 group-data-[expanded=false]:hidden group-data-[expanded=true]:flex">
        <div class="flex items-center justify-between">
          <h3 class="text-turquoise-700 flex items-center gap-1 text-sm font-medium">
            <Lucideicons.file_text class="size-4" /> Nowa umowa
          </h3>
          <p class="text-grey-500 text-sm">
            Podpisz do: {present_date(@pending_contract.signed_at)}
          </p>
        </div>

        <ol class="text-grey-700 list-decimal space-y-2 pl-4 text-sm">
          <li>
            <span class="pr-2">Zapoznaj się z dokumentem</span>
            <.link
              kind="button"
              variant="outline"
              size="small"
              redirect={~p"/zarzadzanie/umowy/#{@pending_contract.id}"}
              download
            >
              <Lucideicons.file_text class="size-4" /> <span class="font-medium">Umowa</span>
            </.link>
          </li>
          <li>
            <span>Podpisz dokument</span>
            <.link
              kind="button"
              size="small"
              variant="plain"
              class="text-turquoise-700 pl-0"
              external="https://podpis.gov.pl/podpisz-dokument-elektronicznie/"
              target="_blank"
            >
              <span class="font-medium">Profilem Zaufanym</span>
              <Lucideicons.external_link class="size-4" />
            </.link>
          </li>
          <li>
            <p>Wgraj podpisaną umowę</p>
            <form phx-change="validate_signed_contract">
              <label
                id={"signed-contract-drop-#{@signed_contract_upload.ref}"}
                phx-drop-target={@signed_contract_upload.ref}
                phx-hook="FileUploadDragState"
                data-dragging="false"
                class={[
                  "border-turquoise-200 data-[dragging=true]:bg-turquoise-100 data-[dragging=true]:border-turquoise-400 group mt-4 flex w-full flex-col items-center justify-center gap-2 rounded-md border-dashed py-6 transition-colors",
                  if(Enum.empty?(@signed_contract_upload.entries),
                    do: "cursor-pointer border-2 border-dashed px-10",
                    else: "bg-turquoise-100 px-8"
                  )
                ]}
              >
                <span
                  :if={Enum.empty?(@signed_contract_upload.entries)}
                  class="text-grey-700 flex items-center gap-1 text-sm font-medium group-data-[dragging=true]:hidden"
                >
                  Przeciągnij PDF lub <span class="text-turquoise-700">Wybierz plik</span>
                </span>
                <span
                  :if={Enum.empty?(@signed_contract_upload.entries)}
                  class="text-turquoise-700 hidden group-data-[dragging=true]:flex"
                >
                  Upuść plik
                </span>
                <.live_file_input upload={@signed_contract_upload} class="sr-only" />

                <div
                  :for={entry <- @signed_contract_upload.entries}
                  class="text-turquoise-700 z-10 w-full text-sm"
                >
                  <div class="flex items-center justify-between">
                    <span class="flex min-w-0 items-center gap-1 truncate font-medium"><Lucideicons.file_text class="size-4" /> {entry.client_name}</span>
                    <span :if={!entry.done?} class="shrink-0 tabular-nums">{entry.progress}%</span>
                    <.button
                      variant="unstyled"
                      type="button"
                      class="hover:text-grey-700 text-grey-500 shrink-0"
                      phx-click="cancel_signed_contract"
                      phx-value-ref={entry.ref}
                    >
                      <Lucideicons.x class="size-4" />
                    </.button>
                  </div>
                </div>
              </label>
            </form>
            <p
              :for={error <- upload_errors(@signed_contract_upload)}
              class="mt-2 text-sm text-red-600"
            >
              {upload_error_to_string(error)}
            </p>
          </li>
        </ol>
        <div class="mt-1 flex w-fit gap-3 self-end">
          <.button
            type="button"
            variant="ghost"
            size="small"
            phx-click={
              JS.toggle_attribute({"data-expanded", "true", "false"},
                to: "#contract-signing-box"
              )
            }
          >
            Wróć później
          </.button>
          <.button
            type="button"
            accent="turquoise"
            size="small"
            phx-click="submit_signed_contract"
            phx-disable-with="Przesyłanie..."
            disabled={contract_upload_submit_disabled?(@signed_contract_upload)}
          >
            Prześlij umowę
          </.button>
        </div>
      </div>
    </div>

    <.profile_section
      title="Informacje o zatrudnieniu"
      action={
        if(!@editing_profile_employment and can_edit_contract?(@latest_contract, @ash_scope),
          do: "toggle_editing_profile_employment"
        )
      }
      action_label="Edytuj informacje o zatrudnieniu"
    >
      <%= if @editing_profile_employment do %>
        <.form for={@contract_form} phx-submit="save_contract_employment" class="space-y-4">
          <div class="space-y-2">
            <.row_input field={@contract_form[:position]} label="Stanowisko" type="text" />
            <Helpers.settings_field
              label="Rodzaj umowy"
              layout={:row}
              block_class="flex items-center"
              for={@contract_form[:contract_type].id}
            >
              <.input
                type="select"
                field={@contract_form[:contract_type]}
                options={[
                  {"Umowa o pracę", :uop},
                  {"B2B", :b2b},
                  {"Umowa zlecenie", :uz},
                  {"Umowa o dzieło", :uod}
                ]}
                container_class="w-full"
                new
              />
            </Helpers.settings_field>
            <.row_input field={@contract_form[:starts_at]} label="Obowiązuje od" type="date" />
          </div>

          <div class="flex w-full justify-end gap-3">
            <.button
              type="button"
              variant="ghost"
              size="small"
              phx-click="toggle_editing_profile_employment"
            >
              Anuluj
            </.button>

            <.button type="submit" variant="success" size="small">
              Zapisz
            </.button>
          </div>
        </.form>
      <% else %>
        <div class="space-y-2">
          <.detail_row :if={@latest_contract} label="Umowa">
            <.link
              kind="button"
              variant="outline"
              size="small"
              redirect={~p"/zarzadzanie/umowy/#{@latest_contract.id}"}
              download
            >
              <Lucideicons.file_text class="size-4" /> <span class="font-medium">Pobierz umowę</span>
            </.link>
          </.detail_row>
          <.detail_row label="Stanowisko">
            {present(@latest_contract && @latest_contract.position)}
          </.detail_row>
          <.detail_row label="Rodzaj umowy">
            {format_contract_type(@latest_contract && @latest_contract.contract_type)}
          </.detail_row>
          <.detail_row label="Obowiązuje od">
            {present_date(@latest_contract && @latest_contract.starts_at)}
          </.detail_row>
        </div>
      <% end %>
    </.profile_section>
    """
  end

  attr :current_user, :map, required: true
  attr :user_form, :map, required: true
  attr :editing_profile_finance, :boolean, required: true

  defp finance_section(assigns) do
    ~H"""
    <.profile_section
      title="Finanse"
      action={if(!@editing_profile_finance, do: "toggle_editing_profile_finance")}
      action_label="Edytuj finanse"
    >
      <%= if @editing_profile_finance do %>
        <.form for={@user_form} phx-submit="save_profile_finance" class="space-y-4">
          <div class="space-y-2">
            <.row_input field={@user_form[:bank_account_number]} label="Nr konta" type="text" />
          </div>

          <div class="flex w-full justify-end gap-3">
            <.button
              type="button"
              variant="ghost"
              phx-click="toggle_editing_profile_finance"
              size="small"
            >
              Anuluj
            </.button>
            <.button type="submit" variant="success" size="small">Zapisz</.button>
          </div>
        </.form>
      <% else %>
        <div class="w-full space-y-2">
          <.detail_row label="Nr konta">{present(@current_user.bank_account_number)}</.detail_row>
        </div>
      <% end %>
    </.profile_section>
    """
  end

  attr :current_user, :map, required: true
  attr :user_form, :map, required: true
  attr :editing_profile_contact, :boolean, required: true

  defp contact_section(assigns) do
    ~H"""
    <.profile_section
      title="Dane korespondencyjne"
      action={if(!@editing_profile_contact, do: "toggle_editing_profile_contact")}
      action_label="Edytuj dane korespondencyjne"
    >
      <%= if @editing_profile_contact do %>
        <.form
          for={@user_form}
          phx-submit="save_profile_contact"
          phx-change="validate_profile_contact"
          class="space-y-4"
        >
          <div class="space-y-2">
            <.row_input field={@user_form[:phone]} label="Numer telefonu" type="tel" />
            <.row_input field={@user_form[:slack_url]} label="Slack" type="url" />
            <.row_input
              field={@user_form[:residence_address]}
              label="Adres zamieszkania"
              type="textarea"
              label_class="pt-1.5 self-start"
            />

            <Helpers.settings_field
              label_class="max-w-56 ml-auto"
              label="Adres korespondencyjny jest taki sam jak adres zamieszkania"
              layout={:row}
              block_class="flex items-center"
              for={@user_form[:is_same_correspondence_address].id}
            >
              <.switch
                field={@user_form[:is_same_correspondence_address]}
                class="w-12"
                color="turquoise"
              />
            </Helpers.settings_field>

            <%= if not Phoenix.HTML.Form.normalize_value("switch", @user_form[:is_same_correspondence_address].value) do %>
              <.row_input
                field={@user_form[:correspondence_address]}
                label="Adres korespondencyjny"
                type="textarea"
                label_class="pt-1.5 self-start"
              />
            <% end %>
          </div>

          <div class="flex w-full justify-end gap-3">
            <.button
              type="button"
              variant="ghost"
              size="small"
              phx-click="toggle_editing_profile_contact"
            >
              Anuluj
            </.button>
            <.button type="submit" variant="success" size="small">Zapisz</.button>
          </div>
        </.form>
      <% else %>
        <div class="w-full space-y-2">
          <.detail_row label="Numer telefonu">{present(@current_user.phone)}</.detail_row>
          <.detail_row label="Slack">
            <span :if={slack_present?(@current_user)}>{present_slack(@current_user)}</span>
            <span :if={!slack_present?(@current_user)}>—</span>
          </.detail_row>
          <.detail_row label="Adres zamieszkania">
            {present(@current_user.residence_address)}
          </.detail_row>
          <.detail_row
            :if={@current_user.correspondence_address not in [nil, ""]}
            label="Adres korespondencyjny"
          >
            {present(@current_user.correspondence_address)}
          </.detail_row>
        </div>
      <% end %>
    </.profile_section>
    """
  end

  attr :leave_requests, :list, required: true
  attr :leave_request_form, :map, required: true
  attr :leave_request_upload, :map, required: true
  attr :leave_search, :string, required: true
  attr :leave_days, :integer, required: true

  defp leave_section(assigns) do
    assigns =
      assign(
        assigns,
        :filtered_leave_requests,
        LeavePresentation.filter_by_search(assigns.leave_requests, assigns.leave_search)
      )

    ~H"""
    <section class="flex size-full flex-col gap-6 rounded-lg bg-white p-6 shadow">
      <div class="flex items-start justify-between gap-3">
        <h2 class="text-grey-900 text-base leading-none font-medium">Nieobecności</h2>
        <div class="flex items-center gap-3">
          <form class="flex gap-4" phx-submit="search_leave_requests">
            <div
              id="profile-leave-search-container"
              data-expanded={to_string(@leave_search != "")}
              class="data-[expanded=true]:bg-greyButtonBg group flex items-center justify-center rounded-lg transition-shadow data-[expanded=true]:focus-within:ring-2"
            >
              <.input
                type="text"
                name="szukaj"
                value={@leave_search}
                placeholder="Szukaj wniosku"
                phx-change="search_leave_requests"
                phx-debounce="300"
                input_class="py-0 px-1 bg-transparent border-none"
                class="group w-0 border-transparent px-0 opacity-0 transition-[width,opacity,padding] duration-200 ease-in-out group-data-[expanded=true]:w-42 group-data-[expanded=true]:px-2 group-data-[expanded=true]:opacity-100 focus:border-none focus:ring-0 focus:outline-hidden lg:group-data-[expanded=true]:w-56"
              />
              <.button
                type="button"
                size="small"
                variant="outline"
                class="py-2 group-data-[expanded=true]:rounded-r-lg"
                phx-click={
                  JS.toggle_attribute({"data-expanded", "true", "false"},
                    to: "#profile-leave-search-container"
                  )
                  |> JS.focus(to: "#profile-leave-search-container input")
                }
              >
                <Lucideicons.search />
              </.button>
            </div>
          </form>
          <.button
            type="button"
            variant="secondary"
            size="small"
            phx-click={show_modal("leave-request-modal")}
            class="py-1.75"
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Złóż wniosek
          </.button>
        </div>
      </div>
      <div class="flex items-center gap-3">
        <div class="bg-grey-50 text-grey-500 rounded px-3 py-1 text-sm">
          Wykorzystane w tym roku:
          <span class="text-grey-700 pl-1 font-medium">{@leave_days} dni</span>
        </div>
      </div>
      <div class="scrollbar-card h-100 max-h-100 overflow-y-auto pr-1">
        <ul class="divide-grey-100 divide-y">
          <li
            :for={request <- @filtered_leave_requests}
            class="flex items-center gap-3 py-3 first:pt-0 last:pb-0"
          >
            <span class="bg-grey-100 text-grey-700 flex size-6.5 items-center justify-center rounded">
              <.reason_icon reason={request.reason} />
            </span>
            <span class="min-w-0 flex-1 truncate">
              {LeavePresentation.reason_label(request.reason, :short)}
            </span>
            <span class="shrink-0 tabular-nums">
              {LeavePresentation.format_range(request.starts_on, request.ends_on)}
            </span>
            <span class={leave_status_badge_styles(request.status)}>
              {LeavePresentation.status_label(request.status)}
            </span>
          </li>
        </ul>
        <div
          :if={Enum.empty?(@filtered_leave_requests)}
          class="bg-grey-50 text-grey-700 flex size-full items-center justify-center rounded-lg text-sm"
        >
          <p>
            Brak wniosków o nieobecności.
          </p>
        </div>
      </div>

      <.modal id="leave-request-modal" class="max-w-xl">
        <h2 class="mb-8 text-xl font-medium">
          Zgłoszenie nieobecności
        </h2>
        <.form
          for={@leave_request_form}
          id="leave-request-form"
          phx-submit="create_leave_request"
          phx-change="validate_leave_request_attachment"
          class="space-y-8"
        >
          <div>
            <p class="text-grey-700 mb-2 text-sm">
              Rodzaj nieobecności:
            </p>
            <div class="flex flex-wrap gap-2">
              <.button
                :for={reason <- leave_reasons()}
                type="button"
                variant="outline"
                size="small"
                phx-click="select_leave_reason"
                data-active={to_string(@leave_request_form[:reason].value) == to_string(reason)}
                phx-value-reason={reason}
                class="bg-grey-100 border-grey-100 text-grey-700 inline-flex items-center gap-2 rounded-2xl! px-4 py-1 text-sm transition data-active:border-orange-200 data-active:bg-orange-200 data-active:text-orange-700"
              >
                {String.downcase(LeavePresentation.reason_label(reason, :short))}
                <.reason_icon reason={reason} />
              </.button>
            </div>
            <.input
              type="hidden"
              name="leave_request[reason]"
              value={@leave_request_form[:reason].value}
            />
          </div>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <.label
              for={@leave_request_form[:starts_on].id}
              class="text-grey-700 flex items-center gap-2 text-sm"
            >
              Od:
              <.input
                new={true}
                field={@leave_request_form[:starts_on]}
                is_tooltip={true}
                type="date"
              />
            </.label>
            <.label
              for={@leave_request_form[:ends_on].id}
              class="text-grey-700 flex items-center gap-2 text-sm"
            >
              Do:
              <.input new={true} field={@leave_request_form[:ends_on]} is_tooltip={true} type="date" />
            </.label>
          </div>
          <div>
            <.label
              for={@leave_request_form[:note].id}
              class="text-grey-700 flex flex-col gap-2 text-sm"
            >
              Dodatkowe informacje:
              <.input
                field={@leave_request_form[:note]}
                type="textarea"
                new={true}
                rows="8"
                class="mb-4"
              />
            </.label>
            <.button
              as="label"
              for={@leave_request_upload.ref}
              variant="secondary"
              size="small"
              type="button"
            >
              <.icon name="hero-cloud-arrow-up" class="size-4" /> Wgraj załącznik
              <.live_file_input upload={@leave_request_upload} class="sr-only" />
            </.button>
            <div
              :for={entry <- @leave_request_upload.entries}
              class="text-grey-600 mt-2 space-y-1 text-sm"
            >
              <div class="flex items-center gap-2">
                <span class="min-w-0 truncate">{entry.client_name}</span>
                <span :if={!entry.done?} class="shrink-0 tabular-nums">{entry.progress}%</span>
                <.button
                  variant="unstyled"
                  type="button"
                  class="hover:text-grey-700 text-grey-500 shrink-0"
                  phx-click="cancel_leave_request_attachment"
                  phx-value-ref={entry.ref}
                >
                  Usuń
                </.button>
              </div>
              <p
                :for={error <- upload_errors(@leave_request_upload, entry)}
                class="text-sm text-red-600"
              >
                {leave_upload_error_to_string(error)}
              </p>
            </div>
            <p
              :for={error <- upload_errors(@leave_request_upload)}
              class="mt-2 text-sm text-red-600"
            >
              {leave_upload_error_to_string(error)}
            </p>
          </div>
          <div class="flex justify-end">
            <.button
              type="submit"
              variant="primary"
              size="big"
              phx-disable-with="Wysyłanie..."
              disabled={leave_attachment_submit_disabled?(@leave_request_upload)}
            >
              Wyślij
            </.button>
          </div>
        </.form>
      </.modal>
    </section>
    """
  end

  attr :projects, :list, required: true
  attr :total_duration, :integer, required: true
  attr :date, :integer, required: true

  defp projects_section(assigns) do
    ~H"""
    <div class="flex flex-col items-end gap-4">
      <section class="flex w-full flex-col gap-6 rounded-lg bg-white p-6 shadow">
        <div class="flex items-start justify-between gap-3">
          <div class="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-1">
            <h2 class="text-grey-900 text-base leading-none font-medium">Twoje projekty</h2>
            <span class="text-grey-500 text-sm">
              {TimeFormatter.format_date(@date, "LLLL y")}
            </span>
          </div>
          <span class="text-grey-700 shrink-0 tabular-nums">
            {format_project_duration(@total_duration)}
          </span>
        </div>

        <ul :if={@projects != []} class="space-y-3">
          <li :for={project <- @projects} class="flex items-center justify-between gap-3">
            <span class="bg-turquoise-200 text-turquoise-700 rounded-full px-3 py-1 text-sm/snug font-medium">
              {project.name}
            </span>
            <span class="text-grey-500 shrink-0 text-sm tabular-nums">
              {format_project_duration(project.duration)}
            </span>
          </li>
        </ul>

        <p :if={@projects == []} class="text-grey-500 text-sm">
          Brak przepracowanego czasu w tym miesiącu.
        </p>
      </section>
      <.link
        kind="unstyled"
        navigate={Navigation.hours_record_index_path(@date)}
        class="hover:text-grey-900 text-grey-700 inline-flex items-center gap-1 text-sm font-medium"
      >
        Zobacz ewidencję <.icon name="hero-chevron-right-mini" class="size-4" />
      </.link>
    </div>
    """
  end

  defp format_project_duration(seconds) when seconds < 60, do: "0h 0min"

  defp format_project_duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}min"
  end

  attr :reason, :atom, required: true
  attr :class, :string, default: "size-4"

  defp reason_icon(assigns) do
    ~H"""
    <%= cond do %>
      <% @reason in [:sick, :indisposition] -> %>
        <Lucideicons.cross class={@class} />
      <% @reason in [:rest, :vacation] -> %>
        <Lucideicons.sun class={@class} />
      <% @reason in [:unpaid, :other] -> %>
        <Lucideicons.slash class={@class} />
    <% end %>
    """
  end

  defp leave_status_badge_styles(status) do
    [
      "w-31 shrink-0 rounded-full px-3 py-1 text-center text-sm",
      LeavePresentation.status_badge_styles(status)
    ]
  end

  attr :field, :map, required: true
  attr :label, :string, required: true
  attr :type, :string, required: true
  attr :label_class, :string, default: nil

  defp row_input(assigns) do
    ~H"""
    <Helpers.settings_field
      label={@label}
      layout={:row}
      for={@field.id}
      label_class={@label_class}
    >
      <.input field={@field} type={@type} new input_class="w-full" />
    </Helpers.settings_field>
    """
  end

  defp present(nil), do: "—"
  defp present(""), do: "—"
  defp present(value), do: to_string(value)

  defp present_date(nil), do: "—"
  defp present_date(value), do: TimeFormatter.format_date(value)

  defp present_slack(%{slack_url: slack_url}) when slack_url in [nil, ""], do: nil

  defp present_slack(%{slack_url: slack_url}), do: String.replace_prefix(slack_url, "https://", "")

  defp slack_present?(%{slack_url: slack_url}) when slack_url in [nil, ""], do: false
  defp slack_present?(_user), do: true

  defp leave_attachment_submit_disabled?(upload) do
    Enum.any?(upload.entries, &(not &1.done?)) or upload_errors(upload) != []
  end

  defp contract_upload_submit_disabled?(upload) do
    upload.entries == [] or Enum.any?(upload.entries, &(not &1.done?)) or
      upload_errors(upload) != []
  end

  defp leave_upload_error_to_string(:too_large), do: "Plik jest za duży (max 10 MB)."
  defp leave_upload_error_to_string(:too_many_files), do: "Można wgrać tylko jeden plik."

  defp leave_upload_error_to_string(:not_accepted), do: "Dozwolone są pliki PDF oraz obrazy (JPG, JPEG, PNG)."

  defp leave_upload_error_to_string(other), do: "Błąd wgrywania: #{inspect(other)}"

  defp leave_reasons, do: [:indisposition, :rest, :other]

  defp upload_error_to_string(:too_large), do: "Plik jest za duży (max 10 MB)."
  defp upload_error_to_string(:too_many_files), do: "Można wgrać tylko jeden plik."
  defp upload_error_to_string(:not_accepted), do: "Dozwolone są tylko pliki PDF."
  defp upload_error_to_string(other), do: "Błąd wgrywania: #{inspect(other)}"

  defp format_contract_type(nil), do: "Nieokreślona"
  defp format_contract_type(:uop), do: "Umowa o pracę"
  defp format_contract_type(:b2b), do: "B2B"
  defp format_contract_type(:uz), do: "Umowa zlecenie"
  defp format_contract_type(:uod), do: "Umowa o dzieło"

  defp can_edit_contract?(nil, _scope), do: false

  defp can_edit_contract?(contract, scope) do
    contract
    |> Ash.Changeset.for_update(:update, %{}, scope: scope)
    |> Ash.can?(scope)
  end
end
