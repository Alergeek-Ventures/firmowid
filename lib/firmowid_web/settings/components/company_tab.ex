defmodule FirmowidWeb.Settings.Components.CompanyTab do
  @moduledoc """
  Function components for the company settings route.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.KsefConnection
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.DesignSystem.Components.InvoicingBadges
  import FirmowidWeb.Settings.Components.EditButton
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Core.UserRole
  alias Firmowid.TimeFormatter
  alias FirmowidWeb.Analysis.Utilities.Industry
  alias FirmowidWeb.Invoicing.Utilities.VatExemption
  alias FirmowidWeb.Settings.Components.Helpers
  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the company settings route.
  """
  @spec company_tab(map()) :: Rendered.t()
  attr :current_user, :map, required: true
  attr :current_org, :map, required: true
  attr :company_form, :map, required: true
  attr :editing_basic_info, :boolean, required: true
  attr :ksef_credential, :any, required: true
  attr :ksef_auth_method, :atom, required: true
  attr :ksef_auth_status, :atom, required: true
  attr :ksef_failure, :any, default: nil
  attr :bank_accounts, :list, required: true
  attr :bank_institutions, :map, required: true
  attr :pending_requisitions, :list, required: true
  attr :organization_users, :list, required: true
  attr :organization_invites, :list, required: true
  attr :show_active_invites, :boolean, required: true
  attr :selected_user, :any, default: nil
  attr :bank_account_statuses, :map, required: true
  attr :uploads, :map, required: true
  attr :ksef_fetching?, :boolean, required: true

  def company_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 items-start gap-8 lg:grid-cols-2 lg:gap-14">
      <div class="space-y-14">
        <.company_basic_info_section
          current_org={@current_org}
          company_form={@company_form}
          editing_basic_info={@editing_basic_info}
        />

        <.company_section title="Integracja z KSeF">
          <.ksef_connection
            ksef_credential={@ksef_credential}
            ksef_auth_method={@ksef_auth_method}
            ksef_auth_status={@ksef_auth_status}
            ksef_failure={@ksef_failure}
            uploads={@uploads}
            allow_fetch?
            fetching?={@ksef_fetching?}
          />
        </.company_section>
      </div>

      <.bank_accounts_section
        bank_accounts={@bank_accounts}
        bank_institutions={@bank_institutions}
        pending_requisitions={@pending_requisitions}
        bank_account_statuses={@bank_account_statuses}
        class="col-span-2"
      />

      <.administrators_section
        organization_users={@organization_users}
        organization_invites={@organization_invites}
        show_active_invites={@show_active_invites}
        selected_user={@selected_user}
        current_user={@current_user}
      />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :action, :any, default: nil
  attr :action_label, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp company_section(assigns) do
    ~H"""
    <section class={["space-y-4", @class]}>
      <div class="flex min-h-8 items-center gap-1">
        <h2 class="text-base leading-none font-medium text-grey-900">{@title}</h2>

        <span
          :if={@action}
          id={"settings-#{@action}-tooltip"}
          phx-hook="Tippy"
          data-tippy-content={@action_label || gettext("Edit %{section}", section: @title)}
          data-tippy-delay="100"
          data-tippy-theme="small"
        >
          <.edit_button
            type="button"
            phx-click={@action}
            aria-label={@action_label || gettext("Edit %{section}", section: @title)}
          />
        </span>
      </div>

      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  attr :wide, :boolean, default: false
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

  attr :current_org, :map, required: true
  attr :company_form, :map, required: true
  attr :editing_basic_info, :boolean, required: true

  defp company_basic_info_section(assigns) do
    ~H"""
    <.company_section
      title="Dane firmy"
      action={if(!@editing_basic_info, do: "toggle_editing_basic_info")}
      action_label="Edytuj dane firmy"
    >
      <%= if @editing_basic_info do %>
        <.form
          for={@company_form}
          phx-submit="save"
          phx-change="validate_company_form"
          class="space-y-4"
        >
          <div class="space-y-2">
            <.row_input field={@company_form[:name]} label="Nazwa" type="text" />
            <.row_input field={@company_form[:nip]} label="NIP" type="text" />

            <Helpers.settings_field
              label="Płatnik VAT"
              layout={:row}
              block_class="flex items-center my-1"
              for={@company_form[:is_vat_payer].id}
            >
              <.switch field={@company_form[:is_vat_payer]} color="teal" />
            </Helpers.settings_field>
            <%= if @company_form[:is_vat_payer].value not in [true, "true"] do %>
              <Helpers.settings_field
                label="Zwolnienie z VAT"
                layout={:row}
                block_class="flex items-center"
                for={@company_form[:vat_exemption_type].id}
              >
                <.input
                  type="select"
                  field={@company_form[:vat_exemption_type]}
                  options={VatExemption.options()}
                  input_class="w-full"
                />
              </Helpers.settings_field>

              <%= if to_string(@company_form[:vat_exemption_type].value) == "other" do %>
                <Helpers.settings_field
                  label="Podstawa prawna zwolnienia z VAT"
                  layout={:row}
                  for={@company_form[:vat_exemption_basis].id}
                >
                  <.input
                    type="text"
                    field={@company_form[:vat_exemption_basis]}
                    required
                    show_error={false}
                    input_class="w-full"
                  />
                </Helpers.settings_field>
              <% else %>
                <input type="hidden" name={@company_form[:vat_exemption_basis].name} value="" />
              <% end %>
            <% else %>
              <input type="hidden" name={@company_form[:vat_exemption_type].name} value="" />
              <input type="hidden" name={@company_form[:vat_exemption_basis].name} value="" />
            <% end %>
            <Helpers.settings_field
              label={gettext("Industry")}
              layout={:row}
              block_class="flex items-center"
              for={@company_form[:industry].id}
            >
              <.input
                type="select"
                field={@company_form[:industry]}
                options={Industry.options()}
                input_class="w-full"
              />
            </Helpers.settings_field>
            <.row_input
              field={@company_form[:address]}
              label="Adres"
              type="textarea"
              label_class="pt-1.5 self-start"
            />

            <Helpers.settings_field
              label="Adres korespondencyjny jest taki sam jak adres firmy"
              label_class="max-w-50 ml-auto"
              layout={:row}
              for={@company_form[:is_same_correspondence_address].id}
            >
              <.switch
                field={@company_form[:is_same_correspondence_address]}
                class="w-12"
                color="teal"
              />
            </Helpers.settings_field>

            <%= if not Phoenix.HTML.Form.normalize_value(
                  "switch",
                  @company_form[:is_same_correspondence_address].value
                ) do %>
              <.row_input
                field={@company_form[:correspondence_address]}
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
              phx-click="toggle_editing_basic_info"
            >
              Anuluj
            </.button>
            <.button type="submit" variant="success" size="small">Zapisz</.button>
          </div>
        </.form>
      <% else %>
        <div class="space-y-2">
          <.detail_row label="Nazwa" wide>{present(@current_org.name)}</.detail_row>
          <.detail_row label="NIP" wide>{present(@current_org.nip)}</.detail_row>
          <.detail_row label="Płatnik VAT" wide>{yes_no(@current_org.is_vat_payer)}</.detail_row>
          <.detail_row
            :if={exemption = present_vat_exemption(@current_org)}
            label="Zwolnienie z VAT"
            wide
          >
            {exemption}
          </.detail_row>
          <.detail_row label={gettext("Industry")} wide>
            {Industry.label(@current_org.industry)}
          </.detail_row>
          <.detail_row label="Adres" wide>{multiline_address(@current_org.address)}</.detail_row>
          <.detail_row
            :if={@current_org.correspondence_address not in [nil, ""]}
            label="Adres korespondencyjny"
            wide
          >
            {multiline_address(@current_org.correspondence_address)}
          </.detail_row>
        </div>
      <% end %>
    </.company_section>
    """
  end

  attr :bank_accounts, :list, required: true
  attr :bank_institutions, :map, required: true
  attr :pending_requisitions, :list, required: true
  attr :bank_account_statuses, :map, required: true
  attr :class, :string, default: nil

  defp bank_accounts_section(assigns) do
    ~H"""
    <section class={["space-y-4", @class]}>
      <.pending_requisition_banner :if={Enum.any?(@pending_requisitions)} />

      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h2 class="text-base leading-none font-semibold text-grey-900">Konta bankowe</h2>

        <div class="flex flex-wrap items-center gap-2.5">
          <.button
            type="button"
            variant="secondary"
            size="small"
            phx-click={show_modal("manual_bank_account_modal_company")}
          >
            Dodaj ręcznie
          </.button>
          <.link
            kind="button"
            variant="primary"
            size="small"
            navigate={~p"/ustawienia/bank/dodaj"}
          >
            Nowe konto
          </.link>
        </div>
      </div>

      <div :if={Enum.empty?(@bank_accounts)} class="text-sm leading-[1.35] text-grey-700">
        Nie dodano jeszcze żadnych kont bankowych.
      </div>

      <div
        :if={!Enum.empty?(@bank_accounts)}
        class="grid gap-x-4 gap-y-6 md:grid-cols-2"
      >
        <.bank_card
          :for={account <- @bank_accounts}
          account={account}
          bank_institutions={@bank_institutions}
          status={Map.get(@bank_account_statuses, account.id)}
        />
      </div>

      <.manual_bank_account_modal_company />
    </section>
    """
  end

  defp pending_requisition_banner(assigns) do
    ~H"""
    <section class="rounded-lg border border-grey-200 bg-white px-6 py-5 shadow-sm">
      <div class="flex items-start gap-4">
        <span class="inline-flex size-10 items-center justify-center rounded-full bg-teal-200 text-teal-800">
          <.icon name="hero-arrow-path" class="size-5 animate-spin" />
        </span>

        <div class="space-y-1 text-sm leading-[1.35] text-grey-900">
          <p class="font-medium">Trwa konfiguracja połączenia bankowego.</p>
          <p>Konto pojawi się na liście po zakończeniu autoryzacji i pierwszej synchronizacji.</p>
        </div>
      </div>
    </section>
    """
  end

  attr :organization_users, :list, required: true
  attr :organization_invites, :list, required: true
  attr :show_active_invites, :boolean, required: true
  attr :selected_user, :any, default: nil
  attr :current_user, :map, required: true

  defp administrators_section(assigns) do
    assigns = assign(assigns, :active_invites, active_invites(assigns.organization_invites))

    ~H"""
    <section
      id="settings-organization-invites"
      phx-hook="CopyToClipboard"
      class="col-span-2 space-y-4"
    >
      <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
        <h2 class="text-base/normal font-semibold text-grey-900">Członkowie organizacji</h2>

        <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
          <.button
            type="button"
            variant="unstyled"
            phx-click="toggle_active_invites"
            role="switch"
            size="small"
            aria-checked={to_string(@show_active_invites)}
            class="inline-flex h-11 items-center justify-between gap-3 rounded-lg bg-white px-3 text-sm font-medium text-grey-700 transition focus:outline-none focus-visible:ring-2 focus-visible:ring-rust-700"
          >
            <span>Aktywne zaproszenia</span>
            <span class={invite_toggle_track_styles(@show_active_invites)}>
              <span class={invite_toggle_thumb_styles(@show_active_invites)}></span>
            </span>
          </.button>
          <.button
            type="button"
            variant="secondary"
            size="small"
            phx-click={show_modal("organization_invite_modal")}
          >
            Wygeneruj zaproszenie
          </.button>
        </div>
      </div>

      <div
        :if={@show_active_invites}
        class="scrollbar-card h-151 overflow-y-auto rounded-lg border border-grey-200 bg-white p-6 shadow-sm"
      >
        <div
          :if={@active_invites == []}
          class="flex min-h-96 items-center justify-center text-sm leading-[1.35] text-grey-700"
        >
          Brak aktywnych zaproszeń.
        </div>

        <div :if={@active_invites != []} class="space-y-6">
          <div
            :for={invite <- @active_invites}
            class="grid grid-cols-[minmax(0,1fr)_1fr_auto] items-center gap-4 rounded-lg"
          >
            <p class="text-sm">
              <span class="text-grey-500">Wygenerowano:</span> {TimeFormatter.format_date(
                invite.inserted_at
              )} | {invite_issuer(invite)}
            </p>

            <.button
              type="button"
              variant="unstyled"
              size="small"
              class="flex w-full max-w-80 cursor-pointer items-center justify-between gap-5 rounded bg-teal-100 p-1 py-2 pl-3 text-sm text-teal-700"
              phx-click="copy_organization_invite"
              phx-value-code={invite.invite_code}
            >
              {invite.invite_code}
              <Lucideicons.copy class="size-5" />
            </.button>

            <div class="flex items-center gap-4">
              <span class={role_badge_styles(invite.role)}>{UserRole.label(invite.role)}</span>

              <.button
                type="button"
                variant="unstyled"
                phx-click="delete_organization_invite"
                phx-value-id={invite.id}
                aria-label={gettext("Delete invitation")}
              >
                <Lucideicons.trash_2 class="text-grey-500 transition-all hover:text-grey-700" />
              </.button>
            </div>
          </div>
        </div>
      </div>

      <div
        :if={not @show_active_invites}
        class="scrollbar-card h-151 overflow-y-auto rounded-lg border border-grey-200 bg-white p-6 shadow-sm"
      >
        <div class="flex flex-col gap-6">
          <div
            :for={user <- @organization_users}
            class="flex min-h-12 flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
          >
            <div class="flex min-w-0 items-center gap-4 sm:max-w-sm sm:flex-1">
              <.avatar class="size-12 rounded-full bg-grey-100">
                <.avatar_image
                  :if={user.member.avatar_blob && user.member.avatar_blob.url}
                  src={user.member.avatar_blob.url}
                  alt={user.member.name || user.email}
                />
                <.avatar_fallback class="text-sm font-medium text-grey-700">
                  {initial(user.member.name || user.email)}
                </.avatar_fallback>
              </.avatar>

              <div class="flex min-w-0 flex-col gap-0.5">
                <p class="truncate text-base/snug text-grey-900">
                  {present(user.member.name)}
                </p>
                <p class="truncate text-sm/snug text-grey-700">{user.email}</p>
              </div>
            </div>

            <div class="flex items-center justify-end gap-2">
              <span class={role_badge_styles(user.member.role)}>{UserRole.label(user.member.role)}</span>

              <.dropdown :if={user.id != @current_user.id} id={"organization_user_#{user.id}"}>
                <:trigger>
                  <span class="flex size-10 items-center justify-center rounded-lg text-grey-700 transition hover:bg-grey-100">
                    <span class="sr-only">Opcje użytkownika {present(user.email)}</span>
                    <.icon name="hero-ellipsis-vertical" class="size-6" />
                  </span>
                </:trigger>

                <div class="mt-10 flex w-40 flex-col overflow-hidden rounded-lg border border-grey-200 bg-white p-1 shadow-lg">
                  <.button
                    type="button"
                    variant="unstyled"
                    phx-click="open_update_role_modal"
                    phx-value-user_id={user.id}
                    class={menu_item_styles()}
                  >
                    Zmień rolę
                  </.button>

                  <.link
                    kind="unstyled"
                    navigate={~p"/zarzadzanie/pracownicy/#{user.id}"}
                    class={menu_item_styles()}
                  >
                    Pokaż profil
                  </.link>

                  <.button
                    type="button"
                    variant="unstyled"
                    phx-click="archive_organization_user"
                    phx-value-user_id={user.id}
                    class={["text-brick-800 hover:bg-brick-100", menu_item_styles()]}
                  >
                    Archiwizuj
                  </.button>
                </div>
              </.dropdown>

              <span :if={user.id == @current_user.id} class="size-10 shrink-0" aria-hidden="true" />
            </div>
          </div>
        </div>
      </div>
    </section>

    <.organization_invite_modal />
    <.update_role_modal :if={@selected_user} user={@selected_user} />
    """
  end

  attr :account, :map, required: true
  attr :bank_institutions, :map, required: true
  attr :status, :atom, default: nil

  defp bank_card(assigns) do
    ~H"""
    <article
      id={"konto-bankowe-#{@account.id}"}
      class="relative flex flex-col gap-4 rounded-lg border border-grey-200 bg-white p-4"
    >
      <div class="flex items-center justify-start gap-4">
        <.bank_badge institution={@account} />
        <div class="flex items-start gap-4 self-start">
          <div class="flex flex-wrap gap-2.5">
            <span
              :if={@account.is_default}
              class="rounded-full bg-moss-100 px-4 py-1 text-sm text-moss-700"
            >
              Domyślne <span class="font-semibold">{present(@account.currency)}</span>
            </span>
            <span
              :if={!@account.is_default}
              class="rounded-full bg-grey-100 px-4 py-1 font-semibold text-grey-700"
            >
              {present(@account.currency)}
            </span>
          </div>
        </div>

        <div class="flex flex-1 justify-end">
          <.dropdown id={"bank_account_#{@account.id}"}>
            <:trigger>
              <span class="inline-flex size-8 items-center justify-center rounded-lg text-grey-700 transition hover:bg-grey-100">
                <span class="sr-only">
                  {gettext("Account options for %{account}",
                    account: bank_account_menu_label(@account)
                  )}
                </span>
                <.icon name="hero-ellipsis-horizontal" class="size-5" />
              </span>
            </:trigger>

            <div class="flex w-48 flex-col overflow-hidden rounded-lg border border-grey-200 bg-white py-1 text-sm font-medium text-grey-700 shadow-lg">
              <.button
                type="button"
                variant="unstyled"
                phx-click={show_modal("rename_bank_account_#{@account.id}")}
                class={menu_item_styles()}
              >
                Zmień nazwę
              </.button>

              <.button
                :if={!is_nil(@account.institution_id)}
                type="button"
                variant="unstyled"
                phx-click="reconnect_bank_account"
                phx-value-account_id={@account.id}
                class={menu_item_styles()}
              >
                Połącz ponownie
              </.button>

              <.button
                :if={!@account.is_default}
                type="button"
                variant="unstyled"
                phx-click="make_default_account"
                phx-value-account_id={@account.id}
                class={menu_item_styles()}
              >
                Domyślne dla {present(@account.currency)}
              </.button>

              <.button
                type="button"
                variant="unstyled"
                phx-click={show_modal("confirm_delete_bank_account_#{@account.id}")}
                class={["text-brick-700 hover:bg-brick-100", menu_item_styles()]}
              >
                Usuń
              </.button>
            </div>
          </.dropdown>
        </div>
      </div>

      <div class="grid grid-cols-[max-content_1fr] items-center gap-x-6 gap-y-3">
        <.bank_detail_row :if={!is_nil(@account.name)} label="Nazwa">
          {present(@account.name)}
        </.bank_detail_row>
        <.bank_detail_row label="Bank">{present(@account.institution_name)}</.bank_detail_row>
        <.bank_detail_row label="Numer">
          <span class="break-all">{format_iban(@account.iban)}</span>
        </.bank_detail_row>
        <.bank_detail_row :if={@status} label="Status">
          <span :if={@status in [:broken, :disconnected]} class="inline-flex items-center gap-1.5">
            <span class="font-medium text-brick-800">Konto rozłączone</span>
          </span>

          <span :if={@status not in [:broken, :disconnected]} class="inline-flex items-center gap-2">
            {format_last_sync_info(@status, @account.latest_successful_sync_at)}
          </span>
        </.bank_detail_row>

        <div class="col-span-2 pt-2">
          <.button
            :if={@status in [:broken, :disconnected]}
            variant="outline"
            size="big"
            class="w-full"
            phx-click="reconnect_bank_account"
            phx-value-account_id={@account.id}
            aria-label="Połącz ponownie konto"
          >
            <Lucideicons.unplug class="size-4" />
            <span class="inline-flex">Połącz ponownie</span>
          </.button>
        </div>
      </div>
    </article>

    <.modal id={"rename_bank_account_#{@account.id}"}>
      <.form for={%{}} phx-submit="rename_bank_account" id={"rename_form_#{@account.id}"}>
        <input type="hidden" name="account_id" value={@account.id} />
        <.input
          name="name"
          id={"rename_bank_account_name_#{@account.id}"}
          label="Nowa nazwa"
          value={@account.name}
        />

        <div class="mt-4 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
          <.button
            type="button"
            variant="secondary"
            size="small"
            phx-click={hide_modal("rename_bank_account_#{@account.id}")}
          >
            Anuluj
          </.button>

          <.button
            type="submit"
            variant="success"
            size="small"
            phx-click={hide_modal("rename_bank_account_#{@account.id}")}
            phx-disable-with="Zapisywanie..."
          >
            Zapisz
          </.button>
        </div>
      </.form>
    </.modal>

    <.modal id={"confirm_delete_bank_account_#{@account.id}"}>
      <h3 class="text-lg font-semibold text-grey-900">Potwierdź usunięcie</h3>
      <p class="mt-3 text-sm text-grey-700">
        Czy na pewno chcesz usunąć to konto bankowe? Usuniemy też powiązane transakcje.
      </p>

      <div class="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <.button
          type="button"
          variant="secondary"
          size="small"
          phx-click={hide_modal("confirm_delete_bank_account_#{@account.id}")}
        >
          Anuluj
        </.button>

        <.button
          type="button"
          variant="destructive"
          size="small"
          phx-click={
            JS.push("delete_bank_account", value: %{account_id: @account.id})
            |> hide_modal("confirm_delete_bank_account_#{@account.id}")
          }
          phx-disable-with="Usuwam..."
        >
          Usuń
        </.button>
      </div>
    </.modal>
    """
  end

  defp manual_bank_account_modal_company(assigns) do
    ~H"""
    <.modal
      id="manual_bank_account_modal_company"
      on_cancel={hide_modal("manual_bank_account_modal_company")}
    >
      <div class="space-y-4">
        <div>
          <h3 class="text-lg font-semibold text-grey-900">Dodaj konto bankowe ręcznie</h3>
          <p class="mt-2 text-sm text-grey-700">
            Ta funkcja pozwala dodać konto bez integracji z bankiem. Synchronizacja transakcji będzie wyłączona.
          </p>
        </div>

        <.form
          for={%{}}
          phx-submit="create_manual_bank_account"
          id="manual_bank_account_form_company"
          class="space-y-4"
        >
          <.input name="name" id="manual_bank_account_name" label="Nazwa konta" value="" />
          <.input name="owner_name" id="manual_bank_account_owner_name" label="Właściciel" value="" />
          <.input name="iban" id="manual_bank_account_iban" label="IBAN" value="" />
          <.input name="currency" id="manual_bank_account_currency" label="Waluta" value="" />

          <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
            <.button
              type="button"
              variant="secondary"
              size="small"
              phx-click={hide_modal("manual_bank_account_modal_company")}
            >
              Anuluj
            </.button>

            <.button
              type="submit"
              variant="success"
              size="small"
              phx-disable-with="Dodawanie..."
            >
              Zapisz
            </.button>
          </div>
        </.form>
      </div>
    </.modal>
    """
  end

  defp organization_invite_modal(assigns) do
    ~H"""
    <.modal
      id="organization_invite_modal"
      on_cancel={hide_modal("organization_invite_modal")}
      class="max-w-lg"
    >
      <div class="space-y-8">
        <h3 class="text-xl font-medium">Zaproś nowego pracownika</h3>
        <p>
          Wybierz rolę, a następnie wygeneruj kod. Pracownik, podając go przy zakładaniu konta, automatycznie dołączy do twojej organizacji.
        </p>

        <.form
          for={%{}}
          phx-submit="create_organization_invite"
          id="organization_invite_form"
          class="flex flex-col gap-8"
        >
          <.role_row_input
            :for={role <- UserRole.roles()}
            role={role}
            checked={role == :employee}
          />

          <div class="flex flex-col-reverse gap-4 sm:flex-row sm:justify-end">
            <.button
              type="button"
              variant="secondary"
              size="small"
              phx-click={hide_modal("organization_invite_modal")}
            >
              Anuluj
            </.button>

            <.button
              type="submit"
              variant="primary"
              accent="teal"
              size="small"
              phx-click={hide_modal("organization_invite_modal")}
            >
              Wygeneruj kod
            </.button>
          </div>
        </.form>
      </div>
    </.modal>
    """
  end

  attr :user, :map, required: true

  defp update_role_modal(assigns) do
    current_role = assigns.user.member.role
    other_roles = Enum.reject(UserRole.roles(), &(&1 == current_role))

    assigns =
      assigns
      |> assign(:current_role, current_role)
      |> assign(:other_roles, other_roles)

    ~H"""
    <.modal
      id="update_role_modal"
      show
      on_cancel={JS.push("clear_selected_user")}
      class="max-w-lg"
    >
      <div class="space-y-8">
        <h3 class="text-xl font-medium">Zmiana roli</h3>
        <p>
          Zmieniasz rolę użytkownikowi {present(@user.member.name || to_string(@user.email))}. Jego dotychczasowa rola to:
        </p>

        <.form
          for={%{}}
          phx-submit="update_user_role"
          id="update_role_form"
          class="flex flex-col gap-8"
        >
          <input type="hidden" name="user_id" value={@user.id} />

          <.role_row_input role={@current_role} checked />
          <.role_row_input :for={role <- @other_roles} role={role} />

          <div class="flex flex-col-reverse gap-4 sm:flex-row sm:justify-end">
            <.button
              type="button"
              variant="secondary"
              size="small"
              phx-click={JS.push("clear_selected_user") |> hide_modal("update_role_modal")}
            >
              Anuluj
            </.button>

            <.button
              type="submit"
              variant="primary"
              accent="teal"
              size="small"
            >
              Zmień rolę
            </.button>
          </div>
        </.form>
      </div>
    </.modal>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp bank_detail_row(assigns) do
    ~H"""
    <label class="text-sm text-grey-700">{@label}</label>
    <div class="text-base/snug">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :field, :map, required: true
  attr :label, :string, required: true
  attr :type, :string, required: true
  attr :label_class, :string, default: nil

  defp row_input(assigns) do
    ~H"""
    <Helpers.settings_field label={@label} layout={:row} for={@field.id} label_class={@label_class}>
      <.input field={@field} type={@type} input_class="w-full" />
    </Helpers.settings_field>
    """
  end

  attr :role, :atom, required: true
  attr :checked, :boolean, default: false

  defp role_row_input(assigns) do
    ~H"""
    <.label class="flex cursor-pointer flex-row items-start gap-2">
      <input
        name="role"
        type="radio"
        value={UserRole.param(@role)}
        checked={@checked}
        class="size-5 shrink-0 appearance-none rounded-full border-2 border-grey-300 bg-white text-teal-700 checked:bg-teal-700 focus:outline-none"
      />
      <div>
        <span class="font-medium capitalize">{UserRole.label(@role)}</span>
        <p class="text-sm">{role_desc(@role)}</p>
      </div>
    </.label>
    """
  end

  defp invite_toggle_track_styles(true), do: "bg-teal-700 relative inline-flex h-[24px] w-[44px] rounded-full"

  defp invite_toggle_track_styles(false), do: "bg-grey-200 relative inline-flex h-[24px] w-[44px] rounded-full"

  defp invite_toggle_thumb_styles(true) do
    "absolute top-[3px] left-[3px] size-[18px] translate-x-5 rounded-full bg-white transition"
  end

  defp invite_toggle_thumb_styles(false) do
    "absolute top-[3px] left-[3px] size-[18px] rounded-full bg-white transition"
  end

  defp active_invites(invites) do
    now = DateTime.utc_now()

    invites
    |> Enum.filter(fn invite ->
      is_nil(invite.consumed_at) and DateTime.after?(invite.expires_at, now)
    end)
    |> Enum.sort_by(&DateTime.to_unix(&1.expires_at))
  end

  defp invite_issuer(%{issued_by: %{email: email}}) when not is_nil(email), do: to_string(email)
  defp invite_issuer(_invite), do: "administrator"

  defp menu_item_styles do
    "hover:text-teal-800 hover:bg-teal-100 w-full justify-start rounded-none px-3 py-2 text-left text-sm transition cursor-pointer"
  end

  defp format_last_sync_info(:manual, _datetime), do: "konto dodane ręcznie"
  defp format_last_sync_info(_status, nil), do: "jeszcze nie zsynchronizowano"

  defp format_last_sync_info(_status, %DateTime{} = datetime),
    do: "aktualizacja: #{TimeFormatter.format_relative_time(datetime)}"

  defp format_last_sync_info(_status, %NaiveDateTime{} = datetime),
    do: "aktualizacja: #{TimeFormatter.format_relative_time(datetime)}"

  defp format_last_sync_info(_status, _datetime), do: "jeszcze nie zsynchronizowano"

  defp bank_account_menu_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp bank_account_menu_label(%{iban: iban}) when is_binary(iban) and iban != "", do: iban
  defp bank_account_menu_label(_account), do: "bankowego"

  defp present(nil), do: "—"
  defp present(""), do: "—"
  defp present(value), do: to_string(value)

  defp format_iban(nil), do: ""

  defp format_iban(iban) do
    iban
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join(" ", &Enum.join/1)
  end

  defp yes_no(true), do: "Tak"
  defp yes_no(false), do: "Nie"
  defp yes_no(_), do: "—"

  defp role_desc(:admin) do
    ~s|Pełny dostęp do zakładki "Zarządzanie" — w tym zarządzania pracownikami, kontrahentami oraz projektami. Ta rola pozwala także na pełny dostęp do faktur oraz do wgrywania faktur spoza KSeF.|
  end

  defp role_desc(:employee) do
    "Podstawowy dostęp do organizacji, w tym do Czasośledzia (śledzenie czasu pracy). Możliwość zgłaszania urlopów oraz przesyłania dokumentów."
  end

  defp role_desc(:invoicing) do
    "Dostęp do fakturowania wyłącznie w trybie podglądu, bez możliwości dodawania i edycji."
  end

  defp role_desc(:accountant) do
    "Pełny dostęp do fakturowania (przeglądanie, dodawanie i edycja), z wyjątkiem dodawania faktur spoza KSeF."
  end

  defp role_badge_styles(:admin) do
    "bg-teal-200 text-teal-700 inline-flex w-28 items-center justify-center rounded-sm px-3 py-1 text-sm leading-[1.35]"
  end

  defp role_badge_styles(:accountant) do
    "bg-moss-200 text-moss-700 inline-flex w-28 items-center justify-center rounded-sm px-3 py-1 text-sm leading-[1.35]"
  end

  defp role_badge_styles(:invoicing) do
    "bg-rust-200 text-rust-700 inline-flex w-28 items-center justify-center rounded-sm px-3 py-1 text-sm leading-[1.35]"
  end

  defp role_badge_styles(_role) do
    "bg-grey-200 text-grey-700 inline-flex w-28 items-center justify-center rounded-sm px-3 py-1 text-sm leading-[1.35]"
  end

  defp multiline_address(nil), do: "—"
  defp multiline_address(""), do: "—"
  defp multiline_address(address), do: to_string(address)

  defp initial(email) do
    email
    |> to_string()
    |> String.slice(0, 1)
    |> String.upcase()
  end

  defp present_vat_exemption(%{vat_exemption_type: nil}), do: nil

  defp present_vat_exemption(%{vat_exemption_type: type} = org) do
    case type do
      :other ->
        org.vat_exemption_basis

      _ ->
        VatExemption.label(type)
    end
  end
end
