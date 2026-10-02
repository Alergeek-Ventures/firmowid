defmodule FirmowidWeb.Delegations.Components.Settlement.Documents do
  @moduledoc "Document controls and guidance for delegation settlement expenses."

  use FirmowidWeb, :html

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.LiveView.Rendered

  @doc "Renders the supporting documents attached to an expense."
  @spec related_documents(map()) :: Rendered.t()
  attr :expense, :any, required: true
  attr :editable?, :boolean, required: true

  def related_documents(assigns) do
    ~H"""
    <div class="mt-4 flex flex-wrap items-center gap-2 text-sm">
      <span class="text-grey-700 font-medium">Powiązane dokumenty:</span>
      <div class="flex flex-wrap gap-2">
        <span :for={blob <- @expense.related_blobs}>
          <.document_pill filename={blob.original_filename} url={blob.url}>
            <:action :if={@editable?}>
              <.button
                type="button"
                variant="unstyled"
                class="text-grey-500 cursor-pointer"
                phx-click="remove-related-document"
                phx-value-expense-id={@expense.id}
                phx-value-blob-id={blob.id}
                aria-label={"Usuń #{blob.original_filename}"}
              ><Lucideicons.x class="size-3" /></.button>
            </:action>
          </.document_pill>
        </span>
      </div>
    </div>
    """
  end

  @doc "Renders guidance on evidence documents for an expense category."
  @spec documents_modal(map()) :: Rendered.t()
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :icon, :any, required: true
  attr :kind, :string, required: true

  def documents_modal(assigns) do
    ~H"""
    <.modal id={@id} on_cancel={hide_modal(@id)} class="max-w-[600px]">
      <h2 id={"#{@id}-title"} class="flex items-center gap-2 text-base font-medium text-black">
        {@icon}{@title} - jakie dokumenty załączyć?
      </h2>
      <div id={"#{@id}-description"} class="mt-5 flex flex-col gap-2 text-sm text-black">
        <%= case @kind do %>
          <% "transport" -> %>
            <.modal_paragraph heading="Masz Fakturę?">
              Jeśli masz
              <.document_emphasis>fakturę</.document_emphasis>
              za bilet lub przejazd, dodaj ją jako podstawowy dokument rozliczeniowy.
            </.modal_paragraph>
            <.modal_paragraph heading="Nie masz faktury?">
              Załącz
              <.document_emphasis>bilet</.document_emphasis>
              np. bilet kolejowy, autobusowy, lotniczy lub bilet komunikacji miejskiej wykorzystany w trakcie delegacji.
            </.modal_paragraph>
            <.modal_paragraph heading="Nie masz ani faktury, ani biletu?">
              Załącz
              <.document_emphasis>rezerwację</.document_emphasis>
              lub <.document_emphasis>potwierdzenie rezerwacji</.document_emphasis>. Dokument powinien pokazywać, czego dotyczył wydatek: trasę, datę, przewoźnika lub usługę. W tym przypadku załącz także <.document_emphasis>potwierdzenie płatności</.document_emphasis>.
            </.modal_paragraph>
            <hr class="border-grey-200 my-2 w-full" />
            <p>
              <span class="font-medium">Uwaga:</span>
              Samo potwierdzenie płatności nie wystarczy. Jeśli załączasz potwierdzenie przelewu lub płatności kartą, dodaj do niego dokument potwierdzający, za co była płatność, np. rezerwację.
            </p>
          <% "accommodation" -> %>
            <.modal_paragraph heading="Masz fakturę?">
              Jeśli masz
              <.document_emphasis>fakturę</.document_emphasis>
              za nocleg, dodaj ją jako podstawowy dokument rozliczeniowy.
            </.modal_paragraph>
            <.modal_paragraph heading="Nie masz faktury?">
              Załącz
              <.document_emphasis>rezerwację noclegu</.document_emphasis>
              oraz <.document_emphasis>potwierdzenie zapłaty</.document_emphasis>. Dotyczy to np. sytuacji, gdy nocleg był rezerwowany przez Booking lub podobny serwis i obiekt nie wystawił faktury. Wtedy do rozliczenia dodaj dokument rezerwacji oraz dowód, że nocleg został opłacony.
            </.modal_paragraph>
            <.modal_paragraph heading="Nie masz żadnego dokumentu?">
              Możesz wybrać
              <.document_emphasis>ryczałt</.document_emphasis>
              za nocleg. W takiej sytuacji musisz jednak mieć inne potwierdzenie, że delegacja faktycznie się odbyła, np. bilety transportowe lub inny dokument związany z wyjazdem. Do tego wystarczy ci wypełniona sekcja "Przejazdy".
            </.modal_paragraph>
          <% "other" -> %>
            <p>
              Inne wydatki powinny mieć dokument pokazujący, czego dotyczył koszt. Najlepiej załączyć fakturę, rachunek, bilet, rezerwację, polisę albo inny dokument potwierdzający usługę lub zakup. Jeśli masz tylko potwierdzenie płatności, dodaj też dokument opisujący, za co zapłacono.
            </p>
            <p>
              Wydatek musi być związany z delegacją. Przykładowo ubezpieczenie można rozliczyć wtedy, gdy pokrywa się z podróżą służbową.
            </p>
        <% end %>
      </div>
    </.modal>
    """
  end

  @doc "Renders a document pill with an optional action."
  @spec document_pill(map()) :: Rendered.t()
  attr :filename, :string, required: true
  attr :url, :string, default: nil
  attr :loading?, :boolean, default: false
  slot :action

  def document_pill(assigns) do
    ~H"""
    <span
      aria-busy={@loading?}
      class={[
        "bg-grey-200 text-grey-600 inline-flex max-w-full items-center gap-1 rounded px-2 py-1 text-sm font-medium",
        @loading? && "animate-pulse"
      ]}
    >
      <.link
        :if={@url}
        kind="unstyled"
        external={@url}
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex min-w-0 items-center gap-1"
      ><Lucideicons.file class="size-4 shrink-0" /><span
        class="max-w-[220px] truncate"
        title={@filename}
      >{@filename}</span></.link>
      <span :if={!@url} class="inline-flex min-w-0 items-center gap-1">
        <Lucideicons.file class="size-4 shrink-0" />
        <span class="max-w-[220px] truncate" title={@filename}>{@filename}</span>
      </span>
      {render_slot(@action)}
    </span>
    """
  end

  attr :heading, :string, required: true
  slot :inner_block, required: true

  defp modal_paragraph(assigns) do
    ~H"""
    <div>
      <h3 class="font-medium">{@heading}</h3><p>{render_slot(@inner_block)}</p>
    </div>
    """
  end

  slot :inner_block, required: true

  defp document_emphasis(assigns) do
    ~H"""
    <span class="text-turquoise-700 font-medium underline">{render_slot(@inner_block)}</span>
    """
  end
end
