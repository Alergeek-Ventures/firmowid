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
  import FirmowidWeb.Management.Components.Roles

  import FirmowidWeb.Settings.Components.Helpers,
    only: [settings_section: 1, detail_row: 1, row_input: 1, present: 1, initial: 1]

  import Phoenix.Component, except: [link: 1]

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
  attr :uploads, :map, required: true
  attr :ksef_fetching?, :boolean, required: true

  attr :section, :atom, default: :all

  def company_tab(assigns) do
    ~H"""
    <div class={[
      if(@section == :all,
        do: "grid grid-cols-1 items-start gap-8 lg:grid-cols-2 lg:gap-14",
        else: "flex flex-col gap-8"
      )
    ]}>
      <div :if={@section == :all} class="space-y-14">
        <.company_basic_info_section
          current_org={@current_org}
          company_form={@company_form}
          editing_basic_info={@editing_basic_info}
        />

        <.settings_section title={gettext("KSeF integration")}>
          <.ksef_connection
            ksef_credential={@ksef_credential}
            ksef_auth_method={@ksef_auth_method}
            ksef_auth_status={@ksef_auth_status}
            ksef_failure={@ksef_failure}
            uploads={@uploads}
            allow_fetch?
            fetching?={@ksef_fetching?}
          />
        </.settings_section>
      </div>

      <.company_details_form :if={@section == :organization} company_form={@company_form} />

      <section :if={@section == :ksef} class={card_styles()}>
        <.ksef_connection
          ksef_credential={@ksef_credential}
          ksef_auth_method={@ksef_auth_method}
          ksef_auth_status={@ksef_auth_status}
          ksef_failure={@ksef_failure}
          uploads={@uploads}
          allow_fetch?
          fetching?={@ksef_fetching?}
          details={:inline}
        />
      </section>

      <.bank_accounts_section
        :if={@section in [:all, :bank_accounts]}
        standalone={@section == :bank_accounts}
        bank_accounts={@bank_accounts}
        bank_institutions={@bank_institutions}
        pending_requisitions={@pending_requisitions}
        class={[if(@section == :all, do: "col-span-2")]}
      />

      <.administrators_section
        :if={@section == :all}
        organization_users={@organization_users}
        organization_invites={@organization_invites}
        show_active_invites={@show_active_invites}
        selected_user={@selected_user}
        current_user={@current_user}
      />
    </div>
    """
  end

  attr :current_org, :map, required: true
  attr :company_form, :map, required: true
  attr :editing_basic_info, :boolean, required: true

  defp company_basic_info_section(assigns) do
    ~H"""
    <.settings_section
      title={gettext("Company details")}
      action={if(!@editing_basic_info, do: "toggle_editing_basic_info")}
      action_label={gettext("Edit company details")}
    >
      <%= if @editing_basic_info do %>
        <.form
          for={@company_form}
          phx-submit="save"
          phx-change="validate_company_form"
          class="space-y-4"
        >
          <div class="space-y-2">
            <.row_input field={@company_form[:name]} label={gettext("Name on invoices")} type="text" />
            <.row_input
              field={@company_form[:display_name]}
              label={gettext("Name in the app")}
              type="text"
            />
            <.row_input field={@company_form[:nip]} label="NIP" type="text" />

            <Helpers.settings_field
              label={gettext("VAT payer")}
              layout={:row}
              block_class="flex items-center my-1"
              for={@company_form[:is_vat_payer].id}
            >
              <.switch field={@company_form[:is_vat_payer]} color="teal" />
            </Helpers.settings_field>
            <%= if @company_form[:is_vat_payer].value not in [true, "true"] do %>
              <Helpers.settings_field
                label={gettext("VAT exemption")}
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
                  label={gettext("Legal basis for the VAT exemption")}
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
            <Helpers.settings_field
              label={gettext("Billing by the hour")}
              layout={:row}
              block_class="flex items-center my-1"
              for={@company_form[:bills_hourly].id}
            >
              <.switch field={@company_form[:bills_hourly]} color="teal" />
            </Helpers.settings_field>
            <.row_input
              field={@company_form[:address]}
              label={gettext("Address")}
              type="textarea"
              label_class="pt-1.5 self-start"
            />

            <Helpers.settings_field
              label={gettext("The correspondence address is the same as the company address")}
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
                label={gettext("Correspondence address")}
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
              {gettext("Cancel")}
            </.button>
            <.button type="submit" variant="success" size="small">
              {gettext("Save")}
            </.button>
          </div>
        </.form>
      <% else %>
        <div class="space-y-2">
          <.detail_row label={gettext("Name on invoices")}>
            {present(@current_org.name)}
          </.detail_row>
          <.detail_row label={gettext("Name in the app")}>
            {present(@current_org.display_name)}
          </.detail_row>
          <.detail_row label="NIP">{present(@current_org.nip)}</.detail_row>
          <.detail_row label={gettext("VAT payer")}>
            {yes_no(@current_org.is_vat_payer)}
          </.detail_row>
          <.detail_row
            :if={exemption = present_vat_exemption(@current_org)}
            label={gettext("VAT exemption")}
          >
            {exemption}
          </.detail_row>
          <.detail_row label={gettext("Industry")}>
            {Industry.label(@current_org.industry)}
          </.detail_row>
          <.detail_row label={gettext("Billing by the hour")}>
            {yes_no(@current_org.bills_hourly)}
          </.detail_row>
          <.detail_row label={gettext("Address")}>
            {multiline_address(@current_org.address)}
          </.detail_row>
          <.detail_row
            :if={@current_org.correspondence_address not in [nil, ""]}
            label={gettext("Correspondence address")}
          >
            {multiline_address(@current_org.correspondence_address)}
          </.detail_row>
        </div>
      <% end %>
    </.settings_section>
    """
  end

  attr :company_form, :map, required: true

  # The standalone page edits the details in place; the combined settings page
  # keeps the read-only view behind its edit button.
  defp company_details_form(assigns) do
    ~H"""
    <.form
      for={@company_form}
      id="company-details-form"
      phx-submit="save"
      phx-change="validate_company_form"
      class={card_styles()}
    >
      <div class="grid gap-4 sm:grid-cols-2">
        <Helpers.settings_field
          label={gettext("Name on invoices")}
          for={@company_form[:name].id}
          class="sm:col-span-2"
        >
          <.input field={@company_form[:name]} type="text" input_class="w-full" />
        </Helpers.settings_field>
        <Helpers.settings_field
          label={gettext("Name in the app")}
          for={@company_form[:display_name].id}
          class="sm:col-span-2"
        >
          <.input field={@company_form[:display_name]} type="text" input_class="w-full" />
        </Helpers.settings_field>
        <Helpers.settings_field label="NIP" for={@company_form[:nip].id}>
          <.input field={@company_form[:nip]} type="text" input_class="w-full" />
        </Helpers.settings_field>
        <Helpers.settings_field label={gettext("Industry")} for={@company_form[:industry].id}>
          <.input
            type="select"
            field={@company_form[:industry]}
            options={Industry.options()}
            input_class="w-full"
          />
        </Helpers.settings_field>
      </div>

      <div class="grid gap-4 border-bs border-grey-200 pbs-5 sm:grid-cols-2">
        <.switch
          field={@company_form[:bills_hourly]}
          label={gettext("Billing by the hour: time tracking and projects")}
          color="teal"
          class="sm:col-span-2"
        />
        <.switch
          field={@company_form[:is_vat_payer]}
          label={gettext("VAT payer")}
          color="teal"
          class="sm:col-span-2"
        />
        <%= if @company_form[:is_vat_payer].value not in [true, "true"] do %>
          <Helpers.settings_field
            label={gettext("VAT exemption")}
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
              label={gettext("Legal basis for the VAT exemption")}
              for={@company_form[:vat_exemption_basis].id}
            >
              <.input
                type="text"
                field={@company_form[:vat_exemption_basis]}
                required
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
      </div>

      <div class="grid items-start gap-4 border-bs border-grey-200 pbs-5 sm:grid-cols-2">
        <Helpers.settings_field label={gettext("Address")} for={@company_form[:address].id}>
          <.input field={@company_form[:address]} type="textarea" input_class="w-full" />
        </Helpers.settings_field>

        <div class="flex flex-col gap-3">
          <.switch
            field={@company_form[:is_same_correspondence_address]}
            label={gettext("The correspondence address is the same as the company address")}
            color="teal"
          />
          <Helpers.settings_field
            :if={
              not Phoenix.HTML.Form.normalize_value(
                "switch",
                @company_form[:is_same_correspondence_address].value
              )
            }
            label={gettext("Correspondence address")}
            for={@company_form[:correspondence_address].id}
          >
            <.input
              field={@company_form[:correspondence_address]}
              type="textarea"
              input_class="w-full"
            />
          </Helpers.settings_field>
        </div>
      </div>

      <div class="flex justify-end">
        <.button
          type="submit"
          variant="success"
          size="small"
          phx-disable-with={pgettext("settings", "Saving...")}
        >
          {gettext("Save changes")}
        </.button>
      </div>
    </.form>
    """
  end

  attr :bank_accounts, :list, required: true
  attr :bank_institutions, :map, required: true
  attr :pending_requisitions, :list, required: true
  attr :standalone, :boolean, default: false
  attr :class, :any, default: nil

  defp bank_accounts_section(assigns) do
    ~H"""
    <section class={["space-y-4", @class]}>
      <.pending_requisition_banner :if={Enum.any?(@pending_requisitions)} />

      <div class={[
        "flex flex-col gap-3 sm:flex-row sm:items-center",
        if(@standalone, do: "sm:justify-end", else: "sm:justify-between")
      ]}>
        <%!-- The standalone page title already names the section. --%>
        <h2 :if={!@standalone} class="text-base leading-none font-semibold text-grey-900">
          {gettext("Bank accounts")}
        </h2>

        <div class="flex flex-wrap items-center gap-2.5">
          <.button
            type="button"
            variant="tertiary"
            size="small"
            phx-click={show_modal("manual_bank_account_modal_company")}
          >
            {gettext("Add manually")}
          </.button>
          <.link
            kind="button"
            variant="primary"
            size="small"
            navigate={~p"/ustawienia/bank/dodaj"}
          >
            {gettext("New account")}
          </.link>
        </div>
      </div>

      <div :if={Enum.empty?(@bank_accounts)} class="text-sm leading-[1.35] text-grey-700">
        {gettext("No bank accounts have been added yet.")}
      </div>

      <div
        :if={!Enum.empty?(@bank_accounts)}
        class="grid gap-x-4 gap-y-6 md:grid-cols-2"
      >
        <.bank_card
          :for={account <- @bank_accounts}
          standalone={@standalone}
          account={account}
          bank_institutions={@bank_institutions}
          status={bank_account_status(account, account.requisition && account.requisition.status)}
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
          <p class="font-medium">{gettext("The bank connection is being set up.")}</p>
          <p>
            {gettext(
              "The account will appear on the list after authorization and the first synchronization finish."
            )}
          </p>
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
        <h2 class="text-base/normal font-semibold text-grey-900">
          {gettext("Organization members")}
        </h2>

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
            <span>{gettext("Active invitations")}</span>
            <span class={invite_toggle_track_styles(@show_active_invites)}>
              <span class={invite_toggle_thumb_styles(@show_active_invites)}></span>
            </span>
          </.button>
          <.button
            type="button"
            variant="tertiary"
            size="small"
            phx-click={show_modal("organization_invite_modal")}
          >
            {gettext("Generate invitation")}
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
          {gettext("No active invitations.")}
        </div>

        <div :if={@active_invites != []} class="space-y-6">
          <.invite_row :for={invite <- @active_invites} invite={invite} />
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
              <.role_badge role={user.member.role} />

              <.dropdown :if={user.id != @current_user.id} id={"organization_user_#{user.id}"}>
                <:trigger>
                  <span class="flex size-10 items-center justify-center rounded-lg text-grey-700 transition hover:bg-grey-100">
                    <span class="sr-only">
                      {gettext("User options for %{email}", email: present(user.email))}
                    </span>
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
                    {gettext("Change role")}
                  </.button>

                  <.link
                    kind="unstyled"
                    navigate={~p"/zarzadzanie/pracownicy/#{user.id}"}
                    class={menu_item_styles()}
                  >
                    {gettext("Show profile")}
                  </.link>

                  <.button
                    type="button"
                    variant="unstyled"
                    phx-click="archive_organization_user"
                    phx-value-user_id={user.id}
                    class={["text-brick-800 hover:bg-brick-100", menu_item_styles()]}
                  >
                    {gettext("Archive")}
                  </.button>
                </div>
              </.dropdown>

              <span :if={user.id == @current_user.id} class="size-10 shrink-0" aria-hidden="true" />
            </div>
          </div>
        </div>
      </div>
    </section>

    <.invite_modal />
    <.update_role_modal :if={@selected_user} user={@selected_user} />
    """
  end

  attr :account, :map, required: true
  attr :bank_institutions, :map, required: true
  attr :status, :atom, default: nil
  attr :standalone, :boolean, default: false

  defp bank_card(assigns) do
    assigns =
      assign(assigns,
        default_parts:
          "Default %{currency}"
          |> gettext(currency: "__CURRENCY__")
          |> String.split("__CURRENCY__", parts: 2)
          |> List.to_tuple()
      )

    ~H"""
    <article
      id={"konto-bankowe-#{@account.id}"}
      class={[
        "relative flex flex-col gap-4 bg-white",
        if(@standalone, do: "rounded-md p-5", else: "rounded-lg border border-grey-200 p-4")
      ]}
    >
      <div class="flex items-center justify-start gap-4">
        <.bank_badge institution={@account} />
        <div class="flex items-start gap-4 self-start">
          <div class="flex flex-wrap gap-2.5">
            <span
              :if={@account.is_default}
              class="rounded-full bg-moss-100 px-4 py-1 text-sm text-moss-700"
            >
              {elem(@default_parts, 0)}<span class="font-semibold">{present(@account.currency)}</span>{elem(
                @default_parts,
                1
              )}
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
                :if={!@standalone}
                type="button"
                variant="unstyled"
                phx-click={show_modal("rename_bank_account_#{@account.id}")}
                class={menu_item_styles()}
              >
                {gettext("Rename")}
              </.button>

              <.button
                :if={!is_nil(@account.institution_id)}
                type="button"
                variant="unstyled"
                phx-click="reconnect_bank_account"
                phx-value-account_id={@account.id}
                class={menu_item_styles()}
              >
                {gettext("Reconnect")}
              </.button>

              <.button
                :if={!@account.is_default}
                type="button"
                variant="unstyled"
                phx-click="make_default_account"
                phx-value-account_id={@account.id}
                class={menu_item_styles()}
              >
                {gettext("Default for %{currency}", currency: present(@account.currency))}
              </.button>

              <.button
                type="button"
                variant="unstyled"
                phx-click={show_modal("confirm_delete_bank_account_#{@account.id}")}
                class={["text-brick-700 hover:bg-brick-100", menu_item_styles()]}
              >
                {gettext("Delete")}
              </.button>
            </div>
          </.dropdown>
        </div>
      </div>

      <div class="grid grid-cols-[max-content_1fr] items-center gap-x-6 gap-y-3">
        <.bank_detail_row :if={!@standalone and !is_nil(@account.name)} label={gettext("Name")}>
          {present(@account.name)}
        </.bank_detail_row>
        <%!-- The standalone page renames in place and saves when the field loses focus or on Enter. --%>
        <.bank_detail_row
          :if={@standalone}
          label={gettext("Name")}
          for={"bank_account_name_#{@account.id}"}
        >
          <.form
            for={%{}}
            id={"bank_account_name_form_#{@account.id}"}
            phx-change="rename_bank_account"
            phx-submit="rename_bank_account"
          >
            <input type="hidden" name="account_id" value={@account.id} />
            <.input
              name="name"
              id={"bank_account_name_#{@account.id}"}
              value={@account.name}
              phx-debounce="blur"
              input_class="w-full"
            />
          </.form>
        </.bank_detail_row>
        <.bank_detail_row label={gettext("Bank")}>
          {present(@account.institution_name)}
        </.bank_detail_row>
        <.bank_detail_row label={gettext("Number")}>
          <span class="break-all">{format_iban(@account.iban)}</span>
        </.bank_detail_row>
        <.bank_detail_row :if={@status} label={gettext("Status")}>
          <span :if={@status in [:broken, :disconnected]} class="inline-flex items-center gap-1.5">
            <span class="font-medium text-brick-800">{gettext("Account disconnected")}</span>
          </span>

          <span :if={@status not in [:broken, :disconnected]} class="inline-flex items-center gap-2">
            {format_last_sync_info(@status, @account.latest_successful_sync_at)}
          </span>
          <.badge :if={@account.suspended_by_plan_at} class="ml-2">
            {gettext("Paused by the plan")}
          </.badge>
        </.bank_detail_row>

        <div class="col-span-2 pt-2">
          <.button
            :if={@status in [:broken, :disconnected]}
            variant="outline"
            size={if(@standalone, do: "small", else: "big")}
            class={[if(!@standalone, do: "w-full")]}
            phx-click="reconnect_bank_account"
            phx-value-account_id={@account.id}
            aria-label={gettext("Reconnect account")}
          >
            <Lucideicons.unplug class="size-4" />
            <span class="inline-flex">{gettext("Reconnect")}</span>
          </.button>
        </div>
      </div>
    </article>

    <.modal :if={!@standalone} id={"rename_bank_account_#{@account.id}"}>
      <.form for={%{}} phx-submit="rename_bank_account" id={"rename_form_#{@account.id}"}>
        <input type="hidden" name="account_id" value={@account.id} />
        <.input
          name="name"
          id={"rename_bank_account_name_#{@account.id}"}
          label={gettext("New name")}
          value={@account.name}
        />

        <div class="mt-4 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
          <.button
            type="button"
            variant="tertiary"
            size="small"
            phx-click={hide_modal("rename_bank_account_#{@account.id}")}
          >
            {gettext("Cancel")}
          </.button>

          <.button
            type="submit"
            variant="success"
            size="small"
            phx-click={hide_modal("rename_bank_account_#{@account.id}")}
            phx-disable-with={pgettext("settings", "Saving...")}
          >
            {gettext("Save")}
          </.button>
        </div>
      </.form>
    </.modal>

    <.modal id={"confirm_delete_bank_account_#{@account.id}"}>
      <h3 class="text-lg font-semibold text-grey-900">
        {gettext("Confirm deletion")}
      </h3>
      <p class="mt-3 text-sm text-grey-700">
        {gettext(
          "Are you sure you want to delete this bank account? We will also delete the related transactions."
        )}
      </p>

      <div class="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
        <.button
          type="button"
          variant="tertiary"
          size="small"
          phx-click={hide_modal("confirm_delete_bank_account_#{@account.id}")}
        >
          {gettext("Cancel")}
        </.button>

        <.button
          type="button"
          variant="destructive"
          size="small"
          phx-click={
            JS.push("delete_bank_account", value: %{account_id: @account.id})
            |> hide_modal("confirm_delete_bank_account_#{@account.id}")
          }
          phx-disable-with={gettext("Deleting...")}
        >
          {gettext("Delete")}
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
          <h3 class="text-lg font-semibold text-grey-900">
            {gettext("Add a bank account manually")}
          </h3>
          <p class="mt-2 text-sm text-grey-700">
            {gettext(
              "This feature lets you add an account without a bank integration. Transaction synchronization will be disabled."
            )}
          </p>
        </div>

        <.form
          for={%{}}
          phx-submit="create_manual_bank_account"
          id="manual_bank_account_form_company"
          class="space-y-4"
        >
          <.input name="name" id="manual_bank_account_name" label={gettext("Account name")} value="" />
          <.input
            name="owner_name"
            id="manual_bank_account_owner_name"
            label={gettext("Owner")}
            value=""
          />
          <.input name="iban" id="manual_bank_account_iban" label="IBAN" value="" />
          <.input
            name="currency"
            id="manual_bank_account_currency"
            label={gettext("Currency")}
            value=""
          />

          <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
            <.button
              type="button"
              variant="tertiary"
              size="small"
              phx-click={hide_modal("manual_bank_account_modal_company")}
            >
              {gettext("Cancel")}
            </.button>

            <.button
              type="submit"
              variant="success"
              size="small"
              phx-disable-with={gettext("Adding...")}
            >
              {gettext("Save")}
            </.button>
          </div>
        </.form>
      </div>
    </.modal>
    """
  end

  attr :label, :string, required: true
  attr :for, :string, default: nil
  slot :inner_block, required: true

  defp bank_detail_row(assigns) do
    ~H"""
    <label for={@for} class="text-sm text-grey-700">{@label}</label>
    <div class="text-base/snug">
      {render_slot(@inner_block)}
    </div>
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

  # The white card of the standalone settings pages, as in the inbox.
  defp card_styles, do: "flex flex-col gap-5 rounded-md bg-white p-5"

  defp menu_item_styles do
    "hover:text-teal-800 hover:bg-teal-100 w-full justify-start rounded-none px-3 py-2 text-left text-sm transition cursor-pointer"
  end

  defp bank_account_status(%{institution_name: "Manual"}, _requisition_status), do: :manual

  defp bank_account_status(account, _requisition_status) when is_nil(account.gocardless_id), do: :disconnected

  defp bank_account_status(account, _requisition_status) when account.sync_stopped?, do: :broken

  defp bank_account_status(account, requisition_status)
       when requisition_status == :accepted and not account.has_successful_sync?, do: :processing

  defp bank_account_status(_account, :pending), do: :processing

  defp bank_account_status(account, _requisition_status) when account.has_successful_sync?, do: :connected

  defp bank_account_status(_account, _requisition_status), do: :disconnected

  defp format_last_sync_info(:manual, _datetime), do: gettext("account added manually")
  defp format_last_sync_info(_status, nil), do: gettext("not synchronized yet")

  defp format_last_sync_info(_status, %DateTime{} = datetime),
    do: gettext("updated: %{time}", time: TimeFormatter.format_relative_time(datetime))

  defp format_last_sync_info(_status, %NaiveDateTime{} = datetime),
    do: gettext("updated: %{time}", time: TimeFormatter.format_relative_time(datetime))

  defp format_last_sync_info(_status, _datetime), do: gettext("not synchronized yet")

  defp bank_account_menu_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp bank_account_menu_label(%{iban: iban}) when is_binary(iban) and iban != "", do: iban
  defp bank_account_menu_label(_account), do: pgettext("bank account fallback", "bank")

  defp format_iban(nil), do: ""

  defp format_iban(iban) do
    iban
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join(" ", &Enum.join/1)
  end

  defp yes_no(true), do: gettext("Yes")
  defp yes_no(false), do: gettext("No")
  defp yes_no(_), do: "—"

  defp multiline_address(nil), do: "—"
  defp multiline_address(""), do: "—"
  defp multiline_address(address), do: to_string(address)

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
