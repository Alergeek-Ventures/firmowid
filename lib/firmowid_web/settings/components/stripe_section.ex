defmodule FirmowidWeb.Settings.Components.StripeSection do
  @moduledoc """
  The "Stripe" settings page of an admin (see `Firmowid.Invoicing.StripeConnection`).

  A company connected to KSeF connects its Stripe account with a restricted key that only
  reads. Every successful Stripe payment after the connection becomes an invoice issued as paid
  and sent to KSeF; one payment gives one invoice, and payments from before the connection get
  none. The company chooses whether buyers without a tax ID get an invoice too; the choice
  applies to the next payments only. The latest payments are listed with their invoices.
  """
  use FirmowidWeb, :live_component

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Settings.Components.Integrations, only: [integration_step: 1]
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.StripeConnection.Changes.VerifyKey
  alias Firmowid.Ksef
  alias FirmowidWeb.Settings.Utilities.Navigation

  @timezone "Europe/Warsaw"

  @impl true
  def mount(socket), do: {:ok, assign(socket, key: "", error: nil)}

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign_connection()}
  end

  @impl true
  def handle_event("validate", %{"key" => key}, socket), do: {:noreply, assign(socket, key: key, error: nil)}

  def handle_event("connect", %{"key" => key}, socket) do
    case Invoicing.connect_stripe(key, scope: socket.assigns.scope) do
      {:ok, _connection} ->
        LiveToast.send_toast(:success, gettext("Stripe is connected."))
        {:noreply, socket |> assign(key: "", error: nil) |> assign_connection()}

      {:error, error} ->
        {:noreply, assign(socket, key: key, error: error_message(error))}
    end
  end

  def handle_event("consumers", %{"consumers" => value}, socket) when value in ["invoice", "skip"] do
    {:ok, _connection} =
      Invoicing.set_stripe_invoice_consumers(
        socket.assigns.connection,
        value == "invoice",
        scope: socket.assigns.scope
      )

    {:noreply, assign_connection(socket)}
  end

  def handle_event("disconnect", _params, socket) do
    :ok = Invoicing.disconnect_stripe(socket.assigns.connection, scope: socket.assigns.scope)
    LiveToast.send_toast(:success, gettext("Stripe is disconnected."))
    {:noreply, assign_connection(socket)}
  end

  defp assign_connection(socket) do
    scope = socket.assigns.scope
    connection = Invoicing.get_stripe_connection!(scope: scope)

    payments =
      if connection,
        do:
          Invoicing.list_stripe_payments!(
            scope: scope,
            load: [sales_invoice: [:ksef_submission_status]]
          ).results,
        else: []

    assign(socket,
      connection: connection,
      payments: payments,
      ksef_connected?: Ksef.connected?(scope)
    )
  end

  # The key's own problem (a key that is not restricted, unknown to Stripe or without a
  # permission) or a missing KSeF connection, in the user's language.
  defp error_message(%Ash.Error.Invalid{errors: errors}) do
    Enum.find_value(errors, gettext("Could not connect Stripe. Try again."), fn
      %{field: field, message: message, vars: vars} when field in [:api_key, :base] ->
        translate_error({message, vars})

      _other ->
        nil
    end)
  end

  defp error_message(_error), do: gettext("Could not connect Stripe. Try again.")

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :permissions, VerifyKey.permissions())

    ~H"""
    <section id={@id} class="grid items-start gap-x-12 gap-y-10 lg:grid-cols-[minmax(0,1fr)_22rem]">
      <%= cond do %>
        <% @connection -> %>
          <.connected connection={@connection} payments={@payments} myself={@myself} />
        <% @ksef_connected? -> %>
          <.key_flow key={@key} error={@error} permissions={@permissions} myself={@myself} />
          <.payment_flow />
        <% true -> %>
          <div class="flex max-w-xl flex-col gap-4">
            <p class="text-sm/snug text-grey-700">
              {gettext(
                "Invoices of Stripe payments go to KSeF, so connect the company to KSeF before Stripe."
              )}
            </p>
            <div>
              <.link
                kind="button"
                variant="special"
                size="small"
                navigate={Navigation.canonical_path(:ksef)}
              >
                {gettext("Connect to KSeF")}
              </.link>
            </div>
          </div>
          <.payment_flow />
      <% end %>
    </section>
    """
  end

  attr :connection, :map, required: true
  attr :payments, :list, required: true
  attr :myself, :any, required: true

  defp connected(assigns) do
    ~H"""
    <div class="flex max-w-xl flex-col gap-8">
      <div class="flex flex-col gap-2">
        <.status_row label={gettext("Status")}>
          <.badge tone="success">
            <.figma_icon name="circle_check" />{gettext("Connected to Stripe")}
          </.badge>
        </.status_row>
        <.status_row label={gettext("Invoiced since")}>
          {local_time(@connection.inserted_at, "%d.%m.%Y, %H:%M")}
        </.status_row>
        <.status_row class="mbs-2">
          <.button
            size="small"
            type="button"
            variant="destructive"
            {%{popovertarget: "confirm_disconnect_stripe"}}
          >
            {gettext("Disconnect")}
          </.button>
        </.status_row>
      </div>

      <p class="text-sm/snug text-grey-700">
        {gettext(
          "Every successful payment since the connection becomes an invoice issued as paid and sent to KSeF: paid Stripe invoices, Checkout payments and other payments. One payment gives one invoice."
        )}
      </p>

      <form
        id="stripe-consumers"
        phx-change="consumers"
        phx-target={@myself}
        class="flex flex-col gap-3"
      >
        <fieldset class="flex flex-col gap-3">
          <legend class="mbe-3 text-h5 font-medium text-grey-900">
            {gettext("Buyers without a tax ID")}
          </legend>
          <.consumers_option
            value="invoice"
            checked={@connection.invoice_consumers}
            label={gettext("Issue an invoice")}
            description={
              gettext("A private person gets an invoice without a tax ID, like any other buyer")
            }
          />
          <.consumers_option
            value="skip"
            checked={not @connection.invoice_consumers}
            label={gettext("Do not issue an invoice")}
            description={gettext("Only buyers who gave a tax ID in Stripe get an invoice")}
          />
        </fieldset>
        <p class="text-sm/snug text-grey-600">
          {gettext("The change applies to the next payments. Issued invoices stay as they are.")}
        </p>
      </form>
    </div>

    <div class="flex flex-col gap-3 lg:border-l lg:border-grey-200 lg:ps-12">
      <h2 class="text-h5 font-medium text-grey-900">{gettext("Latest payments")}</h2>
      <p :if={@payments == []} class="text-sm/snug text-grey-600">
        {gettext("No payments since the connection yet. Each new one appears here with its invoice.")}
      </p>
      <ul
        :if={@payments != []}
        id="stripe-payments"
        class="flex flex-col divide-y divide-grey-200 border-y border-grey-200"
      >
        <li
          :for={payment <- @payments}
          id={"stripe-payment-#{payment.id}"}
          class="flex flex-col gap-1 py-3"
        >
          <span class="flex items-baseline justify-between gap-4 text-sm">
            <span class="min-w-0 truncate text-grey-900">{buyer(payment)}</span>
            <span class="shrink-0 text-grey-900 tabular-nums">
              {payment.currency |> Money.new(payment.amount) |> Money.to_string!()}
            </span>
          </span>
          <span class="text-xs text-grey-600">
            <span class="tabular-nums">
              {local_time(payment.paid_at, "%d.%m, %H:%M")}
            </span>
            · <.payment_outcome payment={payment} />
          </span>
        </li>
      </ul>
    </div>

    <div
      id="confirm_disconnect_stripe"
      popover
      role="alertdialog"
      aria-labelledby="confirm_disconnect_stripe_title"
      class="m-auto w-[min(90vi,32rem)] rounded-lg border border-grey-200 bg-white p-6 shadow-lg"
    >
      <h3 id="confirm_disconnect_stripe_title" class="text-lg font-semibold text-grey-900">
        {gettext("Disconnect Stripe?")}
      </h3>
      <p class="mbs-3 text-sm text-grey-700">
        {gettext("Payments after this will not get invoices. Issued invoices stay.")}
      </p>
      <div class="mbs-6 flex flex-wrap justify-end gap-3">
        <.button
          type="button"
          variant="tertiary"
          size="small"
          {%{popovertarget: "confirm_disconnect_stripe", popovertargetaction: "hide"}}
        >
          {gettext("Cancel")}
        </.button>
        <.button
          type="button"
          variant="destructive"
          size="small"
          phx-click="disconnect"
          phx-target={@myself}
          {%{popovertarget: "confirm_disconnect_stripe", popovertargetaction: "hide"}}
        >
          {gettext("Disconnect")}
        </.button>
      </div>
    </div>
    """
  end

  defp local_time(datetime, format), do: datetime |> DateTime.shift_zone!(@timezone) |> Calendar.strftime(format)

  defp buyer(%{sales_invoice: %{buyer_display_name: name}}) when is_binary(name), do: name
  defp buyer(payment), do: payment.payment_intent_id

  attr :payment, :map, required: true

  defp payment_outcome(%{payment: %{status: :invoiced}} = assigns) do
    ~H"""
    <.link
      kind="unstyled"
      navigate={~p"/sprzedazowe/#{@payment.sales_invoice.id}"}
      class="inline-flex text-grey-900 underline underline-offset-2"
    >
      {gettext("Invoice %{number}", number: @payment.sales_invoice.invoice_number)}
    </.link>
    ·
    <span class={[@payment.sales_invoice.ksef_submission_status == :failed && "text-brick-700"]}>
      {ksef_status(@payment.sales_invoice.ksef_submission_status)}
    </span>
    """
  end

  defp payment_outcome(%{payment: %{status: :pending}} = assigns) do
    ~H"""
    {gettext("issuing the invoice")}
    """
  end

  defp payment_outcome(%{payment: %{status: :skipped}} = assigns) do
    ~H"""
    {gettext("no invoice: the buyer gave no tax ID")}
    """
  end

  defp payment_outcome(%{payment: %{status: :untaxed}} = assigns) do
    ~H"""
    <span class="text-brick-700">
      {gettext("no invoice: Stripe charged no VAT, set the tax in Stripe and issue it by hand")}
    </span>
    """
  end

  defp payment_outcome(%{payment: %{status: :failed}} = assigns) do
    ~H"""
    <span class="text-brick-700" title={@payment.error}>
      {gettext("the invoice could not be issued, issue it by hand")}
    </span>
    """
  end

  defp ksef_status(:not_submitted), do: gettext("waiting for KSeF")
  defp ksef_status(:submitting), do: gettext("sent to KSeF")
  defp ksef_status(:submitted), do: gettext("accepted by KSeF")
  defp ksef_status(:failed), do: gettext("rejected by KSeF, fix the invoice")

  attr :key, :string, required: true
  attr :error, :string, default: nil
  attr :permissions, :list, required: true
  attr :myself, :any, required: true

  defp key_flow(assigns) do
    ~H"""
    <div class="flex max-w-xl flex-col gap-8">
      <p class="text-sm/snug text-grey-700">
        {gettext(
          "Connect Stripe and every successful payment from then on becomes an invoice issued as paid and sent to KSeF. Payments made before the connection get no invoices."
        )}
      </p>

      <ol id="stripe-key-flow" class="space-y-6">
        <.integration_step number={1}>
          <:title>{gettext("Create a restricted key in Stripe")}</:title>
          <:content>
            <p>
              <.stripe_keys_sentence text={
                gettext("Open __LINK__ and create a restricted key that can only read:")
              } />
            </p>
            <p class="mbs-2 text-grey-900">{Enum.join(@permissions, ", ")}</p>
          </:content>
        </.integration_step>

        <.integration_step number={2} content_class="mbs-3">
          <:title><label for="stripe-key">{gettext("Paste the key")}</label></:title>
          <:content>
            <form
              id="stripe-key-form"
              phx-change="validate"
              phx-submit="connect"
              phx-target={@myself}
              class="space-y-4"
            >
              <.input
                type="password"
                id="stripe-key"
                name="key"
                value={@key}
                placeholder="rk_live_…"
                autocomplete="off"
                input_class="w-full"
                errors={if(@error, do: [""], else: [])}
                show_error={false}
              />
              <p :if={@error} id="stripe-key-error" class="text-sm text-brick-700">{@error}</p>
              <div class="flex justify-end">
                <.button
                  type="submit"
                  variant="special"
                  size="small"
                  phx-disable-with={gettext("Checking the key…")}
                >
                  {gettext("Connect to Stripe")}
                </.button>
              </div>
            </form>
          </:content>
        </.integration_step>
      </ol>

      <p class="text-sm/snug text-grey-600">
        {gettext("Soon you will connect Stripe with one click, without creating a key.")}
      </p>
    </div>
    """
  end

  # The way of one payment, with made-up data: from Stripe to an invoice and on to KSeF.
  defp payment_flow(assigns) do
    ~H"""
    <aside
      id="stripe-payment-flow"
      class="flex flex-col gap-5 lg:border-l lg:border-grey-200 lg:ps-12"
    >
      <h2 class="text-h5 font-medium text-grey-900">{gettext("What happens to a payment")}</h2>
      <ol class="flex flex-col">
        <.flow_step title={gettext("The customer pays in Stripe")}>
          <:icon>
            <span class="grid size-8 place-items-center rounded-md bg-[#635bff] p-1.5 text-white">
              <svg viewBox="0 0 24 24" fill="currentColor" class="size-full" aria-hidden="true">
                <path d="M13.976 9.15c-2.172-.806-3.356-1.426-3.356-2.409 0-.831.683-1.305 1.901-1.305 2.227 0 4.515.858 6.09 1.631l.89-5.494C18.252.975 15.697 0 12.165 0 9.667 0 7.589.654 6.104 1.872 4.56 3.147 3.757 4.992 3.757 7.218c0 4.039 2.467 5.76 6.476 7.219 2.585.92 3.445 1.574 3.445 2.583 0 .98-.84 1.545-2.354 1.545-1.875 0-4.965-.921-6.99-2.109l-.9 5.555C5.175 22.99 8.385 24 11.714 24c2.641 0 4.843-.624 6.328-1.813 1.664-1.305 2.525-3.236 2.525-5.732 0-4.128-2.524-5.851-6.594-7.305h.003z" />
              </svg>
            </span>
          </:icon>
          <span class="flex justify-between gap-3">
            <span>Acme Sp. z o.o.</span><span class="text-grey-900 tabular-nums">123,00 zł</span>
          </span>
        </.flow_step>
        <.flow_step title={gettext("Firmowid issues the invoice")}>
          <:icon>
            <span class="grid size-8 place-items-center rounded-md bg-teal-200 text-teal-900">
              <.figma_icon name="faktury" class="size-4.5" />
            </span>
          </:icon>
          <span class="flex items-center justify-between gap-3">
            <span class="tabular-nums">{gettext("Invoice %{number}", number: "19/11/2026")}</span>
            <.badge tone="sales">{pgettext("issued invoice", "Paid")}</.badge>
          </span>
        </.flow_step>
        <.flow_step title={gettext("The invoice goes to KSeF")} last>
          <:icon>
            <span class="grid size-8 place-items-center rounded-md bg-moss-200 text-moss-900">
              <.figma_icon name="check" class="size-4.5" />
            </span>
          </:icon>
          <.badge tone="success">{gettext("Accepted by KSeF")}</.badge>
        </.flow_step>
      </ol>
    </aside>
    """
  end

  attr :title, :string, required: true
  attr :last, :boolean, default: false
  slot :icon, required: true
  slot :inner_block, required: true

  defp flow_step(assigns) do
    ~H"""
    <li class={["relative grid grid-cols-[2rem_minmax(0,1fr)] gap-x-3", !@last && "pbe-6"]}>
      <span :if={!@last} class="absolute top-9 bottom-1 left-4 w-px bg-grey-200" aria-hidden="true"></span>
      {render_slot(@icon)}
      <span class="flex flex-col gap-1.5 pbs-1">
        <span class="text-sm font-medium text-grey-900">{@title}</span>
        <span class="text-sm text-grey-700">{render_slot(@inner_block)}</span>
      </span>
    </li>
    """
  end

  attr :label, :string, default: ""
  attr :class, :string, default: nil
  slot :inner_block, required: true

  # A label and its value, like the status rows of the KSeF connection: the value moves under
  # its label on a narrow screen.
  defp status_row(assigns) do
    ~H"""
    <div class={["flex flex-wrap items-baseline gap-x-5", @class]}>
      <div class="grow basis-40 text-sm/snug text-grey-700">{@label}</div>
      <div class="grow-999 basis-0 text-base/snug wrap-break-word text-grey-900 min-inline-1/2">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :value, :string, required: true
  attr :checked, :boolean, required: true
  attr :label, :string, required: true
  attr :description, :string, required: true

  # A radio with its consequence underneath, like the role choice in the team settings.
  defp consumers_option(assigns) do
    ~H"""
    <label class="flex cursor-pointer items-start gap-3">
      <input
        type="radio"
        name="consumers"
        value={@value}
        checked={@checked}
        class="mbs-0.5 size-5 shrink-0 cursor-pointer appearance-none rounded-full border-2 border-grey-300 bg-white checked:border-6 checked:border-grey-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-grey-900"
      />
      <span class="flex flex-col gap-0.5">
        <span class="text-sm font-medium text-grey-900">{@label}</span>
        <span class="text-sm/snug text-grey-600">{@description}</span>
      </span>
    </label>
    """
  end

  attr :text, :string, required: true, doc: "Translated sentence with a `__LINK__` marker."

  defp stripe_keys_sentence(assigns) do
    assigns = assign(assigns, :parts, String.split(assigns.text, "__LINK__", parts: 2))

    ~H"""
    <span phx-no-format>{List.first(@parts)}<.link
        kind="unstyled"
        external="https://dashboard.stripe.com/apikeys"
        target="_blank"
        rel="noopener noreferrer"
        class="inline-flex font-medium text-grey-900 underline underline-offset-2"
      >{gettext("API keys in Stripe")}</.link>{List.last(@parts)}</span>
    """
  end
end
