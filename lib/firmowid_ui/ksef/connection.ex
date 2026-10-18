defmodule FirmowidUI.Ksef.Connection do
  @moduledoc "Shared LiveView state and interactions for the three KSeF connection methods."

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias Ash.Error.Forbidden
  alias Ash.Error.Invalid
  alias Ash.Notifier.Notification
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.Credential
  alias Firmowid.Ash.Scope
  alias Phoenix.LiveView.Socket
  alias Phoenix.Socket.Broadcast

  @statuses ~w(authenticating authenticating_epuap preparing_enrollment wait_for_certificate refreshing working failed)

  @doc "Initializes connection assigns, uploads and credential subscriptions for an administrator."
  @spec init(Socket.t(), Scope.t()) :: Socket.t()
  def init(socket, scope) do
    authorize_admin!(scope)

    if connected?(socket) do
      for status <- @statuses do
        Phoenix.PubSub.subscribe(Firmowid.PubSub, "credential:#{status}:#{scope.tenant}")
      end
    end

    internal_credential =
      Credential.get_internal!(scope: scope, authorize?: true, query: [select: [:status]])

    socket
    |> assign(:ksef_connection_tenant, scope.tenant)
    |> assign(:ksef_credential, active_credential(scope))
    |> assign(:ksef_auth_challenge, nil)
    |> assign(:ksef_auth_method, :trusted_profile)
    |> assign(:ksef_auth_status, connection_status(internal_credential))
    |> assign(:ksef_failure, nil)
    |> assign(:ksef_fetching?, Ksef.fetching_invoices?(scope))
    |> allow_upload(:ksef_credentials, accept: ~w(.crt .key), max_entries: 2)
    |> allow_upload(:signed_auth_token_request, accept: ~w(.xml), max_entries: 1)
  end

  @doc "Clears connection state, pending uploads and subscriptions when interface authorization expires."
  @spec clear(Socket.t()) :: Socket.t()
  def clear(socket) do
    if tenant = socket.assigns[:ksef_connection_tenant] do
      for status <- @statuses do
        Phoenix.PubSub.unsubscribe(Firmowid.PubSub, "credential:#{status}:#{tenant}")
      end
    end

    socket =
      Enum.reduce([:ksef_credentials, :signed_auth_token_request], socket, fn name, socket ->
        case socket.assigns[:uploads][name] do
          nil -> socket
          upload -> Enum.reduce(upload.entries, socket, &cancel_upload(&2, name, &1.ref))
        end
      end)

    socket
    |> assign(:ksef_connection_tenant, nil)
    |> assign(:ksef_credential, nil)
    |> assign(:ksef_auth_challenge, nil)
    |> assign(:ksef_auth_method, :trusted_profile)
    |> assign(:ksef_auth_status, :idle)
    |> assign(:ksef_failure, nil)
    |> assign(:ksef_fetching?, false)
  end

  @doc "Handles an existing KSeF setup event with an explicit, authorized scope."
  @spec handle_event(String.t(), map(), Socket.t(), Scope.t()) :: {:noreply, Socket.t()}
  def handle_event(event, params, socket, scope) do
    authorize_admin!(scope)
    do_handle_event(event, params, socket, scope)
  end

  defp do_handle_event("save_ksef_token", %{"ksef_token" => token}, socket, scope) do
    case Credential.authenticate_with_token(token, scope: scope, authorize?: true) do
      {:ok, credential} ->
        authentication_started(socket, credential, scope)

      {:error, %Invalid{errors: [%{message: message} | _]}} ->
        LiveToast.send_toast(:error, message)
        {:noreply, socket}

      {:error, _reason} ->
        LiveToast.send_toast(:error, "Nie udało się połączyć z KSeF. Spróbuj ponownie.")
        {:noreply, socket}
    end
  end

  defp do_handle_event("select_ksef_auth_method", %{"method" => method}, socket, _scope)
       when method in ~w(token trusted_profile certificate) do
    {:noreply,
     socket
     |> assign(:ksef_auth_method, String.to_existing_atom(method))
     |> assign(:ksef_failure, nil)}
  end

  defp do_handle_event(event, _params, socket, _scope)
       when event in ["validate_ksef_certificate", "validate_signed_auth_token_request"] do
    {:noreply, socket}
  end

  defp do_handle_event("download_ksef_auth_token_request", _params, socket, scope) do
    case Ksef.prepare_external_auth_token_request(scope) do
      {:ok, request} ->
        {:noreply,
         socket
         |> assign(:ksef_auth_challenge, request.challenge)
         |> push_event("download-ksef-auth-token-request", %{
           content: request.xml,
           filename: "wniosek.xml"
         })}

      {:error, _reason} ->
        LiveToast.send_toast(:error, "Nie udało się pobrać dokumentu z KSeF.")
        {:noreply, socket}
    end
  end

  # LiveView supplies managed temporary paths, never paths derived from client filenames.
  # sobelow_skip ["Traversal.FileModule"]
  defp do_handle_event("upload_signed_auth_token_request", _params, socket, scope) do
    uploaded_xml =
      consume_uploaded_entries(socket, :signed_auth_token_request, fn %{path: path}, _entry ->
        File.read(path)
      end)

    with [signed_xml] <- uploaded_xml,
         {:ok, _credential} <-
           Credential.enroll_ksef_certificate(signed_xml, socket.assigns.ksef_auth_challenge,
             scope: scope,
             authorize?: true
           ) do
      LiveToast.send_toast(:info, "Rozpoczęto generowanie certyfikatu KSeF.")

      {:noreply,
       socket
       |> assign(:ksef_auth_challenge, nil)
       |> assign(:ksef_auth_status, :authenticating_epuap)
       |> assign(:ksef_failure, nil)}
    else
      _error ->
        LiveToast.send_toast(:error, "Podpisany dokument nie zgadza się z pobranym wnioskiem.")
        {:noreply, socket}
    end
  end

  # LiveView supplies managed temporary paths, never paths derived from client filenames.
  # sobelow_skip ["Traversal.FileModule"]
  defp do_handle_event("save_ksef_certificate", %{"private_key_password" => password}, socket, scope) do
    files =
      consume_uploaded_entries(socket, :ksef_credentials, fn %{path: path}, entry ->
        with {:ok, contents} <- File.read(path) do
          {:ok, {Path.extname(entry.client_name), contents}}
        end
      end)

    with {".crt", certificate} <- List.keyfind(files, ".crt", 0),
         {".key", private_key} <- List.keyfind(files, ".key", 0) do
      case Credential.authenticate_with_uploaded_certificate(certificate, private_key, password,
             scope: scope,
             authorize?: true
           ) do
        {:ok, credential} ->
          authentication_started(socket, credential, scope)

        {:error, _reason} ->
          LiveToast.send_toast(
            :error,
            "Nie udało się zalogować do KSeF. Sprawdź pliki i hasło do klucza."
          )

          {:noreply, socket}
      end
    else
      _ ->
        LiveToast.send_toast(:error, "Wybierz certyfikat i klucz prywatny.")
        {:noreply, socket}
    end
  end

  defp do_handle_event("fetch_ksef_invoices", _params, socket, scope) do
    if Ksef.fetching_invoices?(scope) do
      {:noreply, assign(socket, :ksef_fetching?, true)}
    else
      :ok = Ksef.fetch_new_invoices(scope)
      LiveToast.send_toast(:info, "Rozpoczęto pobieranie faktur z KSeF.")
      {:noreply, assign(socket, :ksef_fetching?, true)}
    end
  end

  defp do_handle_event("disconnect_ksef", _params, socket, scope) do
    case Ksef.unauthenticate(scope) do
      {:ok, _} ->
        LiveToast.send_toast(:info, "Rozłączono z KSeF.")

        {:noreply,
         socket
         |> assign(:ksef_credential, nil)
         |> assign(:ksef_auth_challenge, nil)
         |> assign(:ksef_auth_status, :idle)
         |> assign(:ksef_failure, nil)}

      {:error, _} ->
        LiveToast.send_toast(:error, "Wystąpił błąd podczas rozłączania z KSeF.")
        {:noreply, socket}
    end
  end

  @doc "Refreshes connection state from a tenant-matched credential PubSub notification."
  @spec handle_info(Broadcast.t(), Socket.t(), Scope.t()) :: {:noreply, Socket.t()}
  def handle_info(
        %Broadcast{
          topic: "credential:" <> topic,
          payload: %Notification{resource: Credential, data: credential} = notification
        },
        socket,
        scope
      ) do
    authorize_admin!(scope)

    case String.split(topic, ":", parts: 2) do
      [status, tenant]
      when tenant == scope.tenant and tenant == socket.assigns.ksef_connection_tenant and
             status in @statuses ->
        update_status(socket, String.to_existing_atom(status), credential, notification, scope)

      _ ->
        {:noreply, socket}
    end
  end

  defp update_status(socket, status, credential, notification, scope) do
    socket = assign(socket, :ksef_auth_status, status)

    case status do
      :working ->
        if notification.action != :recover_certificate_refresh do
          LiveToast.send_toast(:success, "Połączono z KSeF.")
        end

        {:noreply,
         socket
         |> assign(:ksef_failure, nil)
         |> assign(:ksef_credential, active_credential(scope))}

      :failed ->
        reason = Ash.Changeset.get_argument(notification.changeset, :reason)

        {:noreply,
         socket
         |> assign(:ksef_failure, %{reason: reason, auth_type: credential.auth_type})
         |> assign(:ksef_credential, active_credential(scope))}

      :refreshing ->
        {:noreply, assign(socket, :ksef_credential, active_credential(scope))}

      _ ->
        {:noreply, socket}
    end
  end

  defp authentication_started(socket, credential, scope) do
    LiveToast.send_toast(:info, "Rozpoczęto uwierzytelnianie w KSeF.")

    {:noreply,
     socket
     |> assign(:ksef_credential, active_credential(scope))
     |> assign(:ksef_auth_status, credential.status)
     |> assign(:ksef_failure, nil)}
  end

  defp connection_status(nil), do: :idle
  defp connection_status(%Credential{status: status}), do: status

  defp active_credential(scope) do
    case Ksef.get_credential!(
           scope: scope,
           authorize?: true,
           query: [select: [:auth_type, :expires_on]]
         ) do
      nil ->
        nil

      credential ->
        if credential.expires_on && Date.before?(credential.expires_on, Date.utc_today()),
          do: nil,
          else: Map.take(credential, [:auth_type, :expires_on])
    end
  end

  defp authorize_admin!(%Scope{actor: %{role: :admin, organization_id: tenant}, tenant: tenant}) when is_binary(tenant),
    do: :ok

  defp authorize_admin!(_scope) do
    raise Forbidden, message: "Tylko administrator może zarządzać KSeF."
  end
end
