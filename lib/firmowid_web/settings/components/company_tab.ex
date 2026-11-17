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
  import FirmowidWeb.Settings.Components.Helpers, only: [present: 1]
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.TimeFormatter
  alias FirmowidUI.Components.Inputs
  alias FirmowidWeb.Analysis.Utilities.Industry
  alias FirmowidWeb.Invoicing.Utilities.VatExemption
  alias FirmowidWeb.Settings.Components.Helpers
  alias FirmowidWeb.Settings.Components.TaxSection
  alias FirmowidWeb.Settings.Utilities.RegisterCheck
  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.Rendered

  @doc """
  Renders the company settings route.
  """
  @spec company_tab(map()) :: Rendered.t()
  attr :company_form, :map, required: true
  attr :ksef_credential, :any, required: true
  attr :ksef_auth_method, :atom, required: true
  attr :ksef_auth_status, :atom, required: true
  attr :ksef_failure, :any, default: nil
  attr :bank_accounts, :list, required: true
  attr :bank_institutions, :map, required: true
  attr :pending_requisitions, :list, required: true
  attr :uploads, :map, required: true
  attr :ksef_fetching?, :boolean, required: true
  attr :current_org, :map, required: true
  attr :organization_users, :list, required: true
  attr :scope, :any, required: true

  attr :taxes?, :boolean,
    default: false,
    doc: "whether the `taxes` flag shows the taxes and ZUS card"

  attr :section, :atom, required: true, values: [:organization, :ksef, :bank_accounts]

  def company_tab(assigns) do
    ~H"""
    <div class="flex flex-col gap-8">
      <.company_details_form
        :if={@section == :organization}
        company_form={@company_form}
        register={RegisterCheck.status(@current_org)}
      />

      <div :if={@section == :organization and @taxes?}>
        <.live_component
          module={TaxSection}
          id="tax-section"
          organization={@current_org}
          scope={@scope}
          members={@organization_users}
        />
      </div>

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
        :if={@section == :bank_accounts}
        bank_accounts={@bank_accounts}
        bank_institutions={@bank_institutions}
        pending_requisitions={@pending_requisitions}
      />
    </div>
    """
  end

  attr :company_form, :map, required: true
  attr :register, :map, required: true

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
        <div class="flex flex-col gap-2">
          <Helpers.settings_field label="NIP" for={@company_form[:nip].id}>
            <.input field={@company_form[:nip]} type="text" input_class="w-full" />
          </Helpers.settings_field>
          <.register_status register={@register} />
          <.register_problem register={@register} field={:nip} />
        </div>
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
        <.register_problem register={@register} field={:is_vat_payer} class="-mbs-3 sm:col-span-2" />
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

  attr :register, :map, required: true

  # What the VAT white list and CEIDG last said about the NIP (`VatIdCheckWorker`),
  # as a quiet line: only an answer that is itself a problem stands out.
  defp register_status(assigns) do
    ~H"""
    <p
      id="organization-register-status"
      data-result={@register.result}
      class="text-sm/snug text-grey-700"
    >
      <span class={[@register.danger? && "font-medium text-brick-700"]}>{@register.label}</span>
      <span :if={@register.meta}>· {@register.meta}</span>
    </p>
    """
  end

  attr :register, :map, required: true
  attr :field, :atom, required: true
  attr :class, :any, default: nil

  # The contradiction shows under the detail it concerns; the inbox links to it.
  defp register_problem(assigns) do
    ~H"""
    <div :if={@register.problem && @register.field == @field} id="rejestry" class={@class}>
      <Inputs.error>{@register.problem}</Inputs.error>
    </div>
    """
  end

  attr :bank_accounts, :list, required: true
  attr :bank_institutions, :map, required: true
  attr :pending_requisitions, :list, required: true

  defp bank_accounts_section(assigns) do
    ~H"""
    <section class="space-y-4">
      <.pending_requisition_banner :if={Enum.any?(@pending_requisitions)} />

      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-end">
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

  attr :account, :map, required: true
  attr :bank_institutions, :map, required: true
  attr :status, :atom, default: nil

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
      class="relative flex flex-col gap-4 rounded-md bg-white p-5"
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
        <%!-- Renames in place and saves when the field loses focus or on Enter. --%>
        <.bank_detail_row label={gettext("Name")} for={"bank_account_name_#{@account.id}"}>
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
            size="small"
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

  # The white card of the company settings pages, as in the inbox.
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
end
