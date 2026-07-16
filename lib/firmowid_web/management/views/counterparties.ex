defmodule FirmowidWeb.Management.Views.Counterparties do
  @moduledoc """
  Management LiveView for listing active and archived counterparties.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Invoicing
  alias FirmowidWeb.Management.Utilities.CounterpartyHelpers
  alias FirmowidWeb.Management.Utilities.Navigation

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.ash_scope

    zero_state? =
      Invoicing.list_counterparties!(%{status: :all, limit: 1}, scope: scope) == []

    {:ok,
     socket
     |> assign(:page_title, "Zarządzanie kontrahentami")
     |> assign(:zero_state?, zero_state?)
     |> assign(:counterparties_empty?, true)
     |> assign(:view, :standard)
     |> stream(:counterparties, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = Navigation.counterparties_params(params)

    socket =
      socket
      |> assign(:params, params)
      |> assign(:search, params["szukaj"] || "")
      |> assign(:type_filter, Navigation.parse_counterparty_type(params["typ"]))
      |> assign_counterparties()
      |> assign_form()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"szukaj" => search}, socket) do
    {:noreply, refresh_page(socket, Map.put(socket.assigns.params, "szukaj", String.trim(search)))}
  end

  def handle_event("toggle_type", %{"typ" => type}, socket) do
    next_type =
      case {socket.assigns.type_filter, Navigation.parse_counterparty_type(type)} do
        {current, current} -> nil
        {_current, parsed} -> parsed
      end

    params =
      case next_type do
        nil ->
          Map.delete(socket.assigns.params, "typ")

        value ->
          Map.put(socket.assigns.params, "typ", Navigation.encode_counterparty_type(value))
      end

    {:noreply, refresh_page(socket, params)}
  end

  def handle_event("unarchive_counterparty", %{"id" => id}, socket) do
    scope = socket.assigns.ash_scope

    with {:ok, counterparty} when not is_nil(counterparty) <-
           Invoicing.get_counterparty(id, scope: scope, not_found_error?: false),
         {:ok, _counterparty} <- Invoicing.unarchive_counterparty(counterparty, %{}, scope: scope) do
      {:noreply,
       socket
       |> stream_delete(:counterparties, counterparty)
       |> assign(
         :counterparties_empty?,
         length(socket.assigns.streams.counterparties.inserts) == 1
       )}
    else
      _ -> {:noreply, put_flash(socket, :error, "Nie udało się przywrócić kontrahenta")}
    end
  end

  def handle_event("toggle_cooperation_value_view", _params, socket) do
    {:noreply,
     socket
     |> assign(
       :view,
       if(socket.assigns.view == :standard, do: :cooperation_value, else: :standard)
     )
     |> assign_form()}
  end

  defp assign_counterparties(socket) do
    scope = socket.assigns.ash_scope

    status = if socket.assigns.live_action == :archive, do: :archived, else: :active

    filters =
      %{
        status: status,
        search: blank_to_nil(socket.assigns.search),
        type: socket.assigns.type_filter
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    counterparties =
      Invoicing.list_counterparties!(filters,
        load: [:display_label, :cooperation_value],
        scope: scope
      )

    socket
    |> assign(:counterparties_empty?, counterparties == [])
    |> stream(:counterparties, counterparties, reset: true)
  end

  defp assign_form(socket) do
    assign(
      socket,
      :form,
      to_form(%{"view_cooperation_value" => socket.assigns.view != :standard})
    )
  end

  defp refresh_page(socket, params) do
    params =
      Map.reject(params, fn
        {_k, ""} -> true
        {_k, nil} -> true
        _other -> false
      end)

    push_patch(socket, to: Navigation.counterparties_path(socket.assigns.live_action, params))
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  attr :counterparty, :map, required: true

  defp counterparty_identifier(assigns) do
    ~H"""
    {CounterpartyHelpers.identifier(@counterparty)}
    """
  end

  attr :counterparty, :map, required: true

  defp counterparty_icon(assigns) do
    ~H"""
    <.icon name={CounterpartyHelpers.type_icon_name(@counterparty)} class="text-grey-500 size-6" />
    """
  end

  defp cooperation_value_cell(nil), do: "—"

  defp cooperation_value_cell(%{total: total, currency: currency}) do
    total
    |> Money.new(currency)
    |> Money.to_string!(fractional_digits: 2)
  end
end
