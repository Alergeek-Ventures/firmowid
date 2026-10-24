defmodule FirmowidUI.Components.KsefConnection do
  @moduledoc "Shared presentation of the existing KSeF connection and authentication flows."

  use FirmowidUI, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Inputs
  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.LiveView.Rendered

  @doc "Renders KSeF connection content; the interface supplies its section or widget shell."
  @spec ksef_connection(map()) :: Rendered.t()
  attr :ksef_credential, :any, required: true
  attr :ksef_auth_method, :atom, required: true
  attr :ksef_auth_status, :atom, required: true
  attr :ksef_failure, :any, default: nil
  attr :uploads, :map, required: true
  attr :download_hook, :string, default: "KsefAuthDownload"
  attr :allow_token?, :boolean, default: true
  attr :allow_fetch?, :boolean, default: false
  attr :fetching?, :boolean, default: false

  def ksef_connection(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= if @ksef_credential do %>
        <div class="flex flex-col gap-2">
          <.detail_row label="Status">
            <%= if @ksef_auth_status == :refreshing do %>
              <span class="inline-flex items-center gap-2">
                <span>Trwa odnawianie certyfikatu KSeF</span>
                <.icon name="hero-arrow-path" class="size-5 text-grey-700 motion-safe:animate-spin" />
              </span>
            <% else %>
              <span class="inline-flex items-center gap-2">
                <span>Połączono z KSeF</span>
                <.icon name="hero-check-circle-solid" class="size-5 text-green-700" />
              </span>
            <% end %>
          </.detail_row>
          <.detail_row label="Typ autoryzacji">
            {case @ksef_credential.auth_type do
              :token -> "Token"
              :certificate -> "Certyfikat"
              :generated_certificate -> "Certyfikat wygenerowany przez Firmowid"
            end}
          </.detail_row>
          <.detail_row label="Data wygaśnięcia">
            {if @ksef_credential.expires_on,
              do: Calendar.strftime(@ksef_credential.expires_on, "%d.%m.%Y"),
              else: "-"}
          </.detail_row>
          <.detail_row class="mbs-2">
            <div class="flex flex-wrap gap-2">
              <.button
                size="small"
                type="button"
                variant="destructive"
                {%{popovertarget: "confirm_disconnect_ksef"}}
              >
                Rozłącz
              </.button>
              <.button
                :if={@allow_fetch?}
                size="small"
                type="button"
                variant="secondary"
                phx-click="fetch_ksef_invoices"
                disabled={@fetching?}
              >
                {if @fetching?, do: "Trwa pobieranie faktur", else: "Pobierz faktury z KSeF"}
              </.button>
            </div>
          </.detail_row>
        </div>
      <% else %>
        <.detail_row label="Status">
          <span class="inline-flex items-center gap-2">
            <span>Niepołączono z KSeF</span>
            <.icon name="hero-x-circle-solid" class="size-5 text-red-700" />
          </span>
        </.detail_row>

        <div class="mbs-8 mbe-3 text-grey-800">
          <%= if @allow_token? do %>
            Połącz KSeF jedną z trzech metod
          <% else %>
            {gettext("Connect KSeF with a trusted profile or certificate.")}
          <% end %>
        </div>

        <div
          class="mbe-4 grid w-full max-w-lg grid-cols-[repeat(auto-fit,minmax(min(100%,9rem),1fr))] gap-2"
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
            :if={@allow_token?}
            method={:token}
            current_method={@ksef_auth_method}
            label="Token"
            panel_id="ksef-token-auth-flow"
          />
        </div>

        <div
          :if={@allow_token? and @ksef_auth_method == :token}
          id="ksef-token-auth-flow"
          role="tabpanel"
          aria-labelledby="ksef-auth-tab-token"
          class="w-full max-w-lg space-y-5"
        >
          <div class="flex gap-3 rounded-lg border border-orange-700 bg-orange-200 p-4 text-sm text-grey-900">
            <.icon
              name="hero-exclamation-triangle-solid"
              class="mbs-0.5 size-5 shrink-0 text-orange-800"
            />
            <div class="text-orange-800">
              <p class="font-semibold">Metoda wygaszana</p>
              <p class="mbs-1">
                Tokeny KSeF będą obsługiwane tylko do 1 stycznia 2027 roku. Zalecamy
                uwierzytelnienie Profilem Zaufanym lub certyfikatem KSeF.
              </p>
            </div>
          </div>

          <p class="text-sm text-grey-600">Wykonaj poniższe kroki, aby połączyć Firmowid z KSeF.</p>

          <ol class="space-y-6">
            <.ksef_step number={1}>
              <:title>Wygeneruj token</:title>
              <:content>
                Wejdź na stronę <.link
                  kind="unstyled"
                  external="https://ap.ksef.mf.gov.pl/web/"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex items-center gap-1 text-sm text-orangeText underline underline-offset-4"
                >
                  KSeF
                </.link>, zaloguj się i wygeneruj token z uprawnieniami do wystawiania i przeglądania faktur.
              </:content>
            </.ksef_step>

            <.ksef_step number={2} content_class="mbs-3">
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
                <.ksef_auth_status status={@ksef_auth_status} failure={@ksef_failure} />
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
          <p class="text-sm text-grey-600">Wykonaj poniższe kroki, aby połączyć Firmowid z KSeF.</p>
          <ol class="space-y-6">
            <.ksef_step number={1} class="justify-items-start">
              <:title>
                <.button
                  id="download-ksef-auth-token-request"
                  phx-hook={@download_hook}
                  type="button"
                  variant="unstyled"
                  class="cursor-pointer underline focus-visible:outline-2 active:opacity-80"
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
                  class="inline-flex items-center gap-1 text-sm text-orangeText underline underline-offset-4"
                >
                  Profilem Zaufanym
                </.link>
                lub podpisem kwalifikowanym.
              </:content>
            </.ksef_step>
            <.ksef_step number={3} content_class="mbs-3">
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
                    show_errors={false}
                  />
                  <div :if={@ksef_auth_status in [:idle, :working, :failed]} class="flex justify-end">
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
                <.ksef_auth_status status={@ksef_auth_status} failure={@ksef_failure} />
              </:content>
            </.ksef_step>
          </ol>
        </div>

        <div
          :if={@ksef_auth_method == :certificate}
          id="ksef-certificate-auth-flow"
          role="tabpanel"
          aria-labelledby="ksef-auth-tab-certificate"
          class="w-full max-w-lg space-y-5"
        >
          <p class="text-sm text-grey-600">Wykonaj poniższe kroki, aby połączyć Firmowid z KSeF.</p>
          <ol class="space-y-6">
            <.ksef_step number={1}>
              <:title>Wygeneruj certyfikat KSeF</:title>
              <:content>
                Wejdź na stronę <.link
                  kind="unstyled"
                  external="https://ap.ksef.mf.gov.pl/web/"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex items-center gap-1 text-sm text-orangeText underline underline-offset-4"
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
                  class="mbs-3 space-y-4"
                >
                  <.file_upload
                    upload={@uploads.ksef_credentials}
                    prompt="Dodaj certyfikat i klucz prywatny"
                    prompt_class="font-medium"
                  />
                  <label for="private_key_password" class="flex w-full flex-col gap-1">
                    <span class="text-sm leading-[1.35] text-grey-700">Hasło do klucza prywatnego</span>
                    <.input
                      type="password"
                      name="private_key_password"
                      id="private_key_password"
                      value=""
                      required
                      new
                      input_class="w-full"
                    />
                  </label>
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
                <.ksef_auth_status status={@ksef_auth_status} failure={@ksef_failure} />
              </:content>
            </.ksef_step>
          </ol>
        </div>
      <% end %>

      <div
        id="confirm_disconnect_ksef"
        popover
        role="alertdialog"
        aria-labelledby="confirm_disconnect_ksef_title"
        class="m-auto w-[min(90vi,32rem)] rounded-lg border border-grey-200 bg-white p-6 shadow-lg"
      >
        <h3 id="confirm_disconnect_ksef_title" class="text-lg font-semibold text-grey-900">
          Potwierdź rozłączenie
        </h3>
        <p class="mbs-3 text-sm text-grey-700">
          Rozłączenie zatrzyma bieżącą integrację KSeF dla tej organizacji.
        </p>
        <div class="mbs-6 flex flex-wrap justify-end gap-3">
          <.button
            type="button"
            variant="secondary"
            size="small"
            {%{popovertarget: "confirm_disconnect_ksef", popovertargetaction: "hide"}}
          >
            Anuluj
          </.button>
          <.button
            type="button"
            variant="destructive"
            size="small"
            phx-click="disconnect_ksef"
            {%{popovertarget: "confirm_disconnect_ksef", popovertargetaction: "hide"}}
          >
            Rozłącz
          </.button>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, default: ""
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp detail_row(assigns) do
    ~H"""
    <div class={["grid grid-cols-2 items-baseline gap-x-5", @class]}>
      <div class="text-end text-sm leading-[1.35] text-grey-700">{@label}</div>
      <div class="min-w-0 text-base leading-[1.35] wrap-break-word text-grey-900">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :upload, :any, required: true
  attr :prompt, :string, required: true
  attr :prompt_class, :string, default: nil
  attr :show_errors, :boolean, default: true

  defp file_upload(assigns) do
    ~H"""
    <label
      class="flex w-full cursor-pointer justify-center rounded-md border-2 border-dashed border-orangeText px-6 py-8 focus-within:outline-2 focus-within:outline-orange-700 active:opacity-80"
      phx-drop-target={@upload.ref}
    >
      <div class="text-center text-sm text-orangeText">
        <div :if={Enum.empty?(@upload.entries)} class={@prompt_class}>{@prompt}</div>
        <.live_file_input upload={@upload} class="sr-only" />
        <div :for={entry <- @upload.entries}>
          <p>{entry.client_name}</p>
          <p :for={error <- if(@show_errors, do: upload_errors(@upload, entry), else: [])}>
            {present_upload_error(error)}
          </p>
        </div>
        <p :for={error <- if(@show_errors, do: upload_errors(@upload), else: [])}>
          {present_upload_error(error)}
        </p>
      </div>
    </label>
    """
  end

  attr :number, :integer, required: true
  attr :class, :string, default: nil
  attr :content_class, :string, default: nil
  slot :title, required: true
  slot :content

  defp ksef_step(assigns) do
    ~H"""
    <li class={["grid grid-cols-[min-content_minmax(0,1fr)] items-center gap-x-3", @class]}>
      <span class="flex size-7 shrink-0 items-center justify-center rounded-full bg-orangeText text-sm font-semibold text-white">{@number}</span>
      <div class="text-sm font-semibold text-grey-900">{render_slot(@title)}</div>
      <div :for={content <- @content} class={["col-start-2 text-sm text-grey-600", @content_class]}>
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
      class="w-full focus-visible:outline-2 focus-visible:outline-orange-700 active:opacity-80"
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
        "mbs-4 flex items-start gap-2 rounded-lg border px-3 py-2.5 text-sm",
        if(@status == :failed,
          do: "border-red-200 bg-red-100 text-red-900",
          else: "border-grey-200 bg-grey-50 text-grey-700"
        )
      ]}
    >
      <.icon
        :if={@status == :failed}
        name="hero-x-circle-solid"
        class="mbs-0.5 size-5 shrink-0 text-red-700"
      />
      <.icon
        :if={@status != :failed}
        name="hero-arrow-path"
        class="mbs-0.5 size-5 shrink-0 motion-safe:animate-spin"
      />
      <span>{failure_message(@failure) || present_ksef_auth_status(@status)}</span>
    </div>
    """
  end

  defp present_upload_error(:too_large), do: "Plik jest za duży."
  defp present_upload_error(:too_many_files), do: "Wybierz dokładnie dwa pliki."
  defp present_upload_error(:not_accepted), do: "Dozwolone są tylko pliki .crt i .key."

  defp failure_message(nil), do: nil
  defp failure_message(%{reason: reason}), do: credential_failure_message(reason)

  defp credential_failure_message(:certificate_limit_exhausted), do: "Osiągnięto limit certyfikatów KSeF."

  defp credential_failure_message(:invalid_credentials) do
    "Nie udało się uwierzytelnić w KSeF. Sprawdź certyfikat, klucz oraz hasło i spróbuj ponownie."
  end

  defp credential_failure_message(:authentication_failed), do: "Uwierzytelnienie w KSeF nie powiodło się."

  defp credential_failure_message(_reason), do: "Wystąpił błąd podczas generowania certyfikatu KSeF."

  defp present_ksef_auth_status(:authenticating), do: "Trwa uwierzytelnianie w KSeF."
  defp present_ksef_auth_status(:authenticating_epuap), do: "Trwa uwierzytelnianie w KSeF."

  defp present_ksef_auth_status(:preparing_enrollment), do: "Trwa przygotowanie wniosku o certyfikat."

  defp present_ksef_auth_status(:wait_for_certificate), do: "KSeF wystawia certyfikat."
  defp present_ksef_auth_status(:failed), do: "Nie udało się połączyć z KSeF. Spróbuj ponownie."
end
