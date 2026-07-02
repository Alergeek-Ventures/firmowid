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

  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter
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
  attr :correspondence_form, :map, required: true
  attr :editing_basic_info, :boolean, required: true
  attr :editing_correspondence, :boolean, required: true
  attr :ksef_credential, :any, required: true
  attr :ksef_auth_method, :atom, required: true
  attr :ksef_certificate_status, :atom, required: true
  attr :bank_accounts, :list, required: true
  attr :bank_institutions, :map, required: true
  attr :pending_requisitions, :list, required: true
  attr :organization_users, :list, required: true
  attr :organization_invites, :list, required: true
  attr :show_active_invites, :boolean, required: true
  attr :bank_account_statuses, :map, required: true
  attr :uploads, :map, required: true

  def company_tab(assigns) do
    ~H"""
    <div class="grid items-start gap-8 lg:grid-cols-2 lg:gap-16">
      <.company_basic_info_section
        current_org={@current_org}
        company_form={@company_form}
        editing_basic_info={@editing_basic_info}
      />

      <.organization_avatar
        current_org={@current_org}
        current_user={@current_user}
        organization_avatar_upload={@uploads.organization_avatar}
      />

      <.correspondence_section
        current_org={@current_org}
        correspondence_form={@correspondence_form}
        editing_correspondence={@editing_correspondence}
      />

      <.ksef_section
        ksef_credential={@ksef_credential}
        ksef_auth_method={@ksef_auth_method}
        ksef_certificate_status={@ksef_certificate_status}
        uploads={@uploads}
      />

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
        current_user={@current_user}
      />
    </div>
    """
  end

  attr :current_org, :map, required: true
  attr :current_user, :map, required: true
  attr :organization_avatar_upload, :any, default: nil

  def organization_avatar(assigns) do
    ~H"""
    <.company_section title="Logo organizacji">
      <div class="flex flex-row items-center gap-4">
        <.avatar class="size-16 rounded-full bg-white">
          <.avatar_image
            :if={@current_org.avatar_blob && @current_org.avatar_blob.url}
            src={@current_org.avatar_blob.url}
            alt={@current_org.name}
            class="object-contain"
          />
          <.avatar_fallback class="border-grey-100 text-grey-700 rounded-2xl border bg-white text-center text-lg font-semibold">
            {initial(@current_org.name)}
          </.avatar_fallback>
        </.avatar>

        <form
          :if={@current_user.role == :admin && @organization_avatar_upload}
          phx-submit="upload"
          phx-change="upload"
        >
          <.live_file_input
            upload={@organization_avatar_upload}
            class="peer sr-only"
            aria-label="Zmień logo organizacji"
          />

          <.button
            as="label"
            id="settings-organization-avatar-upload-tooltip"
            for={@organization_avatar_upload.ref}
            type="button"
            variant="outline"
            size="small"
            aria-label="Zmień logo organizacji"
            phx-hook="Tippy"
            data-tippy-content="Zmień logo organizacji"
            data-tippy-delay="100"
            class="size-10 rounded-full p-0"
          >
            <Lucideicons.square_pen />
          </.button>
        </form>
      </div>
    </.company_section>
    """
  end

  attr :title, :string, required: true
  attr :action, :any, default: nil
  attr :action_label, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp company_section(assigns) do
    ~H"""
    <section class={["space-y-3", @class]}>
      <div class="flex min-h-8 items-center gap-2.5">
        <h2 class="text-grey-900 text-base leading-none font-semibold">{@title}</h2>

        <span
          :if={@action}
          id={"settings-#{@action}-tooltip"}
          phx-hook="Tippy"
          data-tippy-content={@action_label || "Edytuj #{@title}"}
          data-tippy-delay="100"
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
      class={detail_row_styles(@wide)}
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
      action="toggle_editing_basic_info"
      action_label="Edytuj dane firmy"
    >
      <%= if @editing_basic_info do %>
        <.form for={@company_form} phx-submit="save" class="space-y-4">
          <div class="space-y-2">
            <.row_input field={@company_form[:name]} label="Nazwa" type="text" />
            <.row_input field={@company_form[:nip]} label="NIP" type="text" />

            <Helpers.settings_field label="Płatnik VAT" class="w-full max-w-sm">
              <span class="inline-flex items-center gap-3">
                <input
                  type="checkbox"
                  name={@company_form[:is_vat_payer].name}
                  checked={@company_form[:is_vat_payer].value in [true, "true"]}
                  class="border-grey-200 size-4 rounded text-orange-700"
                />
                <span class="text-grey-900 text-base">Tak</span>
              </span>
            </Helpers.settings_field>

            <.row_input field={@company_form[:address]} label="Adres" type="text" />
          </div>

          <div class="flex w-full max-w-sm justify-end gap-3">
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
          <.detail_row label="Adres" wide>{multiline_address(@current_org.address)}</.detail_row>
        </div>
      <% end %>
    </.company_section>
    """
  end

  attr :current_org, :map, required: true
  attr :correspondence_form, :map, required: true
  attr :editing_correspondence, :boolean, required: true

  defp correspondence_section(
         %{
           editing_correspondence: false,
           current_org: %{correspondence_name: correspondence_name, correspondence_address: correspondence_address}
         } = assigns
       )
       when is_nil(correspondence_name) and is_nil(correspondence_address) do
    ~H"""
    <.company_section
      title="Dane korespondencyjne"
      action="toggle_editing_correspondence"
      action_label="Dodaj dane korespondencyjne"
      class="row-span-2"
    >
      <div class="text-grey-700 text-sm">
        Nie dodano jeszcze danych korespondencyjnych. Jeżeli adres jest inny
        niż organizacji - dodaj je tutaj.
      </div>
    </.company_section>
    """
  end

  defp correspondence_section(assigns) do
    ~H"""
    <.company_section
      title="Dane korespondencyjne"
      action="toggle_editing_correspondence"
      action_label="Edytuj dane korespondencyjne"
    >
      <%= if @editing_correspondence do %>
        <.form for={@correspondence_form} phx-submit="save" class="space-y-4">
          <div class="space-y-2">
            <.row_input field={@correspondence_form[:correspondence_name]} label="Nazwa" type="text" />
            <.row_input
              field={@correspondence_form[:correspondence_address]}
              label="Adres"
              type="text"
            />
          </div>

          <div class="flex w-full max-w-sm justify-end gap-3">
            <.button
              type="button"
              variant="ghost"
              size="small"
              phx-click="toggle_editing_correspondence"
            >
              Anuluj
            </.button>
            <.button type="submit" variant="success" size="small">Zapisz</.button>
          </div>
        </.form>
      <% else %>
        <div class="space-y-2">
          <.detail_row label="Nazwa">{present(@current_org.correspondence_name)}</.detail_row>
          <.detail_row label="Adres">
            {multiline_address(@current_org.correspondence_address)}
          </.detail_row>
        </div>
      <% end %>
    </.company_section>
    """
  end

  attr :ksef_credential, :any, required: true
  attr :ksef_auth_method, :atom, required: true
  attr :ksef_certificate_status, :atom, required: true
  attr :uploads, :map, required: true

  defp ksef_section(assigns) do
    ~H"""
    <.company_section title="Integracja z KSeF" class="col-span-2">
      <%= if @ksef_credential do %>
        <div class="flex flex-col gap-4">
          <.detail_row label="Status" wide>
            <span class="inline-flex items-center gap-2">
              <span>Połączono z KSeF</span>
              <.icon name="hero-check-circle-solid" class="size-5 text-green-700" />
            </span>
          </.detail_row>
          <.detail_row label="Typ autoryzacji" wide>
            {case @ksef_credential.auth_type do
              :token -> "Token"
              :certificate -> "Certyfikat"
            end}
          </.detail_row>
          <.detail_row label="Data wygaśnięcia" wide>
            {TimeFormatter.format_date(@ksef_credential.expires_on)}
          </.detail_row>

          <.button
            class="max-w-[250px]"
            size="small"
            type="button"
            variant="destructive"
            phx-click={show_modal("confirm_disconnect_ksef")}
          >
            Rozłącz
          </.button>
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

                  <%= if @ksef_certificate_status not in [:idle, :awaiting_signature, :connected, :failed] do %>
                    <div class="text-grey-700 flex items-center gap-2 rounded-md py-2 text-sm">
                      <.icon name="hero-arrow-path" class="size-5 animate-spin" />
                      <span class="w-full">
                        {present_certificate_status(@ksef_certificate_status)}
                      </span>
                    </div>
                  <% else %>
                    <div class="flex justify-end">
                      <.button
                        type="submit"
                        variant="secondary"
                        size="small"
                        phx-disable-with="Wysyłanie..."
                      >
                        Wyślij plik
                      </.button>
                    </div>
                  <% end %>
                </form>
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

                  <Helpers.settings_field label="Hasło do klucza prywatnego" class="w-full">
                    <.input
                      type="password"
                      name="private_key_password"
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
            aria-checked={to_string(@show_active_invites)}
            class="border-grey-200 hover:bg-grey-100 text-grey-700 inline-flex min-h-11 items-center justify-between gap-3 rounded-lg border bg-white px-3 py-2 text-sm font-medium transition focus:outline-none focus-visible:ring-2 focus-visible:ring-orange-700 sm:min-h-10"
          >
            <span>Aktywne zaproszenia</span>
            <span class={invite_toggle_track_styles(@show_active_invites)}>
              <span class={invite_toggle_thumb_styles(@show_active_invites)}></span>
            </span>
          </.button>
          <.button
            id="settings-create-invite-tooltip"
            phx-hook="Tippy"
            data-tippy-content="Wygeneruj nowy kod i skopiuj go do schowka"
            data-tippy-delay="100"
            type="button"
            variant="primary"
            phx-click="create_organization_invite"
          >
            Wygeneruj zaproszenie
          </.button>
        </div>
      </div>

      <div
        :if={@show_active_invites}
        class="bg-grey-50 border-grey-200 rounded-lg border p-4"
      >
        <div
          :if={@active_invites == []}
          class="text-grey-700 flex min-h-96 items-center justify-center text-sm leading-[1.35]"
        >
          Brak aktywnych zaproszeń.
        </div>

        <div :if={@active_invites != []} class="space-y-3">
          <div
            :for={invite <- @active_invites}
            class="flex flex-col gap-3 rounded-lg bg-white p-3 shadow-sm sm:flex-row sm:items-center sm:justify-between"
          >
            <div class="min-w-0 space-y-1">
              <p class="text-grey-900 truncate font-mono text-sm">{invite.invite_code}</p>
              <p class="text-grey-600 text-xs leading-[1.35]">
                Ważne do {format_invite_expiration(invite.expires_at)} · utworzone przez {invite_issuer(
                  invite
                )}
              </p>
            </div>

            <span
              id={"settings-copy-invite-#{invite.id}-tooltip"}
              phx-hook="Tippy"
              data-tippy-content="Skopiuj kod zaproszenia"
              data-tippy-delay="100"
              class="shrink-0"
            >
              <.button
                type="button"
                variant="outline"
                size="small"
                phx-click="copy_organization_invite"
                phx-value-code={invite.invite_code}
              >
                Kopiuj
              </.button>
            </span>
          </div>
        </div>
      </div>

      <div
        :if={not @show_active_invites}
        class="border-grey-200 rounded-lg border bg-white p-6 shadow-sm"
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
              <span class={role_badge_styles(user.role)}>{role_label(user.role)}</span>

              <.dropdown :if={user.id != @current_user.id} id={"organization_user_#{user.id}"}>
                <:trigger>
                  <span class="hover:bg-grey-100 text-grey-700 flex size-10 items-center justify-center rounded-lg transition">
                    <span class="sr-only">Opcje użytkownika {present(user.email)}</span>
                    <.icon name="hero-ellipsis-vertical" class="size-6" />
                  </span>
                </:trigger>

                <div class="border-grey-200 flex w-60 flex-col overflow-hidden rounded-lg border bg-white py-1 shadow-lg">
                  <.button
                    :for={role <- promotable_roles(user.role)}
                    type="button"
                    variant="unstyled"
                    phx-click="update_user_role"
                    phx-value-user_id={user.id}
                    phx-value-role={role_param(role)}
                    class={menu_item_styles()}
                  >
                    Awansuj na {role_label(role)}
                  </.button>

                  <.button
                    :for={role <- demotable_roles(user.role)}
                    type="button"
                    variant="unstyled"
                    phx-click="update_user_role"
                    phx-value-user_id={user.id}
                    phx-value-role={role_param(role)}
                    class={menu_item_styles()}
                  >
                    Zdegraduj na {role_label(role)}
                  </.button>

                  <div class="bg-grey-100 mx-3 my-1 h-px"></div>

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
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :account, :map, required: true
  attr :bank_institutions, :map, required: true
  attr :status, :atom, default: nil

  defp bank_card(assigns) do
    ~H"""
    <article class="border-grey-200 relative flex flex-col gap-4 rounded-lg border bg-white p-4">
      <div class="flex items-center justify-start gap-4">
        <.bank_badge institution={@account.institution_id} />
        <div class="flex items-start gap-4">
          <div class="flex flex-wrap gap-2.5">
            <span
              :if={@account.is_default}
              class="text/tight rounded-full bg-green-200 px-3 py-1 text-green-700"
            >
              Domyślne {present(@account.currency)}
            </span>
            <span
              :if={!@account.is_default}
              class="bg-grey-100 text-grey-700 text/tight rounded-full px-3 py-1"
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
                class={["text-red-800 hover:bg-red-100", menu_item_styles()]}
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
          <span class="break-all">{present(@account.iban)}</span>
        </.bank_detail_row>
        <.bank_detail_row :if={@status} label="Status">
          <span :if={@status in [:broken, :disconnected]} class="inline-flex items-center gap-1.5">
            <span class="font-bold text-red-900">Konto rozłączone</span>
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
        <.input name="name" label="Nowa nazwa" value={@account.name} />

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
          <.input name="name" label="Nazwa konta" value="" />
          <.input name="owner_name" label="Właściciel" value="" />
          <.input name="iban" label="IBAN" value="" />
          <.input name="currency" label="Waluta" value="" />

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

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp bank_detail_row(assigns) do
    ~H"""
    <label class="text-grey-700 text-sm font-medium uppercase">{@label}</label>
    <div class="text-grey-900 text-base leading-[1.35]">
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :field, :map, required: true
  attr :label, :string, required: true
  attr :type, :string, required: true

  defp row_input(assigns) do
    ~H"""
    <Helpers.settings_field label={@label} class="w-full max-w-sm">
      <.input type={@type} name={@field.name} value={@field.value} new input_class="w-full" />
    </Helpers.settings_field>
    """
  end

  defp detail_row_styles(true), do: "w-full"
  defp detail_row_styles(false), do: "w-full max-w-sm"

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

  defp format_invite_expiration(expires_at), do: TimeFormatter.format_date(expires_at)

  defp invite_issuer(%{issued_by: %{email: email}}) when is_binary(email), do: email
  defp invite_issuer(_invite), do: "administratora"

  defp menu_item_styles do
    "text-grey-700 hover:bg-grey-100 hover:text-grey-900 w-full justify-start rounded-none px-3 py-2 text-left text-sm font-medium transition"
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

  defp yes_no(true), do: "Tak"
  defp yes_no(false), do: "Nie"
  defp yes_no(_), do: "—"

  defp present_certificate_status(:authenticating), do: "Trwa uwierzytelnianie w KSeF."

  defp present_certificate_status(:preparing_certificate), do: "Trwa przygotowanie wniosku o certyfikat."

  defp present_certificate_status(:waiting_for_certificate), do: "KSeF wystawia certyfikat."
  defp present_certificate_status(_status), do: ""

  defp role_label(:admin), do: "admin"
  defp role_label(:employee), do: "pracownik"
  defp role_label(:invoicing), do: "fakturowanie"
  defp role_label(:accountant), do: "księgowość"
  defp role_label(role), do: present(role)

  defp promotable_roles(role) do
    role
    |> role_index()
    |> then(&Enum.drop(role_ladder(), &1 + 1))
  end

  defp demotable_roles(role) do
    role
    |> role_index()
    |> then(&Enum.take(role_ladder(), &1))
    |> Enum.reverse()
  end

  defp role_param(role), do: Atom.to_string(role)

  defp role_index(role) do
    Enum.find_index(role_ladder(), &(&1 == role)) || 0
  end

  defp role_ladder, do: [:employee, :invoicing, :accountant, :admin]

  defp role_badge_styles(:admin) do
    "bg-blueBg text-blueText inline-flex w-28 items-center justify-center rounded-sm px-3 py-1 text-sm leading-[1.35]"
  end

  defp role_badge_styles(_role) do
    "bg-grey-100 text-grey-700 inline-flex w-28 items-center justify-center rounded-sm px-3 py-1 text-sm leading-[1.35]"
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
end
