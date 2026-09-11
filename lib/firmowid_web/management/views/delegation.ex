defmodule FirmowidWeb.Management.Views.Delegation do
  @moduledoc "Management view for preparing an employee's business-trip order."

  use FirmowidWeb, :live_view

  import FirmowidWeb.Delegations.Components.Delegation, only: [detail_row: 1]
  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Delegations
  alias FirmowidWeb.Delegations.Utilities.DelegationPresentation
  alias FirmowidWeb.Infrastructure.Utilities.ElectronicSignature
  alias FirmowidWeb.Management.Utilities.Navigation

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:command_generated, false)
     |> allow_upload(:signed_command, accept: ~w(.pdf), max_entries: 1)}
  end

  @impl true
  def handle_params(%{"id" => employee_id, "delegation_id" => delegation_id}, _uri, socket) do
    scope = socket.assigns.ash_scope

    case Core.get_org_user!(%{id: employee_id}, scope: scope, not_found_error?: false) do
      nil ->
        {:noreply, push_navigate(socket, to: Navigation.employees_path(:index))}

      employee ->
        employee = Ash.load!(employee, [avatar_blob: [:url]], scope: scope)

        delegation =
          employee_id
          |> Delegations.list_delegations_for_user!(scope: scope)
          |> Enum.find(&(&1.id == delegation_id))

        if delegation do
          {:noreply,
           socket
           |> assign(:employee, employee)
           |> assign(:delegation, delegation)
           |> assign(:command_form, command_form(false, delegation.advance_amount))
           |> assign(:page_title, "Polecenie wyjazdu służbowego")}
        else
          {:noreply, push_navigate(socket, to: Navigation.employee_path(employee.id))}
        end
    end
  end

  @impl true
  def handle_event("toggle-advance", %{"delegation_command" => %{"advance" => value}}, socket) do
    {:noreply,
     assign(
       socket,
       :command_form,
       command_form(value == "true", socket.assigns.delegation.advance_amount)
     )}
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
         |> assign(:command_generated, true)
         |> assign(:command_form, command_form(params["advance"] == "true", advance_amount))}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Nie udało się wygenerować polecenia.")}
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
         |> put_flash(:info, "Delegacja została zatwierdzona pomyślnie!")
         |> push_navigate(to: Navigation.employee_delegations_path(socket.assigns.employee.id))}

      _ ->
        {:noreply, put_flash(socket, :error, "Nie udało się zatwierdzić delegacji.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="w-full p-6 lg:px-4">
      <.back navigate={Navigation.employee_path(@employee.id)} class="justify-self-start">
        Profil pracownika
      </.back>

      <h1 class="mt-10 text-2xl/tight font-medium">Polecenie wyjazdu służbowego</h1>

      <div class="mt-10 grid grid-cols-1 items-start gap-10 lg:grid-cols-2">
        <section>
          <p class="text-grey-700 max-w-xl text-base text-balance">
            Poniżej znajdziesz szczegóły delegacji zgłoszonej przez pracownika. Na tej podstawie ustal, czy przysługuje mu zaliczka, a następnie wygeneruj polecenie.
          </p>

          <dl class="mt-8 grid grid-cols-[minmax(10rem,auto)_1fr] gap-x-8 gap-y-5">
            <.detail_row label="Imię i nazwisko">
              <span class="flex items-center gap-2">
                <.avatar id="delegation-employee-avatar" class="bg-grey-100 size-6 rounded-full">
                  <.avatar_image
                    :if={@employee.avatar_blob && @employee.avatar_blob.url}
                    src={@employee.avatar_blob.url}
                    alt={@employee.name || @employee.email}
                  />
                  <.avatar_fallback class="text-grey-700 text-[10px] font-medium">
                    {initial(@employee.name || @employee.email)}
                  </.avatar_fallback>
                </.avatar>
                {@employee.name || @employee.email}
              </span>
            </.detail_row>
            <.detail_row label="Stanowisko">{@employee.position || "—"}</.detail_row>
            <.detail_row label="Data wyjazdu">
              {DelegationPresentation.format_range(@delegation.start_date, @delegation.end_date)}
            </.detail_row>
            <.detail_row label="Cel wyjazdu">{@delegation.purpose}</.detail_row>
            <.detail_row label="Przewidywana kwota">
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
            <dl class="grid grid-cols-[minmax(10rem,auto)_1fr] items-start gap-x-8 gap-y-5">
              <dt class="text-grey-700 text-base">Zaliczka</dt>
              <dd><.switch field={@command_form[:advance]} color="turquoise" /></dd>

              <dt class="text-grey-500 text-base">Na kwotę</dt>
              <dd>
                <div class="inline-grid grid-cols-[8rem_auto] items-center gap-x-2 gap-y-5">
                  <.input
                    field={@command_form[:amount]}
                    type="number"
                    new
                    min="0"
                    step="0.01"
                    placeholder="0.00"
                    disabled={not @command_form[:advance].value}
                    aria-describedby="delegation-command-currency"
                    input_class="w-32 text-right text-grey-700 placeholder:text-grey-700 disabled:border-grey-400 disabled:text-grey-400 disabled:placeholder:text-grey-300"
                  />
                  <span id="delegation-command-currency" class="text-grey-500 text-sm">PLN</span>
                  <.button
                    type="submit"
                    variant="primary"
                    accent="turquoise"
                    size="small"
                    class="col-span-2 w-full"
                  >
                    Wygeneruj polecenie
                  </.button>
                </div>
              </dd>
            </dl>
          </.form>
        </section>

        <section>
          <dl class="grid grid-cols-[auto_1fr] gap-x-6 text-base">
            <dt class="text-grey-700">Miesiąc rozliczeniowy</dt>
            <dd>{format_billing_month(@delegation.billing_month)}</dd>
          </dl>

          <%= if not @command_generated do %>
            <div class="border-grey-200 mt-8 flex min-h-96 items-center justify-center rounded-md border p-8 text-center shadow-sm">
              <p class="text-grey-700 text-base">Wygeneruj polecenie, aby móc je podpisać.</p>
            </div>
          <% else %>
            <div class="border-grey-200 mt-8 min-h-96 rounded-md border p-8 shadow-sm">
              <div class="flex items-center justify-between gap-4">
                <h2 class="text-turquoise-700 text-base font-medium">Polecenie wyjazdu służbowego</h2>
                <p class="text-grey-400 text-base">
                  {if Money.equal?(@delegation.advance_amount, Money.new(:PLN, 0)),
                    do: "Bez zaliczki",
                    else:
                      "Zaliczka: #{DelegationPresentation.format_money(@delegation.advance_amount)}"}
                </p>
              </div>
              <ol class="mt-6 list-decimal space-y-3 pl-5 text-sm">
                <li>
                  Pobierz dokument
                  <.link
                    kind="button"
                    variant="outline"
                    size="small"
                    redirect={
                      ~p"/zarzadzanie/pracownicy/#{@employee.id}/delegacje/#{@delegation.id}/pdf"
                    }
                    download
                    class="ml-2 inline-flex"
                  >
                    <Lucideicons.file_text class="size-4 fill-current" />
                    {command_filename(@employee)}
                  </.link>
                </li>
                <li>
                  Podpisz dokument
                  <.link
                    kind="unstyled"
                    external={ElectronicSignature.trusted_profile_url()}
                    target="_blank"
                    class="text-turquoise-700"
                  >
                    Profilem Zaufanym <Lucideicons.external_link class="inline size-4" />
                  </.link>
                </li>
                <li>Wgraj podpisane polecenie wyjazdu służbowego.</li>
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
                  class="border-turquoise-200 flex min-h-28 cursor-pointer items-center justify-center rounded-[5px] border border-dashed px-4 text-center"
                >
                  <span>Przeciągnij plik tutaj lub
                  <span class="text-turquoise-700">wybierz z komputera</span></span>
                </label>
                <.file_display
                  :for={entry <- @uploads.signed_command.entries}
                  entry={entry}
                  upload={@uploads.signed_command}
                />
                <p
                  :for={error <- upload_errors(@uploads.signed_command)}
                  class="mt-2 text-sm text-red-600"
                >
                  {upload_error(error)}
                </p>
                <div class="mt-5 flex gap-3">
                  <.button type="button" variant="secondary" class="w-[170px]">Odrzuć</.button>
                  <.button
                    type="submit"
                    variant="primary"
                    accent="turquoise"
                    disabled={@uploads.signed_command.entries == []}
                    class="w-[170px]"
                  >
                    Wyślij
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

  defp upload_error(:too_large), do: "Plik jest zbyt duży."
  defp upload_error(:too_many_files), do: "Możesz dodać tylko jeden plik."
  defp upload_error(:not_accepted), do: "Wgraj plik PDF."

  attr :entry, :map, required: true
  attr :upload, :map, required: true

  defp file_display(assigns) do
    ~H"""
    <div
      phx-drop-target={@upload.ref}
      class="bg-turquoise-100 flex min-h-28 items-center justify-between rounded-[5px] px-4"
    >
      <span class="flex min-w-0 items-center gap-2 text-sm">
        <Lucideicons.file_text class="size-5 shrink-0 fill-current" />
        <span class="truncate">{@entry.client_name}</span>
      </span>
      <.button
        type="button"
        variant="unstyled"
        phx-click="cancel-upload"
        phx-value-ref={@entry.ref}
        class="hover:text-turquoise-700 text-turquoise-500 ml-3 flex size-8 shrink-0 items-center justify-center transition"
        aria-label="Usuń podpisane polecenie"
      >
        <Lucideicons.x class="size-5" />
      </.button>
    </div>
    <p :for={error <- upload_errors(@upload, @entry)} class="mt-2 text-sm text-red-600">
      {upload_error(error)}
    </p>
    """
  end

  defp command_filename(employee) do
    initials =
      (employee.name || employee.email)
      |> String.split()
      |> Enum.map_join(&String.first/1)
      |> String.upcase()

    "Polecenie_wyjazdu_#{initials}.pdf"
  end

  defp initial(name), do: name |> String.trim() |> String.first() |> String.upcase()

  defp format_billing_month(billing_month) do
    Cldr.Date.to_string!(billing_month, Firmowid.Cldr, format: "LLLL y", locale: "pl")
  end
end
