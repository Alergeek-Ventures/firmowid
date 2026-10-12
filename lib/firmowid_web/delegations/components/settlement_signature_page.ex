defmodule FirmowidWeb.Delegations.Components.SettlementSignaturePage do
  @moduledoc "Employee signature and submission step for a prepared delegation settlement."

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Delegations.Components.Delegation
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Delegations.Utilities.DelegationPresentation
  alias FirmowidWeb.Delegations.Utilities.Navigation
  alias FirmowidWeb.Delegations.Utilities.SettlementDocument

  @profile_signature_url "https://podpis.gov.pl/podpisz-dokument-elektronicznie/"

  @doc "Renders the responsive signature, upload, preview, and submission screen."
  @spec settlement_signature_page(map()) :: Phoenix.LiveView.Rendered.t()
  def settlement_signature_page(assigns) do
    assigns =
      assigns
      |> assign(:pdf_filename, SettlementDocument.filename(assigns.delegation))
      |> assign(:pdf_url, Navigation.settlement_download_path(assigns.delegation.reference))
      |> assign(:profile_signature_url, @profile_signature_url)
      |> assign(:entry, List.first(assigns.uploads.signed_settlement.entries))

    ~H"""
    <main class="mx-auto w-full max-w-280 px-4 py-8 sm:px-6">
      <.back navigate={~p"/ustawienia/profil"} />
      <header class="mt-8">
        <div class="flex flex-col justify-between gap-4 lg:flex-row lg:items-start">
          <div>
            <small class="text-grey-500">Cel: <span class="text-grey-700">{@delegation.purpose}</span></small>
            <h1 class="mt-1 text-2xl font-medium">Rozliczenie delegacji</h1>
          </div>
          <dl class="flex flex-wrap gap-4 text-sm text-grey-500">
            <div>
              <dt class="inline">Termin:</dt>

              <dd class="inline text-grey-700">
                <.date_range start_date={@delegation.start_date} end_date={@delegation.end_date} />
              </dd>
            </div>
            <div>
              <dt class="inline">Zaliczka:</dt>

              <dd class="inline text-grey-700">{Money.to_string!(@delegation.advance_amount)}</dd>
            </div>
          </dl>
        </div>
        <p class="mt-4 max-w-2xl text-grey-700">
          Sprawdź wygenerowany dokument. Podpisz go Profilem Zaufanym, wgraj podpisany plik i wyślij rozliczenie do pracodawcy.
        </p>
      </header>

      <div class="mt-10 grid min-w-0 items-start gap-10 lg:grid-cols-[minmax(0,680px)_minmax(0,400px)]">
        <section class="min-w-0 rounded-lg bg-grey-200 p-4 sm:p-6" aria-label="Podgląd rozliczenia">
          <div class="mb-4 flex flex-wrap items-center gap-2 text-sm">
            <strong class="truncate">{@pdf_filename}</strong><span class="text-grey-500">· 2 strony</span>
          </div>
          <div
            id="settlement-pdf-preview"
            phx-hook="PDFViewer"
            data-pdf-url={@pdf_url}
            class="space-y-4 [&_canvas]:block [&_canvas]:h-auto! [&_canvas]:max-w-full [&_canvas]:bg-white [&_canvas]:shadow-sm"
          />
        </section>

        <aside class="min-w-0 space-y-6 lg:sticky lg:top-6">
          <form
            id="signed-settlement-form"
            phx-change="validate-signed-settlement"
            phx-submit="submit-for-review"
          >
            <section class="rounded-lg border border-grey-200 bg-grey-50 p-6">
              <h2 class="font-medium text-turquoise-700">Podpisz i wyślij</h2>
              <ol class="mt-5 list-decimal space-y-4 pl-5 text-sm text-grey-700">
                <li>
                  <span>Pobierz dokument</span>
                  <.link
                    kind="unstyled"
                    redirect={@pdf_url}
                    download
                    class="mt-2 flex max-w-full items-center gap-2 rounded-md border border-grey-200 px-2 py-1.5 font-medium text-grey-900"
                  >
                    <Lucideicons.file_down class="size-4 shrink-0" /><span class="truncate">{@pdf_filename}</span>
                  </.link>
                </li>
                <li>
                  Podpisz dokument
                  <.link
                    kind="unstyled"
                    external={@profile_signature_url}
                    class="inline-flex items-center gap-1 font-medium text-turquoise-700"
                  >
                    Profilem Zaufanym <Lucideicons.external_link class="size-4" />
                  </.link>
                </li>
                <li>Wgraj podpisane rozliczenie delegacji.</li>
              </ol>

              <div :if={is_nil(@entry)} class="mt-5">
                <label
                  for={@uploads.signed_settlement.ref}
                  phx-drop-target={@uploads.signed_settlement.ref}
                  class="flex cursor-pointer flex-wrap items-center justify-between gap-3 rounded-lg border border-dashed border-grey-200 bg-grey-100 px-4 py-6 text-sm text-grey-700 transition-colors hover:border-turquoise-500"
                >
                  <span>Przeciągnij lub wybierz plik.</span>
                  <span class="rounded-md bg-grey-200 px-2 py-1.5 font-medium text-grey-900">Wybierz plik</span>
                </label>
              </div>

              <.live_file_input upload={@uploads.signed_settlement} class="sr-only" />

              <div :if={@entry} class="mt-5">
                <div class="flex items-center gap-3 rounded-lg bg-turquoise-100 px-4 py-3 text-sm text-turquoise-700">
                  <Lucideicons.file_text class="size-4 shrink-0" />
                  <span class="min-w-0 flex-1 truncate" title={@entry.client_name}>{@entry.client_name}</span>
                  <span :if={!@entry.done?} class="text-xs">{@entry.progress}%</span>
                  <.button
                    type="button"
                    variant="unstyled"
                    phx-click="cancel-signed-settlement"
                    phx-value-ref={@entry.ref}
                    aria-label={"Usuń #{@entry.client_name}"}
                    class="rounded p-1 hover:bg-turquoise-200"
                  >
                    <Lucideicons.x class="size-4" />
                  </.button>
                </div>
                <progress
                  :if={!@entry.done?}
                  value={@entry.progress}
                  max="100"
                  class="mt-2 h-1 w-full"
                >{@entry.progress}%</progress>
              </div>

              <p
                :for={error <- upload_errors(@uploads.signed_settlement)}
                class="mt-2 text-sm text-red-600"
              >
                {upload_error(error)}
              </p>
              <p
                :for={
                  error <- if(@entry, do: upload_errors(@uploads.signed_settlement, @entry), else: [])
                }
                class="mt-2 text-sm text-red-600"
              >
                {upload_error(error)}
              </p>
            </section>

            <.summary document={@document} />

            <div class="mt-6 grid grid-cols-2 gap-4">
              <.button
                type="button"
                variant="secondary"
                size="big"
                phx-click="edit-settlement"
              >Edytuj dokument</.button>
              <.button
                type="submit"
                variant="primary"
                accent="turquoise"
                size="big"
                disabled={is_nil(@entry) or !@entry.done? or @submitting?}
                phx-disable-with="Wysyłanie..."
              >Wyślij</.button>
            </div>
          </form>
        </aside>
      </div>
    </main>
    """
  end

  attr :document, :map, required: true

  defp summary(assigns) do
    ~H"""
    <section class="mt-6 rounded-lg bg-white p-5 shadow-sm">
      <h2 class="text-grey-500">Podsumowanie</h2>
      <dl class="mt-6 space-y-3 text-sm">
        <.row label="Przejazdy" value={@document.transport_total} />
        <.row label="Nocleg" value={@document.accommodation_total} />
        <.row label="Inne" value={@document.other_total} />
        <div class="my-5 space-y-3 border-y border-grey-100 py-5">
          <.row label="Razem koszty" value={@document.total} strong />
          <.row label="Pobrana zaliczka" value={@document.delegation.advance_amount} />
        </div>
        <.row label={@document.balance_label} value={@document.balance} strong />
      </dl>
      <p class="mt-5 text-xs text-grey-500">
        Razem z rozliczeniem wyślemy {length(@document.attachments)} {attachment_label(
          length(@document.attachments)
        )} ({attachment_categories(@document.attachments)}).
      </p>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, Money, required: true
  attr :strong, :boolean, default: false

  defp row(assigns) do
    ~H"""
    <div class={["flex justify-between gap-4", @strong && "font-medium"]}>
      <dt>{@label}</dt><dd>{DelegationPresentation.format_money(@value)}</dd>
    </div>
    """
  end

  defp upload_error(:not_accepted), do: "Wybierz plik PDF."
  defp upload_error(:too_large), do: "Plik może mieć maksymalnie 10 MB."
  defp upload_error(:too_many_files), do: "Możesz wgrać tylko jeden plik."
  defp upload_error(_error), do: "Nie udało się wgrać pliku."

  defp attachment_label(1), do: "załącznik"
  defp attachment_label(count) when count in 2..4, do: "załączniki"
  defp attachment_label(_count), do: "załączników"

  defp attachment_categories([]), do: "brak dodatkowych dokumentów"

  defp attachment_categories(attachments) do
    attachments
    |> Enum.map(&category/1)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp category(%{original_filename: filename}) do
    filename = String.downcase(filename || "")

    cond do
      String.contains?(filename, "bilet") -> "bilety"
      String.contains?(filename, "wyci") -> "wyciąg"
      String.contains?(filename, "polis") -> "polisa"
      true -> "faktury i rachunki"
    end
  end
end
