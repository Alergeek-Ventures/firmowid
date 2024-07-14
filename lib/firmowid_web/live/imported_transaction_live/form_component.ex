defmodule FirmowidWeb.ImportedTransactionLive.FormComponent do
  use FirmowidWeb, :live_component

  alias Firmowid.Finances

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage imported_transaction records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="imported_transaction-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:transaction_id]} type="text" label="Transaction" />
        <.input field={@form[:debtor_name]} type="text" label="Debtor name" />
        <.input field={@form[:debtor_account]} type="text" label="Debtor account" />
        <.input field={@form[:transaction_amount]} type="number" label="Transaction amount" step="any" />
        <.input field={@form[:transaction_currency]} type="text" label="Transaction currency" />
        <.input field={@form[:bank_transaction_code]} type="text" label="Bank transaction code" />
        <.input field={@form[:booking_date]} type="date" label="Booking date" />
        <.input field={@form[:value_date]} type="date" label="Value date" />
        <.input field={@form[:remittance_information_unstructured]} type="text" label="Remittance information unstructured" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Imported transaction</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{imported_transaction: imported_transaction} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Finances.change_imported_transaction(imported_transaction))
     end)}
  end

  @impl true
  def handle_event("validate", %{"imported_transaction" => imported_transaction_params}, socket) do
    changeset = Finances.change_imported_transaction(socket.assigns.imported_transaction, imported_transaction_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"imported_transaction" => imported_transaction_params}, socket) do
    save_imported_transaction(socket, socket.assigns.action, imported_transaction_params)
  end

  defp save_imported_transaction(socket, :edit, imported_transaction_params) do
    case Finances.update_imported_transaction(socket.assigns.imported_transaction, imported_transaction_params) do
      {:ok, imported_transaction} ->
        notify_parent({:saved, imported_transaction})

        {:noreply,
         socket
         |> put_flash(:info, "Imported transaction updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_imported_transaction(socket, :new, imported_transaction_params) do
    case Finances.create_imported_transaction(imported_transaction_params) do
      {:ok, imported_transaction} ->
        notify_parent({:saved, imported_transaction})

        {:noreply,
         socket
         |> put_flash(:info, "Imported transaction created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
