defmodule FirmowidWeb.Settings.Components.CompanyTab do
  @moduledoc """
  Function components for the company settings route.
  """

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.InvoicingBadges
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.Settings.Components.EditButton
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Core.UserRole
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter
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

  def company_tab(assigns) do
    ~H"""
    <div class="grid items-start gap-8 lg:grid-cols-2 lg:gap-14">
      <div class="space-y-14">
        <.company_basic_info_section
          current_org={@current_org}
          company_form={@company_form}
          editing_basic_info={@editing_basic_info}
        />

        <.ksef_section
          ksef_credential={@ksef_credential}
          ksef_auth_method={@ksef_auth_method}
          ksef_auth_status={@ksef_auth_status}
          ksef_failure={@ksef_failure}
          uploads={@uploads}
        />
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
              <.switch field={@company_form[:is_vat_payer]} color="turquoise" />
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
                  new
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
                    new
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
                color="turquoise"
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

  attr :ksef_credential, :any, required: true
  attr :ksef_auth_method, :atom, required: true
  attr :ksef_auth_status, :atom, required: true
  attr :ksef_failure, :any, default: nil
  attr :uploads, :map, required: true

  defp ksef_section(assigns) do
    ~H"""
    <.company_section title="Integracja z KSeF">
      <%= if @ksef_credential do %>
        <div class="flex flex-col gap-2">
          <.detail_row label="Status" wide>
            <%= if @ksef_auth_status == :refreshing do %>
              <span class="inline-flex items-center gap-2">
                <span>Trwa odnawianie certyfikatu KSeF</span>
                <.icon name="hero-arrow-path" class="text-grey-700 size-5 animate-spin" />
              </span>
            <% else %>
              <span class="inline-flex items-center gap-2">
                <span>Połączono z KSeF</span>
                <.icon name="hero-check-circle-solid" class="size-5 text-green-700" />
              </span>
            <% end %>
          </.detail_row>
          <.detail_row label="Typ autoryzacji" wide>
            {case @ksef_credential.auth_type do
              :token -> "Token"
              :certificate -> "Certyfikat"
              :generated_certificate -> "Certyfikat wygenerowany przez Firmowid"
            end}
          </.detail_row>
          <.detail_row label="Data wygaśnięcia" wide>
            {if @ksef_credential.expires_on,
              do: TimeFormatter.format_date(@ksef_credential.expires_on),
              else: "-"}
          </.detail_row>
          <Helpers.settings_display_field class="mt-2">
            <.button
              size="small"
              type="button"
              variant="destructive"
              phx-click={show_modal("confirm_disconnect_ksef")}
            >
              Rozłącz
            </.button>
          </Helpers.settings_display_field>
        </div>
      <% else %>
        <.detail_row label="Status" wide>
          <span class="inline-flex items-center gap-2">
            <span>Niepołączono z KSeF</span>
            <.icon name="hero-x-circle-solid text-red-700" class="size-5" />
          </span>
        </.detail_row>

        <div class="text-grey-800 mt-8 mb-3">
          Połącz KSeF jedną z trzech metod
        </div>

        <div
          class="mb-4 grid w-full max-w-lg grid-cols-1 gap-2 sm:grid-cols-3"
          role="tablist"
          aria-label="Metoda uwierzytelnienia KSeF"
        >
          <.ksef_auth_tab
            method={:trusted_profile}
            current_method={@ksef_auth_method}
            label="Profil Zaufany"
            panel_id="ksef-external-signature-flow"
          />
          <.ksef_auth_tab
            method={:certificate}
            current_method={@ksef_auth_method}
            label="Certyfikat KSeF"
            panel_id="ksef-certificate-auth-flow"
          />
          <.ksef_auth_tab
            method={:token}
            current_method={@ksef_auth_method}
            label="Token"
            panel_id="ksef-token-auth-flow"
          />
        </div>

        <div
          :if={@ksef_auth_method == :token}
          id="ksef-token-auth-flow"
          role="tabpanel"
          aria-labelledby="ksef-auth-tab-token"
          class="w-full max-w-lg space-y-5"
        >
          <div class="text-grey-900 flex gap-3 rounded-lg border border-orange-700 bg-orange-200 p-4 text-sm">
            <.icon
              name="hero-exclamation-triangle-solid"
              class="mt-0.5 size-5 shrink-0 text-orange-800"
            />
            <div class="text-orange-800">
              <p class="font-semibold">Metoda wygaszana</p>
              <p class="mt-1">
                Tokeny KSeF będą obsługiwane tylko do 1 stycznia 2027 roku. Zalecamy
                uwierzytelnienie Profilem Zaufanym lub certyfikatem KSeF.
              </p>
            </div>
          </div>

          <p class="text-grey-600 text-sm">
            Wykonaj poniższe kroki, aby połączyć Firmowid z KSeF.
          </p>

          <ol class="space-y-6">
            <.ksef_step number={1}>
              <:title>Wygeneruj token</:title>
              <:content>
                Wejdź na stronę <.link
                  kind="unstyled"
                  external="https://ap.ksef.mf.gov.pl/web/"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-orangeText inline-flex items-center gap-1 text-sm underline underline-offset-4"
                >
                  KSeF
                </.link>, zaloguj się i wygeneruj token z uprawnieniami do wystawiania i przeglądania faktur.
              </:content>
            </.ksef_step>

            <.ksef_step number={2} content_class="mt-3">
              <:title><label for="ksef_token">Wklej token</label></:title>
              <:content>
                <form phx-submit="save_ksef_token" id="ksef-token-form" class="space-y-4">
                  <.input
                    type="password"
                    id="ksef_token"
                    name="ksef_token"
                    value=""
                    required
                    new
                    input_class="w-full"
                  />

                  <div class="flex justify-end">
                    <.button
                      type="submit"
                      variant="secondary"
                      size="small"
                      phx-disable-with="Łączenie..."
                    >
                      Połącz z KSeF
                    </.button>
                  </div>
                </form>

                <.ksef_auth_status
                  status={@ksef_auth_status}
                  failure={@ksef_failure}
                />
              </:content>
            </.ksef_step>
          </ol>
        </div>

        <div
          :if={@ksef_auth_method == :trusted_profile}
          id="ksef-external-signature-flow"
          role="tabpanel"
          aria-labelledby="ksef-auth-tab-trusted_profile"
          class="w-full max-w-lg space-y-5"
        >
          <p class="text-grey-600 text-sm">
            Wykonaj poniższe kroki, aby połączyć Firmowid z KSeF.
          </p>

          <ol class="space-y-6">
            <.ksef_step number={1} class="justify-items-start">
              <:title>
                <.button
                  id="download-ksef-auth-token-request"
                  phx-hook=".KsefAuthDownload"
                  type="button"
                  variant="unstyled"
                  class="cursor-pointer underline"
                  phx-click="download_ksef_auth_token_request"
                >
                  Pobierz wniosek
                </.button>
              </:title>
            </.ksef_step>

            <.ksef_step number={2}>
              <:title>Podpisz plik</:title>
              <:content>
                Podpisz pobrany plik
                <.link
                  kind="unstyled"
                  external="https://podpis.gov.pl/podpisz-dokument-elektronicznie/"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-orangeText inline-flex items-center gap-1 text-sm underline underline-offset-4"
                >
                  Profilem Zaufanym
                </.link>
                lub podpisem kwalifikowanym.
              </:content>
            </.ksef_step>

            <.ksef_step number={3} content_class="mt-3">
              <:title>
                <label for={@uploads.signed_auth_token_request.ref}>Wgraj podpisany plik</label>
              </:title>
              <:content>
                <form
                  phx-change="validate_signed_auth_token_request"
                  phx-submit="upload_signed_auth_token_request"
                  id="ksef-signed-auth-token-request-form"
                  class="space-y-4"
                >
                  <.file_upload
                    upload={@uploads.signed_auth_token_request}
                    prompt="Dodaj podpisany plik (.xml)"
                    error_formatter={&present_upload_error/1}
                    show_errors={false}
                  />

                  <div
                    :if={@ksef_auth_status in [:idle, :working, :failed]}
                    class="flex justify-end"
                  >
                    <.button
                      type="submit"
                      variant="secondary"
                      size="small"
                      phx-disable-with="Wysyłanie..."
                    >
                      Wyślij plik
                    </.button>
                  </div>
                </form>

                <.ksef_auth_status
                  status={@ksef_auth_status}
                  failure={@ksef_failure}
                />
              </:content>
            </.ksef_step>
          </ol>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".KsefAuthDownload">
            export default {
              mounted() {
                this.handleEvent("download-ksef-auth-token-request", ({ content, filename }) => {
                  const blob = new Blob([content], { type: "application/xml;charset=utf-8" })
                  const url = URL.createObjectURL(blob)
                  const link = document.createElement("a")
                  link.href = url
                  link.download = filename
                  link.click()
                  URL.revokeObjectURL(url)
                })
              }
            }
          </script>
        </div>

        <div
          :if={@ksef_auth_method == :certificate}
          id="ksef-certificate-auth-flow"
          role="tabpanel"
          aria-labelledby="ksef-auth-tab-certificate"
          class="w-full max-w-lg space-y-5"
        >
          <p class="text-grey-600 text-sm">
            Wykonaj poniższe kroki, aby połączyć Firmowid z KSeF.
          </p>

          <ol class="space-y-6">
            <.ksef_step number={1}>
              <:title>Wygeneruj certyfikat KSeF</:title>
              <:content>
                Wejdź na stronę <.link
                  kind="unstyled"
                  external="https://ap.ksef.mf.gov.pl/web/"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-orangeText inline-flex items-center gap-1 text-sm underline underline-offset-4"
                >
                  KSeF
                </.link>, zaloguj się i wygeneruj certyfikat o przeznaczeniu <span class="font-medium">„Uwierzytelnienie w systemie KSeF”</span>.
              </:content>
            </.ksef_step>

            <.ksef_step number={2}>
              <:title>Wgraj certyfikat i klucz prywatny</:title>
              <:content>
                Dodaj pobrane pliki .crt i .key, a następnie podaj hasło do klucza prywatnego.
                <form
                  phx-change="validate_ksef_certificate"
                  phx-submit="save_ksef_certificate"
                  id="ksef-certificate-form"
                  class="mt-3 space-y-4"
                >
                  <.file_upload
                    upload={@uploads.ksef_credentials}
                    prompt="Dodaj certyfikat i klucz prywatny"
                    prompt_class="font-medium"
                    error_formatter={&present_upload_error/1}
                  />

                  <Helpers.settings_field
                    label="Hasło do klucza prywatnego"
                    class="w-full"
                    for="private_key_password"
                  >
                    <.input
                      type="password"
                      name="private_key_password"
                      id="private_key_password"
                      value=""
                      required
                      new
                      input_class="w-full"
                    />
                  </Helpers.settings_field>

                  <div class="flex justify-end">
                    <.button
                      type="submit"
                      variant="secondary"
                      size="small"
                      phx-disable-with="Łączenie..."
                    >
                      Wyślij certyfikat
                    </.button>
                  </div>
                </form>

                <.ksef_auth_status
                  status={@ksef_auth_status}
                  failure={@ksef_failure}
                />
              </:content>
            </.ksef_step>
          </ol>
        </div>
      <% end %>

      <.modal id="confirm_disconnect_ksef">
        <h3 class="text-grey-900 text-lg font-semibold">Potwierdź rozłączenie</h3>
        <p class="text-grey-700 mt-3 text-sm">
          Rozłączenie zatrzyma bieżącą integrację KSeF dla tej organizacji.
        </p>

        <div class="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
          <.button
            type="button"
            variant="secondary"
            size="small"
            phx-click={hide_modal("confirm_disconnect_ksef")}
          >
            Anuluj
          </.button>

          <.button
            type="button"
            variant="destructive"
            size="small"
            phx-click={JS.push("disconnect_ksef") |> hide_modal("confirm_disconnect_ksef")}
          >
            Rozłącz
          </.button>
        </div>
      </.modal>
    </.company_section>
    """
  end

  attr :number, :integer, required: true
  attr :class, :string, default: nil
  attr :content_class, :string, default: nil
  slot :title, required: true
  slot :content

  defp ksef_step(assigns) do
    ~H"""
    <li class={["grid grid-cols-[min-content_1fr] items-center gap-x-3", @class]}>
      <span class="bg-orangeText flex size-7 shrink-0 items-center justify-center rounded-full text-sm font-semibold text-white">
        {@number}
      </span>
      <div class="text-grey-900 text-sm font-semibold">
        {render_slot(@title)}
      </div>
      <div :for={content <- @content} class={["text-grey-600 col-start-2 text-sm", @content_class]}>
        {render_slot(content)}
      </div>
    </li>
    """
  end

  attr :method, :atom, required: true
  attr :current_method, :atom, required: true
  attr :label, :string, required: true
  attr :panel_id, :string, required: true

  defp ksef_auth_tab(assigns) do
    ~H"""
    <.button
      id={"ksef-auth-tab-#{@method}"}
      type="button"
      role="tab"
      aria-selected={if(@current_method == @method, do: "true", else: "false")}
      aria-controls={@panel_id}
      variant={if(@current_method == @method, do: "secondary", else: "outline")}
      size="small"
      phx-click="select_ksef_auth_method"
      phx-value-method={@method}
      class="w-full focus:outline-none focus-visible:ring-2 focus-visible:ring-orange-700"
    >
      {@label}
    </.button>
    """
  end

  attr :status, :atom, required: true
  attr :failure, :any, default: nil

  defp ksef_auth_status(assigns) do
    ~H"""
    <div
      :if={
        @status in [
          :authenticating_epuap,
          :preparing_enrollment,
          :wait_for_certificate,
          :authenticating,
          :failed
        ] || @failure
      }
      role="status"
      class={[
        "mt-4 flex items-start gap-2 rounded-lg border px-3 py-2.5 text-sm",
        if(@status == :failed,
          do: "border-red-200 bg-red-50 text-red-900",
          else: "bg-grey-50 border-grey-200 text-grey-700"
        )
      ]}
    >
      <.icon
        :if={@status == :failed}
        name="hero-x-circle-solid"
        class="mt-0.5 size-5 shrink-0 text-red-700"
      />
      <.icon
        :if={@status != :failed}
        name="hero-arrow-path"
        class="mt-0.5 size-5 shrink-0 animate-spin"
      />

      <span>{failure_message(@failure) || present_ksef_auth_status(@status)}</span>
    </div>
    """
  end

  defp present_upload_error(:too_large), do: "Plik jest za duży."
  defp present_upload_error(:too_many_files), do: "Wybierz dokładnie dwa pliki."
  defp present_upload_error(:not_accepted), do: "Dozwolone są tylko pliki .crt i .key."

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
        <h2 class="text-grey-900 text-base leading-none font-semibold">Konta bankowe</h2>

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

      <div :if={Enum.empty?(@bank_accounts)} class="text-grey-700 text-sm leading-[1.35]">
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
    <section class="border-grey-200 rounded-lg border bg-white px-6 py-5 shadow-sm">
      <div class="flex items-start gap-4">
        <span class="bg-blueBg text-blueText inline-flex size-10 items-center justify-center rounded-full">
          <.icon name="hero-arrow-path" class="size-5 animate-spin" />
        </span>

        <div class="text-grey-900 space-y-1 text-sm leading-[1.35]">
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
        <h2 class="text-grey-900 text-base/normal font-semibold">Członkowie organizacji</h2>

        <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
          <.button
            type="button"
            variant="unstyled"
            phx-click="toggle_active_invites"
            role="switch"
            size="small"
            aria-checked={to_string(@show_active_invites)}
            class="text-grey-700 inline-flex h-11 items-center justify-between gap-3 rounded-lg bg-white px-3 text-sm font-medium transition focus:outline-none focus-visible:ring-2 focus-visible:ring-orange-700"
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
        class="border-grey-200 scrollbar-card h-151 overflow-y-auto rounded-lg border bg-white p-6 shadow-sm"
      >
        <div
          :if={@active_invites == []}
          class="text-grey-700 flex min-h-96 items-center justify-center text-sm leading-[1.35]"
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
              class="bg-turquoise-100 text-turquoise-700 flex w-full max-w-80 cursor-pointer items-center justify-between gap-5 rounded p-1 py-2 pl-3 text-sm"
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
                aria-label="Usuń zaproszenie"
              >
                <Lucideicons.trash_2 class="hover:text-darkGrey text-grey-500 transition-all" />
              </.button>
            </div>
          </div>
        </div>
      </div>

      <div
        :if={not @show_active_invites}
        class="border-grey-200 scrollbar-card h-151 overflow-y-auto rounded-lg border bg-white p-6 shadow-sm"
      >
        <div class="flex flex-col gap-6">
          <div
            :for={user <- @organization_users}
            class="flex min-h-12 flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
          >
            <div class="flex min-w-0 items-center gap-4 sm:max-w-sm sm:flex-1">
              <.avatar class="bg-grey-100 size-12 rounded-full">
                <.avatar_image
                  :if={user.avatar_blob && user.avatar_blob.url}
                  src={user.avatar_blob.url}
                  alt={user.name || user.email}
                />
                <.avatar_fallback class="text-grey-700 text-sm font-medium">
                  {initial(user.name || user.email)}
                </.avatar_fallback>
              </.avatar>

              <div class="flex min-w-0 flex-col gap-0.5">
                <p class="text-grey-900 truncate text-base leading-[1.35]">{present(user.name)}</p>
                <p class="text-grey-700 truncate text-sm leading-[1.35]">{user.email}</p>
              </div>
            </div>

            <div class="flex items-center justify-end gap-2">
              <span class={role_badge_styles(user.role)}>{UserRole.label(user.role)}</span>

              <.dropdown :if={user.id != @current_user.id} id={"organization_user_#{user.id}"}>
                <:trigger>
                  <span class="hover:bg-grey-100 text-grey-700 flex size-10 items-center justify-center rounded-lg transition">
                    <span class="sr-only">Opcje użytkownika {present(user.email)}</span>
                    <.icon name="hero-ellipsis-vertical" class="size-6" />
                  </span>
                </:trigger>

                <div class="border-grey-200 mt-10 flex w-40 flex-col overflow-hidden rounded-lg border bg-white p-1 shadow-lg">
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
                    class={["text-red-800 hover:bg-red-100", menu_item_styles()]}
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
    <article class="border-grey-200 relative flex flex-col gap-4 rounded-lg border bg-white p-4">
      <div class="flex items-center justify-start gap-4">
        <.bank_badge institution={@account} />
        <div class="flex items-start gap-4 self-start">
          <div class="flex flex-wrap gap-2.5">
            <span
              :if={@account.is_default}
              class="rounded-full bg-green-100 px-4 py-1 text-sm text-green-700"
            >
              Domyślne <span class="font-semibold">{present(@account.currency)}</span>
            </span>
            <span
              :if={!@account.is_default}
              class="bg-grey-100 text-grey-700 rounded-full px-4 py-1 font-semibold"
            >
              {present(@account.currency)}
            </span>
          </div>
        </div>

        <div class="flex flex-1 justify-end">
          <.dropdown id={"bank_account_#{@account.id}"}>
            <:trigger>
              <span class="hover:bg-grey-100 text-grey-700 inline-flex size-8 items-center justify-center rounded-lg transition">
                <span class="sr-only">Opcje konta {bank_account_menu_label(@account)}</span>
                <.icon name="hero-ellipsis-horizontal" class="size-5" />
              </span>
            </:trigger>

            <div class="border-grey-200 text-grey-700 flex w-48 flex-col overflow-hidden rounded-lg border bg-white py-1 text-sm font-medium shadow-lg">
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
                class={["text-red-700 hover:bg-red-100", menu_item_styles()]}
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
            <span class="font-medium text-red-800">Konto rozłączone</span>
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
      <h3 class="text-grey-900 text-lg font-semibold">Potwierdź usunięcie</h3>
      <p class="text-grey-700 mt-3 text-sm">
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
          <h3 class="text-grey-900 text-lg font-semibold">Dodaj konto bankowe ręcznie</h3>
          <p class="text-grey-700 mt-2 text-sm">
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
              accent="turquoise"
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
    current_role = assigns.user.role
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
          Zmieniasz rolę użytkownikowi {present(@user.name || to_string(@user.email))}. Jego dotychczasowa rola to:
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
              accent="turquoise"
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
    <label class="text-grey-700 text-sm">{@label}</label>
    <div class="text-base leading-[1.35]">
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
      <.input field={@field} type={@type} new input_class="w-full" />
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
        class="border-grey-300 checked:bg-turquoise-700 text-turquoise-700 size-5 shrink-0 appearance-none rounded-full border-2 bg-white focus:outline-none"
      />
      <div>
        <span class="font-medium capitalize">{UserRole.label(@role)}</span>
        <p class="text-sm">{role_desc(@role)}</p>
      </div>
    </.label>
    """
  end

  defp invite_toggle_track_styles(true), do: "bg-turquoise-700 relative inline-flex h-[24px] w-[44px] rounded-full"

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
    "hover:text-turquoise-800 hover:bg-turquoise-100 w-full justify-start rounded-none px-3 py-2 text-left text-sm transition cursor-pointer"
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

  defp failure_message(nil), do: nil
  defp failure_message(%{reason: reason}), do: credential_failure_message(reason)

  defp credential_failure_message(:certificate_limit_exhausted) do
    "Osiągnięto limit certyfikatów KSeF."
  end

  defp credential_failure_message(:invalid_credentials) do
    "Nie udało się uwierzytelnić w KSeF. Sprawdź certyfikat, klucz oraz hasło i spróbuj ponownie."
  end

  defp credential_failure_message(:authentication_failed) do
    "Uwierzytelnienie w KSeF nie powiodło się."
  end

  defp credential_failure_message(_reason) do
    "Wystąpił błąd podczas generowania certyfikatu KSeF."
  end

  defp present_ksef_auth_status(:authenticating), do: "Trwa uwierzytelnianie w KSeF."

  defp present_ksef_auth_status(:authenticating_epuap), do: "Trwa uwierzytelnianie w KSeF."

  defp present_ksef_auth_status(:preparing_enrollment) do
    "Trwa przygotowanie wniosku o certyfikat."
  end

  defp present_ksef_auth_status(:wait_for_certificate), do: "KSeF wystawia certyfikat."

  defp present_ksef_auth_status(:failed) do
    "Nie udało się połączyć z KSeF. Spróbuj ponownie."
  end

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
    "bg-turquoise-200 text-turquoise-700 inline-flex w-28 items-center justify-center rounded-sm px-3 py-1 text-sm leading-[1.35]"
  end

  defp role_badge_styles(:accountant) do
    "bg-green-200 text-green-700 inline-flex w-28 items-center justify-center rounded-sm px-3 py-1 text-sm leading-[1.35]"
  end

  defp role_badge_styles(:invoicing) do
    "bg-orange-200 text-orange-700 inline-flex w-28 items-center justify-center rounded-sm px-3 py-1 text-sm leading-[1.35]"
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
