defmodule FirmowidWeb.Management.Views.CounterpartyForm do
  @moduledoc """
  Management LiveView for creating and editing counterparties.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.Counterparty
  alias Firmowid.Ash.Invoicing.CountryCodes

  @impl true
  def mount(_params, _session, %{assigns: %{live_action: :new}} = socket) do
    scope = socket.assigns.ash_scope

    form =
      Counterparty
      |> AshPhoenix.Form.for_create(:create, scope: scope, as: "counterparty")
      |> to_form()

    {:ok, socket |> assign_navigation(nil) |> assign_form_view(nil, form)}
  end

  def mount(%{"id" => id}, _session, %{assigns: %{live_action: :edit}} = socket) do
    scope = socket.assigns.ash_scope

    case Invoicing.get_counterparty(id, scope: scope, not_found_error?: false) do
      {:ok, nil} ->
        {:ok, redirect_to_counterparties(socket)}

      {:ok, counterparty} ->
        form =
          counterparty
          |> AshPhoenix.Form.for_update(:update, scope: scope, as: "counterparty")
          |> to_form()

        {:ok, socket |> assign_navigation(counterparty) |> assign_form_view(counterparty, form)}

      {:error, _error} ->
        {:ok,
         socket
         |> put_flash(:error, "Nie udało się wczytać kontrahenta")
         |> redirect_to_counterparties()}
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
        {:noreply, push_navigate(socket, to: save_destination(counterparty))}

      {:error, form} ->
        {:noreply, assign(socket, :form, to_form(form))}
    end
  end

  defp assign_navigation(socket, counterparty),
    do: assign(socket, :cancel_path, cancel_path(socket.assigns.live_action, counterparty))

  defp assign_form_view(socket, counterparty, form) do
    socket
    |> assign(:counterparty, counterparty)
    |> assign(:form, form)
    |> assign(:country_options, CountryCodes.country_options())
  end

  defp redirect_to_counterparties(socket) do
    push_navigate(socket, to: ~p"/zarzadzanie/kontrahenci")
  end

  defp cancel_path(:new, _counterparty), do: ~p"/zarzadzanie/kontrahenci"
  defp cancel_path(:edit, counterparty), do: ~p"/zarzadzanie/kontrahenci/#{counterparty.id}"

  defp save_destination(counterparty), do: ~p"/zarzadzanie/kontrahenci/#{counterparty.id}"
end
