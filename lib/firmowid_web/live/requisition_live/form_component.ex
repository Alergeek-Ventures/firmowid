defmodule FirmowidWeb.RequisitionLive.FormComponent do
  use FirmowidWeb, :live_component

  alias Firmowid.GoLimitless

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage requisition records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="requisition-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:requisition_id]} type="text" label="Requisition" />
        <.input field={@form[:status]} type="text" label="Status" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Requisition</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{requisition: requisition} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(GoLimitless.change_requisition(requisition))
     end)}
  end

  @impl true
  def handle_event("validate", %{"requisition" => requisition_params}, socket) do
    changeset = GoLimitless.change_requisition(socket.assigns.requisition, requisition_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"requisition" => requisition_params}, socket) do
    save_requisition(socket, socket.assigns.action, requisition_params)
  end

  defp save_requisition(socket, :edit, requisition_params) do
    case GoLimitless.update_requisition(socket.assigns.requisition, requisition_params) do
      {:ok, requisition} ->
        notify_parent({:saved, requisition})

        {:noreply,
         socket
         |> put_flash(:info, "Requisition updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_requisition(socket, :new, requisition_params) do
    case GoLimitless.create_requisition(requisition_params) do
      {:ok, requisition} ->
        notify_parent({:saved, requisition})

        {:noreply,
         socket
         |> put_flash(:info, "Requisition created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
