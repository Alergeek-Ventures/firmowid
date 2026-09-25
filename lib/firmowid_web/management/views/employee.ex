# credo:disable-for-this-file ExDNA.Credo
# Employee detail view duplicates monthly aggregation/cost assembly paths; resolving this
# cleanly requires extracting shared timetracker/payroll query helpers across LiveViews.
defmodule FirmowidWeb.Management.Views.Employee do
  @moduledoc false
  use FirmowidWeb, :live_view

  import FirmowidWeb.DesignSystem.Components.Button
  import FirmowidWeb.DesignSystem.Components.Link
  import FirmowidWeb.Management.Components.Card
  import FirmowidWeb.Management.Components.Tab
  import Phoenix.Component, except: [link: 1]

  alias Ash.Notifier.Notification
  alias Firmowid.Ash.Blobs.Blob
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Timetracker
  alias FirmowidWeb.Core.Endpoint
  alias FirmowidWeb.Documents.Components.DocumentsSection, as: DocumentsTab
  alias FirmowidWeb.Infrastructure.Components.BlobProcessingToasts
  alias FirmowidWeb.Infrastructure.Utilities.TimeFormatter
  alias FirmowidWeb.Management.Components.LeavesTab
  alias FirmowidWeb.Management.Components.ProfileTab
  alias FirmowidWeb.Management.Utilities.Navigation
  alias Phoenix.Socket.Broadcast

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    organization_id = user.organization_id

    if connected?(socket) do
      # Ash PubSub — blobs
      Endpoint.subscribe("blob:created:#{organization_id}")
      Endpoint.subscribe("blob:updated:#{organization_id}")
      Endpoint.subscribe("blob:destroyed:#{organization_id}")
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    if socket.assigns.current_user.role == :admin do
      scope = socket.assigns.ash_scope
      params = Navigation.employee_params(params)

      selected_date = Navigation.parse_month(params)

      user =
        %{id: id}
        |> Core.get_org_user!(scope: scope, not_found_error?: false)
        |> case do
          nil ->
            nil

          loaded_user ->
            Ash.load!(
              loaded_user,
              [:display_name, :projects, :delegations, :shared_birthday, avatar_blob: [:url]],
              scope: scope
            )
        end

      socket =
        if is_nil(user) do
          push_navigate(socket,
            to: Navigation.employees_path(:index, %{miesiac: Navigation.current_month()})
          )
        else
          active_months = months_with_sessions(%{user_id: id}, scope)

          socket
          |> assign(:employee, user)
          |> assign(:active_months, active_months)
          |> assign(:projects_filter_date, selected_date)
          |> assign(:page_title, user.display_name)
        end

      {:noreply, socket}
    else
      {:noreply,
       push_navigate(socket,
         to: Navigation.employees_path(:index, %{miesiac: Navigation.current_month()})
       )}
    end
  end

  def format_shared_birthday(%{day: day, month: month, year: year}) do
    {:ok, date} = Date.new(year, month, day)
    TimeFormatter.format_date(date, "d MMMM yyyy")
  end

  def format_shared_birthday(%{day: day, month: month}) do
    {:ok, date} = Date.new(Date.utc_today().year, month, day)
    TimeFormatter.format_date(date, "d MMMM")
  end

  def format_shared_birthday(_), do: nil

  @impl true
  def handle_event("change-month", %{"month" => month}, socket) do
    employee = socket.assigns.employee
    {:noreply, push_patch(socket, to: Navigation.employee_path(employee.id, %{miesiac: month}))}
  end

  def handle_event("change-year", %{"year" => year}, socket) do
    send_update(LeavesTab, id: "leaves-tab", year: String.to_integer(year))
    {:noreply, socket}
  end

  def handle_event("archive_employee", _params, socket) do
    scope = socket.assigns.ash_scope

    with {:ok, user} <-
           Core.get_org_user(%{id: socket.assigns.employee.id},
             scope: scope,
             not_found_error?: false
           ),
         {:ok, archived_user} <- Core.archive_user(user, %{}, scope: scope) do
      loaded_user =
        Ash.load!(
          archived_user,
          [:display_name, :projects, :delegations, :shared_birthday, avatar_blob: [:url]],
          scope: scope
        )

      {:noreply,
       socket
       |> assign(:employee, loaded_user)
       |> assign(:page_title, loaded_user.display_name)}
    else
      {:error, %Ash.Error.Forbidden{}}
      when socket.assigns.current_user.id == socket.assigns.employee.id ->
        {:noreply, put_flash(socket, :error, "Nie możesz zarchiwizować własnego konta.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, humanize_ash_error(error))}

      _ ->
        {:noreply, put_flash(socket, :error, "Nie udało się zarchiwizować pracownika")}
    end
  end

  def handle_event("unarchive_employee", _params, socket) do
    scope = socket.assigns.ash_scope

    with {:ok, user} <-
           Core.get_org_user(%{id: socket.assigns.employee.id},
             scope: scope,
             not_found_error?: false
           ),
         {:ok, unarchived_user} <- Core.unarchive_user(user, %{}, scope: scope) do
      loaded_user =
        Ash.load!(
          unarchived_user,
          [:display_name, :projects, :delegations, :shared_birthday, avatar_blob: [:url]],
          scope: scope
        )

      {:noreply,
       socket
       |> assign(:employee, loaded_user)
       |> assign(:page_title, loaded_user.display_name)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Nie udało się przywrócić pracownika")}
    end
  end

  def handle_event("copy-bank-account-number", %{"number" => number}, socket) do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: number})
     |> LiveToast.put_toast(:success, "Skopiowano numer konta")}
  end

  def handle_event("copy-email", %{"email" => email}, socket) do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: email})
     |> LiveToast.put_toast(:success, "Skopiowano adres e-mail")}
  end

  defp humanize_ash_error(%Ash.Error.Invalid{errors: [first_error | _]}) do
    Exception.message(first_error)
  end

  defp humanize_ash_error(error), do: Exception.message(error)

  # Distinct months (as naive_datetime) that have sessions, newest first.
  defp months_with_sessions(filters, scope), do: Timetracker.months_with_sessions(filters, scope)

  # Blob created — file is being processed, refresh list
  @impl true
  def handle_info(
        %Broadcast{
          payload: %Notification{
            resource: Blob,
            action: %{type: :create},
            data: %{processing_target: :employment_contract}
          }
        },
        socket
      ) do
    send_update(DocumentsTab,
      id: "documents-tab",
      refetch: true
    )

    {:noreply, socket}
  end

  # Blob updated — processing state transitions
  @impl true
  def handle_info(
        %Broadcast{
          payload: %Notification{
            resource: Blob,
            action: %{type: :update},
            data: %{processing_target: :employment_contract} = blob
          }
        },
        socket
      ) do
    cond do
      blob.processing_state == :failed ->
        BlobProcessingToasts.show_failure_toast(blob)

      blob.processing_state == :succeeded ->
        BlobProcessingToasts.show_success_toast(blob, :employment_contract)

      true ->
        :ok
    end

    send_update(DocumentsTab,
      id: "documents-tab",
      refetch: true
    )

    send_update(ProfileTab,
      id: "profile-tab",
      refetch: true
    )

    {:noreply, socket}
  end

  # Blob destroyed — processing failed
  @impl true
  def handle_info(
        %Broadcast{
          payload:
            %Notification{
              resource: Blob,
              action: %{type: :destroy},
              data: %{processing_target: :employment_contract},
              metadata: %{reason: :processing_failed}
            } = notification
        },
        socket
      ) do
    LiveToast.send_toast(:error, notification.data.original_filename, title: "Nie udało się wgrać pliku")

    send_update(DocumentsTab,
      id: "documents-tab",
      refetch: true
    )

    {:noreply, socket}
  end

  # Blob destroyed — invalid document uploaded
  @impl true
  def handle_info(
        %Broadcast{
          payload:
            %Notification{
              resource: Blob,
              action: %{type: :destroy},
              data: %{processing_target: :employment_contract},
              metadata: %{reason: :invalid_document}
            } = notification
        },
        socket
      ) do
    LiveToast.send_toast(
      :error,
      "Plik #{notification.data.original_filename} nie zawiera wymaganych danych. Upewnij się, że wgrywasz umowę.",
      title: "Nieprawidłowy dokument"
    )

    send_update(DocumentsTab,
      id: "documents-tab",
      refetch: true
    )

    {:noreply, socket}
  end

  # Blob destroyed — normal cleanup (delete invoice, etc.)
  @impl true
  def handle_info(
        %Broadcast{
          payload: %Notification{
            resource: Blob,
            data: %{processing_target: :employment_contract},
            action: %{type: :destroy}
          }
        },
        socket
      ) do
    send_update(DocumentsTab,
      id: "documents-tab",
      refetch: true
    )

    {:noreply, socket}
  end

  # Ignore other blob broadcasts (e.g., signed contract uploads with processing_target :none)
  def handle_info(%Broadcast{payload: %Notification{resource: Blob}}, socket) do
    {:noreply, socket}
  end

  # The Swoosh test adapter delivers emails directly to the LiveView process.
  def handle_info({:email, %Swoosh.Email{}}, socket) do
    {:noreply, socket}
  end

  def handle_info({:employee_updated, user}, socket) do
    {:noreply,
     assign(
       socket,
       :employee,
       Ash.load!(
         user,
         [:display_name, :projects, :delegations, :shared_birthday, avatar_blob: [:url]],
         scope: socket.assigns.ash_scope
       )
     )}
  end
end
