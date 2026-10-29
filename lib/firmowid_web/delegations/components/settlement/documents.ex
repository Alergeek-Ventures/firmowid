defmodule FirmowidWeb.Delegations.Components.Settlement.Documents do
  @moduledoc "Document controls and guidance for delegation settlement expenses."

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.LiveView.Rendered

  @doc "Renders the supporting documents attached to an expense."
  @spec related_documents(map()) :: Rendered.t()
  attr :expense, :any, required: true
  attr :editable?, :boolean, required: true

  def related_documents(assigns) do
    ~H"""
    <div class="mt-4 flex flex-wrap items-center gap-2 text-sm">
      <span class="font-medium text-grey-700">{gettext("Related documents:")}</span>
      <div class="flex flex-wrap gap-2">
        <span :for={blob <- @expense.related_blobs}>
          <.document_pill filename={blob.original_filename} url={blob.url}>
            <:action :if={@editable?}>
              <.button
                type="button"
                variant="unstyled"
                class="cursor-pointer text-grey-500"
                phx-click="remove-related-document"
                phx-value-expense-id={@expense.id}
                phx-value-blob-id={blob.id}
                aria-label={gettext("Remove %{name}", name: blob.original_filename)}
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
        {@icon}{gettext("%{title} - which documents should I attach?", title: @title)}
      </h2>
      <div id={"#{@id}-description"} class="mt-5 flex flex-col gap-2 text-sm text-black">
        <%= case @kind do %>
          <% "transport" -> %>
            <.modal_paragraph heading={pgettext("transport documents", "Do you have an invoice?")}>
              <.emphasized_text text={
                gettext(
                  "If you have an *invoice* for a ticket or a journey, add it as the main settlement document."
                )
              } />
            </.modal_paragraph>
            <.modal_paragraph heading={gettext("Don't have an invoice?")}>
              <.emphasized_text text={
                gettext(
                  "Attach a *ticket*, e.g. a train, bus, plane or public transport ticket used during the business trip."
                )
              } />
            </.modal_paragraph>
            <.modal_paragraph heading={gettext("Have neither an invoice nor a ticket?")}>
              <.emphasized_text text={
                gettext(
                  "Attach a *booking* or a *booking confirmation*. The document should show what the expense was for: the route, date, carrier or service. In this case, also attach a *payment confirmation*."
                )
              } />
            </.modal_paragraph>
            <hr class="my-2 w-full border-grey-200" />
            <p>
              <span class="font-medium">{gettext("Note:")}</span>
              {gettext(
                "A payment confirmation alone is not enough. If you attach a transfer or card payment confirmation, add a document showing what the payment was for, e.g. a booking."
              )}
            </p>
          <% "accommodation" -> %>
            <.modal_paragraph heading={pgettext("accommodation documents", "Do you have an invoice?")}>
              <.emphasized_text text={
                gettext(
                  "If you have an *invoice* for accommodation, add it as the main settlement document."
                )
              } />
            </.modal_paragraph>
            <.modal_paragraph heading={gettext("Don't have an invoice?")}>
              <.emphasized_text text={
                gettext(
                  "Attach an *accommodation booking* and a *payment confirmation*. This applies, for example, when the accommodation was booked through Booking or a similar service and the property did not issue an invoice. In that case, add the booking document and proof that the accommodation was paid for."
                )
              } />
            </.modal_paragraph>
            <.modal_paragraph heading={gettext("Don't have any document?")}>
              <.emphasized_text text={
                gettext(
                  "You can choose a *flat rate* for accommodation. In that case, you must still have other confirmation that the business trip actually took place, e.g. transport tickets or another document related to the trip. The completed \"Journeys\" section is enough for that."
                )
              } />
            </.modal_paragraph>
          <% "other" -> %>
            <p>
              {gettext(
                "Other expenses should have a document showing what the cost was for. It is best to attach an invoice, receipt, ticket, booking, policy or another document confirming the service or purchase. If you only have a payment confirmation, also add a document describing what was paid for."
              )}
            </p>
            <p>
              {gettext(
                "The expense must be related to the business trip. For example, insurance can be settled when it covers the business trip."
              )}
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
        "inline-flex max-w-full items-center gap-1 rounded bg-grey-200 px-2 py-1 text-sm font-medium text-grey-600",
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

  attr :text, :string, required: true

  # Renders a translated sentence, emphasising the parts wrapped in asterisks.
  defp emphasized_text(assigns) do
    assigns = assign(assigns, :parts, assigns.text |> String.split("*") |> Enum.with_index())

    ~H"""
    <%= for {part, index} <- @parts do %>
      <%= if rem(index, 2) == 1 do %>
        <.document_emphasis>{part}</.document_emphasis>
      <% else %>
        {part}
      <% end %>
    <% end %>
    """
  end

  slot :inner_block, required: true

  defp document_emphasis(assigns) do
    ~H"""
    <span class="font-medium text-teal-700 underline">{render_slot(@inner_block)}</span>
    """
  end
end
