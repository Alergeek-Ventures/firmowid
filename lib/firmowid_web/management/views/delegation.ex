defmodule FirmowidWeb.Management.Views.Delegation do
  @moduledoc "Management view for preparing an employee's business-trip order."

  use FirmowidWeb, :live_view

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Delegations.Components.Delegation, only: [detail_row: 1]
  import FirmowidWeb.DesignSystem.Components.CoreComponents
  import FirmowidWeb.DesignSystem.Components.MonthPicker
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Core
  alias Firmowid.Delegations
  alias Firmowid.Payroll
  alias FirmowidWeb.Delegations.Utilities.DelegationPresentation
  alias FirmowidWeb.Infrastructure.Utilities.ElectronicSignature
  alias FirmowidWeb.Management.Utilities.Navigation

  @impl true
  def mount(_params, _session, socket) do
    [sign_before, sign_after] =
      split_sentence(gettext("Sign the document %{link}", link: "__LINK__"))

    [drop_before, drop_after] =
      split_sentence(gettext("Drag a file here or %{link}", link: "__LINK__"))

    {:ok,
     socket
     |> assign(:generated_advance_amount, nil)
     |> assign(:generated_billing_month, nil)
     |> assign(:current_advance_amount, Money.new(:PLN, 0))
     |> assign(sign_before: sign_before, sign_after: sign_after)
     |> assign(drop_before: drop_before, drop_after: drop_after)
     |> allow_upload(:signed_command, accept: ~w(.pdf), max_entries: 1)}
  end

  @impl true
  def handle_params(%{"id" => employee_id, "reference" => reference}, _uri, socket) do
    scope = socket.assigns.ash_scope

    case Core.get_org_user!(%{id: employee_id}, scope: scope, not_found_error?: false) do
      nil ->
        {:noreply, push_navigate(socket, to: Navigation.employees_path(:index))}

      employee ->
        employee = Ash.load!(employee, [member: [avatar_blob: [:url]]], scope: scope)
        member_id = employee.member.id
        {:ok, employment_contract} = Payroll.load_current_contract(member_id, scope: scope)

        delegation =
          case Delegations.get_delegation_by_reference(reference,
                 scope: scope,
                 not_found_error?: false
               ) do
            {:ok, %{member_id: ^member_id} = delegation} -> delegation
            _ -> nil
          end

        if delegation do
          {:noreply,
           socket
           |> assign(:employee, employee)
           |> assign(:employment_contract, employment_contract)
           |> assign(:delegation, delegation)
           |> assign(:command_form, command_form(false, delegation.advance_amount))
           |> assign(:current_advance_amount, delegation.advance_amount)
           |> assign(:billing_month, delegation.billing_month)
           |> assign(:page_title, gettext("Business trip order"))}
        else
          {:noreply, push_navigate(socket, to: Navigation.employee_path(employee.id))}
        end
    end
  end

  @impl true
  def handle_event("toggle-advance", %{"delegation_command" => params}, socket) do
    advance_amount = advance_amount(params)

    {:noreply,
     socket
     |> assign(
       :command_form,
       command_form(params["advance"] == "true", advance_amount)
     )
     |> assign(:current_advance_amount, advance_amount)}
  end

  @impl true
  def handle_event("generate", %{"delegation_command" => params}, socket) do
    advance_amount = advance_amount(params)

    case Delegations.prepare_delegation_command(
           socket.assigns.delegation.id,
           %{advance_amount: advance_amount},
           scope: socket.assigns.ash_scope
         ) do
      {:ok, delegation} ->
        {:noreply,
         socket
         |> assign(:delegation, delegation)
         |> assign(:generated_advance_amount, advance_amount)
         |> assign(:generated_billing_month, delegation.billing_month)
         |> assign(:current_advance_amount, advance_amount)
         |> assign(:command_form, command_form(params["advance"] == "true", advance_amount))}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, gettext("Could not generate the order."))}
    end
  end

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    case Date.from_iso8601(month) do
      {:ok, billing_month} ->
        case Delegations.update_delegation_billing_month(
               socket.assigns.delegation.id,
               %{billing_month: billing_month},
               scope: socket.assigns.ash_scope
             ) do
          {:ok, delegation} ->
            {:noreply,
             socket
             |> assign(:delegation, delegation)
             |> assign(:billing_month, delegation.billing_month)}

          {:error, _error} ->
            {:noreply, put_flash(socket, :error, gettext("Could not change the billing month."))}
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Invalid billing month."))}
    end
  end

  def handle_event("validate-upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :signed_command, ref)}
  end

  def handle_event("approve", _params, socket) do
    scope = socket.assigns.ash_scope

    result =
      consume_uploaded_entries(socket, :signed_command, fn %{path: path}, entry ->
        {:ok,
         Delegations.approve_delegation(
           socket.assigns.delegation.id,
           %{
             advance_amount: socket.assigns.delegation.advance_amount,
             signed_command_filename: entry.client_name,
             upload_path: path,
             content_type: entry.client_type
           },
           scope: scope
         )}
      end)

    case result do
      [{:ok, _delegation}] ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("The business trip has been approved successfully!"))
         |> push_navigate(to: Navigation.employee_delegations_path(socket.assigns.employee.id))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not approve the business trip."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="w-full px-4 py-6">
      <.back navigate={Navigation.employee_path(@employee.id)} class="justify-self-start">
        {gettext("Employee profile")}
      </.back>

      <h1 class="mt-10 text-2xl/tight font-medium">{gettext("Business trip order")}</h1>

      <div class="mt-10 grid grid-cols-1 items-start gap-10 lg:grid-cols-2">
        <section>
          <p class="max-w-xl text-base text-balance text-grey-700">
            {gettext(
              "Below you will find the details of the business trip submitted by the employee. Use them to decide whether they are entitled to an advance, then generate the order."
            )}
          </p>

          <dl class="mt-8 grid grid-cols-1 gap-x-8 gap-y-5 lg:grid-cols-[minmax(10rem,auto)_1fr]">
            <.detail_row label={gettext("Full name")}>
              <span class="flex items-center gap-2">
                <.avatar
                  id="delegation-employee-avatar"
                  class="size-6 rounded-full border border-grey-200 bg-grey-100"
                >
                  <.avatar_image
                    :if={@employee.member.avatar_blob && @employee.member.avatar_blob.url}
                    src={@employee.member.avatar_blob.url}
                    alt={@employee.member.name || @employee.email}
                  />
                  <.avatar_fallback class="text-[10px] font-medium text-grey-700">
                    {initial(@employee.member.name || @employee.email)}
                  </.avatar_fallback>
                </.avatar>
                {@employee.member.name || @employee.email}
              </span>
            </.detail_row>
            <.detail_row label={gettext("Position")}>
              {(@employment_contract && @employment_contract.position) || "—"}
            </.detail_row>
            <.detail_row label={gettext("Departure date")}>
              {DelegationPresentation.format_range(@delegation.start_date, @delegation.end_date)}
            </.detail_row>
            <.detail_row label={gettext("Purpose of the trip")}>{@delegation.purpose}</.detail_row>
            <.detail_row label={gettext("Estimated amount")}>
              {Money.to_string!(@delegation.expected_cost)}
            </.detail_row>
          </dl>

          <.form
            for={@command_form}
            id="delegation-command-form"
            phx-change="toggle-advance"
            phx-submit="generate"
            class="mt-10"
          >
            <dl class="grid grid-cols-1 items-start gap-x-8 gap-y-5 lg:grid-cols-[minmax(10rem,auto)_1fr]">
              <dt class="text-base text-grey-700">{gettext("Advance")}</dt>
              <dd><.switch field={@command_form[:advance]} color="teal" /></dd>

              <dt class="text-base text-grey-500">{gettext("For the amount")}</dt>
              <dd>
                <div class="grid w-full grid-cols-[8rem_auto] items-center gap-x-2 gap-y-5 lg:w-auto">
                  <.input
                    field={@command_form[:amount]}
                    type="number"
                    min="0"
                    step="0.01"
                    placeholder="0.00"
                    disabled={not @command_form[:advance].value}
                    aria-describedby="delegation-command-currency"
                    input_class="w-32 text-right text-grey-700 placeholder:text-grey-700 disabled:border-grey-400 disabled:text-grey-400 disabled:placeholder:text-grey-300"
                  />
                  <span id="delegation-command-currency" class="text-sm text-grey-500">PLN</span>
                  <.button
                    type="submit"
                    variant="primary"
                    accent="teal"
                    size="small"
                    class="col-span-2 w-full"
                    disabled={
                      not command_changed?(
                        @generated_advance_amount,
                        @current_advance_amount,
                        @generated_billing_month,
                        @billing_month
                      )
                    }
                  >
                    {gettext("Generate order")}
                  </.button>
                </div>
              </dd>
            </dl>
          </.form>
        </section>

        <section>
          <div class="grid w-full grid-cols-1 gap-y-2 text-base lg:ml-auto lg:w-fit lg:grid-cols-[auto_1fr] lg:items-center lg:gap-x-6">
            <span class="text-grey-700">{gettext("Billing month")}</span>
            <div class="relative w-57">
              <.month_picker
                id="delegation-billing-month"
                selected_date={Date.to_iso8601(@billing_month)}
                show_on_mobile
                variant="outline"
                size="small"
                class="w-full pr-10"
              />
              <Lucideicons.chevron_down class="pointer-events-none absolute top-1/2 right-3 size-4 -translate-y-1/2 text-grey-700" />
            </div>
          </div>

          <%= if is_nil(@generated_advance_amount) do %>
            <div class="mt-8 flex min-h-96 items-center justify-center rounded-md border border-grey-200 p-8 text-center shadow-sm">
              <p class="text-base text-grey-700">
                {gettext("Generate the order to be able to sign it.")}
              </p>
            </div>
          <% else %>
            <div class="mt-8 min-h-96 rounded-md border border-grey-200 p-8 shadow-sm">
              <div class="flex items-center justify-between gap-4">
                <h2 class="text-base font-medium text-teal-700">{gettext("Business trip order")}</h2>
                <p class="text-base text-grey-400">
                  {if Money.equal?(@delegation.advance_amount, Money.new(:PLN, 0)),
                    do: gettext("No advance"),
                    else:
                      gettext("Advance: %{amount}",
                        amount: DelegationPresentation.format_money(@delegation.advance_amount)
                      )}
                </p>
              </div>
              <ol class="mt-6 list-decimal space-y-3 pl-5 text-sm">
                <li>
                  {gettext("Download the document")}
                  <.link
                    kind="button"
                    variant="outline"
                    size="small"
                    redirect={
                      ~p"/zarzadzanie/pracownicy/#{@employee.id}/delegacje/#{@delegation.reference}/pdf"
                    }
                    download
                    class="mt-2 flex w-fit max-w-full sm:mt-0 sm:ml-2 sm:inline-flex"
                  >
                    <Lucideicons.file_text class="size-4 shrink-0 text-grey-900" />
                    <span class="truncate">{command_filename(@employee)}</span>
                  </.link>
                </li>
                <li>
                  {@sign_before}
                  <.link
                    kind="unstyled"
                    external={ElectronicSignature.trusted_profile_url()}
                    target="_blank"
                    class="inline-flex items-center gap-1 font-medium whitespace-nowrap text-teal-700"
                  >
                    {gettext("with a Trusted Profile")} <Lucideicons.external_link class="size-4" />
                  </.link>{@sign_after}
                </li>
                <li>{gettext("Upload the signed business trip order.")}</li>
              </ol>
              <form
                id="signed-command-upload"
                phx-change="validate-upload"
                phx-submit="approve"
                class="mt-6"
              >
                <.live_file_input upload={@uploads.signed_command} class="sr-only" />
                <label
                  :if={@uploads.signed_command.entries == []}
                  for={@uploads.signed_command.ref}
                  phx-drop-target={@uploads.signed_command.ref}
                  class="flex min-h-28 cursor-pointer items-center justify-center rounded-[5px] border border-dashed border-teal-200 px-4 text-center"
                >
                  <span class="text-teal-700 sm:hidden">{gettext("Choose a file")}</span>
                  <span class="hidden sm:inline">{@drop_before}<span class="text-teal-700">{gettext("choose from your computer")}</span>{@drop_after}</span>
                </label>
                <.file_display
                  :for={entry <- @uploads.signed_command.entries}
                  entry={entry}
                  upload={@uploads.signed_command}
                />
                <p
                  :for={error <- upload_errors(@uploads.signed_command)}
                  class="mt-2 text-sm text-brick-600"
                >
                  {upload_error(error)}
                </p>
                <div class="mt-5 flex gap-3">
                  <.button type="button" variant="secondary" class="w-[170px]">{gettext("Reject")}</.button>
                  <.button
                    type="submit"
                    variant="primary"
                    accent="teal"
                    disabled={@uploads.signed_command.entries == []}
                    class="w-[170px]"
                  >
                    {gettext("Send")}
                  </.button>
                </div>
              </form>
            </div>
          <% end %>
        </section>
      </div>
    </main>
    """
  end

  defp command_form(advance?, amount) do
    to_form(%{"advance" => advance?, "amount" => Money.to_decimal(amount)},
      as: :delegation_command
    )
  end

  defp advance_amount(%{"advance" => "true", "amount" => amount}) do
    case Decimal.parse(amount) do
      {decimal, ""} -> Money.new(:PLN, decimal)
      _ -> Money.new(:PLN, 0)
    end
  end

  defp advance_amount(_params), do: Money.new(:PLN, 0)

  defp command_changed?(nil, _advance_amount, _generated_billing_month, _billing_month), do: true

  defp command_changed?(generated_advance_amount, advance_amount, generated_billing_month, billing_month) do
    not Money.equal?(generated_advance_amount, advance_amount) or
      generated_billing_month != billing_month
  end

  defp upload_error(:too_large), do: gettext("The file is too large.")
  defp upload_error(:too_many_files), do: gettext("You can add only one file.")
  defp upload_error(:not_accepted), do: gettext("Upload a PDF file.")

  attr :entry, :map, required: true
  attr :upload, :map, required: true

  defp file_display(assigns) do
    ~H"""
    <div
      phx-drop-target={@upload.ref}
      class="flex min-h-28 items-center justify-between rounded-[5px] bg-teal-100 px-4"
    >
      <span class="flex min-w-0 items-center gap-2 text-sm">
        <Lucideicons.file_text class="size-5 shrink-0" />
        <span class="truncate">{@entry.client_name}</span>
      </span>
      <.button
        type="button"
        variant="unstyled"
        phx-click="cancel-upload"
        phx-value-ref={@entry.ref}
        class="ml-3 flex size-8 shrink-0 items-center justify-center text-teal-500 transition hover:text-teal-700"
        aria-label={gettext("Remove the signed order")}
      >
        <Lucideicons.x class="size-5" />
      </.button>
    </div>
    <p :for={error <- upload_errors(@upload, @entry)} class="mt-2 text-sm text-brick-600">
      {upload_error(error)}
    </p>
    """
  end

  defp command_filename(employee) do
    initials =
      (employee.member.name || employee.email)
      |> String.split()
      |> Enum.map_join(&String.first/1)
      |> String.upcase()

    "Polecenie_wyjazdu_#{initials}.pdf"
  end

  defp initial(name), do: name |> String.trim() |> String.first() |> String.upcase()

  # Splits a translated sentence around the marker that stands for its inline link.
  defp split_sentence(sentence), do: String.split(sentence, "__LINK__", parts: 2)
end
