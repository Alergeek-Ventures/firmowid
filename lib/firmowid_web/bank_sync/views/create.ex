defmodule FirmowidWeb.BankSync.Views.Create do
  @moduledoc """
  LiveView for creating GoCardless bank connections.

  Uses Ash native code interfaces from Firmowid.Ash.Finances domain.
  The AshOban trigger on Requisition auto-schedules status polling.
  """
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.CoreComponents, except: [button: 1]
  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  alias Firmowid.Ash.Finances
  alias Firmowid.ErrorKind

  require Logger

  @institution_refresh_delay 300
  @institution_refresh_limit 5

  @impl true
  def render(assigns) do
    ~H"""
    <section class="container mx-auto flex flex-col gap-8 pt-4">
      <.header>
        Dodaj konto bankowe
      </.header>

      <div class="flex flex-col gap-1">
        <p class="m-0">
          Za pomocą rozwiązania naszego partnera, GoCardless, połączymy Twoje konto z
          Firmowidem.
        </p>
        <p class="m-0">
          Sprawi to, że transakcje będą automatycznie synchronizowane, a
          faktury automatycznie dopasowywane.
        </p>
      </div>

      <%= if is_nil(@requisition_link) do %>
        <div class="grid grid-cols-1 items-center gap-4 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
          <form
            :for={institution <- @available_institutions}
            id={"institution-#{institution.id}"}
            phx-submit="institution_selected"
            phx-value-institution-id={institution.id}
            phx-value-institution-transaction-total-days={institution.transaction_total_days}
          >
            <.institution_button
              id={"institution-button-#{institution.id}"}
              color_rgb={institution.dominant_color_rgb}
              phx-hook="TippyWhenTruncated"
              data-tippy-content={institution.name}
              data-tippy-truncate-selector="[data-role='institution-name']"
            >
              <img src={institution.logo} class="h-10 w-auto" />
              <p data-role="institution-name" class="max-w-40 truncate">
                {institution.name}
              </p>
            </.institution_button>
          </form>
          <form
            id="instiution-SANDBOXFINANCE_SFIN0000"
            phx-submit="institution_selected"
            phx-value-institution-id="SANDBOXFINANCE_SFIN0000"
            phx-value-institution-transaction-total-days={90}
            phx-hook="Tippy"
            data-tippy-content="Kliknij aby dodać konto bankowe przygotowane przez nas, które zawiera kilkanaście transakcji i pozwala przetestować system."
          >
            <.institution_button>
              <div class="flex h-10 items-center justify-center">
                <Lucideicons.flask_conical class="size-7" />
              </div>
              <p>
                Konto Sandbox
              </p>
            </.institution_button>
          </form>
        </div>
      <% else %>
        <.link kind="unstyled" external={@requisition_link} class="text-xl font-bold underline">
          Kliknij, aby potwierdzić połączenie
          <.icon name="hero-arrow-right-start-on-rectangle" class="size-8" />
        </.link>
      <% end %>
    </section>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:institution_refresh_attempts, 0)
      |> assign(:available_institutions, fetch_available_institutions(socket))
      |> assign(:requisition_link, nil)

    maybe_schedule_institution_refresh(socket)

    {:ok, socket}
  end

  @impl true
  def handle_info(:refresh_institutions, socket) do
    socket =
      socket
      |> update(:institution_refresh_attempts, &(&1 + 1))
      |> assign(:available_institutions, fetch_available_institutions(socket))

    maybe_schedule_institution_refresh(socket)

    {:noreply, socket}
  end

  @impl true
  def handle_params(params, url, socket) do
    # extract domain for redirecting when submitting an account
    # (makes it work for both localhost and production)
    socket = assign(socket, :redirect_url, url |> String.split("?") |> List.first())

    requisition_id = params["ref"]

    if is_nil(requisition_id) do
      {:noreply, socket}
    else
      # AshOban trigger auto-schedules status check when requisition is pending.
      # No manual worker insertion needed.
      error = params["error"]

      if is_nil(error) do
        {:noreply,
         socket
         |> LiveToast.put_toast(
           :success,
           "Konto bankowe zostało poprawnie połączone.",
           title: "Gotowe"
         )
         |> push_navigate(to: ~p"/ustawienia/firma")}
      else
        details = params["details"]

        Logger.warning("Failed to connect to bank",
          error_kind: ErrorKind.classify(error),
          details_kind: ErrorKind.classify(details)
        )

        {:noreply,
         socket
         |> LiveToast.put_toast(
           :error,
           "Będziemy kontynuować próby połączenia w Twoim imieniu.",
           title: "Połączenie z bankiem nie zostało utworzone w tym momencie."
         )
         |> push_patch(to: ~p"/fakturowanie")}
      end
    end
  end

  @impl true
  def handle_event(
        "institution_selected",
        %{"institution-id" => institution_id, "institution-transaction-total-days" => transaction_total_days},
        socket
      ) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    # it comes as as string
    transaction_total_days = String.to_integer(transaction_total_days)

    # Use Ash native code interface with authorization
    # The AshOban trigger auto-schedules status polling on create
    {:ok, link} =
      Finances.create_requisition(
        institution_id,
        transaction_total_days,
        socket.assigns.redirect_url,
        tenant: organization_id,
        actor: user,
        authorize?: true
      )

    {:noreply, assign(socket, :requisition_link, link)}
  end

  attr :rest, :global
  attr :color_rgb, :string, default: nil
  slot :inner_block, required: true

  defp institution_button(assigns) do
    ~H"""
    <.button
      type="submit"
      variant="unstyled"
      style={institution_button_style(@color_rgb)}
      class={["block w-full cursor-pointer", institution_button_styles(@color_rgb)]}
      {@rest}
    >
      <div class="flex size-full flex-row items-center justify-between gap-4 p-4 text-center">
        {render_slot(@inner_block)}
      </div>
    </.button>
    """
  end

  defp institution_button_style(nil), do: nil

  defp institution_button_style(color_rgb) do
    "background-color: rgb(#{color_rgb} / 0.5); color: #{institution_button_text_color(color_rgb)};"
  end

  defp institution_button_styles(nil) do
    [
      "size-full rounded-sm border-2 border-black/20 bg-white transition-all",
      "hover:border-black hover:bg-white/10 active:bg-white/20"
    ]
  end

  defp institution_button_styles(_color_rgb) do
    [
      "size-full rounded-sm border-2 border-black/20 transition-all",
      "hover:border-black hover:opacity-75"
    ]
  end

  defp fetch_available_institutions(socket) do
    case Finances.list_institutions("pl", actor: socket.assigns.current_user) do
      {:ok, institutions} -> institutions
      {:error, _} -> []
    end
  end

  defp maybe_schedule_institution_refresh(socket) do
    if should_refresh_institutions?(socket) do
      Process.send_after(self(), :refresh_institutions, @institution_refresh_delay)
    end

    socket
  end

  defp should_refresh_institutions?(socket) do
    socket.assigns.institution_refresh_attempts < @institution_refresh_limit and
      Enum.any?(socket.assigns.available_institutions, &is_nil(&1.dominant_color_rgb))
  end

  defp institution_button_text_color(color_rgb) do
    [red, green, blue] = color_rgb |> String.split(" ") |> Enum.map(&String.to_integer/1)

    if contrast_prefers_dark_text?({red, green, blue}) do
      "rgb(17 24 39)"
    else
      "rgb(255 255 255)"
    end
  end

  defp contrast_prefers_dark_text?({red, green, blue}) do
    brightness = red * 0.299 + green * 0.587 + blue * 0.114
    brightness >= 160
  end
end
