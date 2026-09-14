defmodule FirmowidWeb.Management.Views.CounterpartyForm do
  @moduledoc """
  Management LiveView for creating and editing counterparties.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Ash.Error.Changes.InvalidAttribute
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.Counterparty
  alias Firmowid.Ash.Invoicing.CountryCodes
  alias Firmowid.Ash.Invoicing.Services.NipApiClient
  alias FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents
  alias FirmowidWeb.Invoicing.Utilities.Navigation, as: InvoicingNavigation
  alias FirmowidWeb.Management.Utilities.Navigation

  @impl true
  def mount(params, _session, %{assigns: %{live_action: :new}} = socket) do
    scope = socket.assigns.ash_scope
    params = Navigation.counterparty_params(params)

    form =
      Counterparty
      |> AshPhoenix.Form.for_create(:create, scope: scope, as: "counterparty")
      |> to_form()

    {:ok, socket |> assign_navigation(nil, params) |> assign_form_view(nil, form, params)}
  end

  def mount(%{"id" => id} = params, _session, %{assigns: %{live_action: :edit}} = socket) do
    scope = socket.assigns.ash_scope
    params = Navigation.counterparty_params(params)

    case Invoicing.get_counterparty(id, scope: scope, not_found_error?: false) do
      {:ok, nil} ->
        {:ok, redirect_to_counterparties(socket, params)}

      {:ok, counterparty} ->
        form =
          counterparty
          |> AshPhoenix.Form.for_update(:update, scope: scope, as: "counterparty")
          |> to_form()

        {:ok,
         socket
         |> assign_navigation(counterparty, params)
         |> assign_form_view(counterparty, form, params)}

      {:error, _error} ->
        {:ok,
         socket
         |> put_flash(:error, "Nie udało się wczytać kontrahenta")
         |> redirect_to_counterparties(params)}
    end
  end

  @impl true
  def handle_event("validate", %{"counterparty" => params}, socket) do
    form =
      socket.assigns.form
      |> AshPhoenix.Form.validate(params)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"counterparty" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, counterparty} ->
        event =
          case socket.assigns.live_action do
            :new -> :counterparty_created
            :edit -> :counterparty_updated
          end

        {:noreply,
         push_navigate(
           PosthogBusinessEvents.capture(socket, event),
           to: save_destination(counterparty, socket.assigns.live_action, socket.assigns.params)
         )}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  def handle_event("fetch_by_nip", params, socket) do
    nip = Map.get(params, "nip", "")

    case fetch_counterparty_data(nip) do
      {:ok, organization} ->
        params =
          Map.merge(socket.assigns.form.params, %{
            "type" => "company",
            "tax_id" => organization.nip,
            "display_name" => organization.name,
            "full_name" => organization.name,
            "address" => organization.address,
            "country" => "PL"
          })

        form =
          socket.assigns.form
          |> AshPhoenix.Form.validate(params, errors: false)
          |> to_form()

        {:noreply, assign(socket, :form, form)}

      {:error, message} ->
        {:noreply, assign(socket, :form, form_with_tax_id_error(socket.assigns.form, nip, message))}
    end
  end

  defp fetch_counterparty_data(""), do: {:error, "NIP jest wymagany"}

  defp fetch_counterparty_data(nip) do
    case NipApiClient.fetch_org_data_by_nip(nip) do
      {:ok, organization} -> {:ok, organization}
      {:error, :invalid_nip} -> {:error, "musi być poprawnym numerem NIP"}
      {:error, :not_found} -> {:error, "Nie znaleziono kontrahenta dla podanego NIP"}
      {:error, _reason} -> {:error, "Nie udało się pobrać danych kontrahenta"}
    end
  end

  defp form_with_tax_id_error(form, nip, message) do
    form
    |> AshPhoenix.Form.validate(Map.put(form.params, "tax_id", nip))
    |> AshPhoenix.Form.add_error(%InvalidAttribute{field: :tax_id, message: message})
    |> to_form()
  end

  defp assign_navigation(socket, counterparty, params),
    do: assign(socket, :cancel_path, cancel_path(socket.assigns.live_action, counterparty, params))

  defp assign_form_view(socket, counterparty, form, params) do
    socket
    |> assign(:counterparty, counterparty)
    |> assign(:form, form)
    |> assign(:params, params)
    |> assign(:country_options, CountryCodes.country_options())
  end

  defp redirect_to_counterparties(socket, params) do
    push_navigate(socket, to: form_return_path(params))
  end

  defp cancel_path(:new, _counterparty, params), do: form_return_path(params)

  defp cancel_path(:edit, counterparty, params), do: Navigation.counterparty_path(counterparty.id, params)

  defp save_destination(counterparty, :new, params) do
    InvoicingNavigation.sales_invoice_creator_return_path(params["powrot_do"]) ||
      Navigation.counterparty_path(counterparty.id, params)
  end

  defp save_destination(counterparty, :edit, params), do: Navigation.counterparty_path(counterparty.id, params)

  defp form_return_path(params) do
    Navigation.counterparties_return_path(params["powrot_do"]) ||
      InvoicingNavigation.sales_invoice_creator_return_path(params["powrot_do"]) ||
      ~p"/zarzadzanie/kontrahenci"
  end
end
