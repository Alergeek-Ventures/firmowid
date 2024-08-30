defmodule FirmowidWeb.DocumentsLive.Show do
  use FirmowidWeb, :live_view

  alias Firmowid.Documents

  @impl true
  def mount(params, _session, socket) do
    document = Documents.get_document(params["id"])

    document =
      Map.merge(
        document,
        %{
          file_url: Documents.get_file_url(document.id),
          amount:
            Money.from_float!(
              document.currency,
              document.total_amount
            )
        }
      )

    potential_transactions =
      Documents.get_potential_transactions(document)
      |> Enum.map(fn t ->
        Map.merge(t, %{
          amount:
            Money.from_float!(
              t.transaction_currency,
              t.transaction_amount
            )
        })
      end)

    socket =
      socket
      |> assign(:document, document)
      |> assign(:potential_transactions, potential_transactions)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  defp apply_action(socket, :index, params) do
    socket
    |> assign(:page_title, "Podgląd dokumentu #{params["id"]}")
  end
end
