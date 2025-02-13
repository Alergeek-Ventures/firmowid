defmodule FirmowidWeb.HoursRecordLive.FormComponent do
  use FirmowidWeb, :live_component

  alias Firmowid.Timetracker

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage hours_record records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="hours_record-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:month]} type="number" label="Month" />
        <.input field={@form[:year]} type="number" label="Year" />
        <.input field={@form[:number_of_hours]} type="number" label="number_of_hours" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Hours record</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{hours_record: hours_record} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(Timetracker.change_hours_record(hours_record))
     end)}
  end

  @impl true
  def handle_event("validate", %{"hours_record" => hours_record_params}, socket) do
    changeset = Timetracker.change_hours_record(socket.assigns.hours_record, hours_record_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"hours_record" => hours_record_params}, socket) do
    save_hours_record(socket, socket.assigns.action, hours_record_params)
  end

  defp save_hours_record(socket, :edit, hours_record_params) do
    case Timetracker.update_hours_record(socket.assigns.hours_record, hours_record_params) do
      {:ok, hours_record} ->
        notify_parent({:saved, hours_record})

        {:noreply,
         socket
         |> put_flash(:info, "Hours record updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_hours_record(socket, :new, hours_record_params) do
    case Timetracker.create_hours_record(hours_record_params) do
      {:ok, hours_record} ->
        notify_parent({:saved, hours_record})

        {:noreply,
         socket
         |> put_flash(:info, "Hours record created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
