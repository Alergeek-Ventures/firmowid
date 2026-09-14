defmodule FirmowidWeb.Infrastructure.Utilities.PosthogBusinessEvents do
  @moduledoc """
  Sends the small, allowlisted set of business events exposed to PostHog.

  Event names and properties are owned here so feature LiveViews cannot
  accidentally send identifiers, personal data, or arbitrary telemetry.
  """

  alias Phoenix.LiveView.Socket

  @event_names %{
    invoice_created: "invoice_created",
    bank_connection_completed: "bank_connection_completed",
    time_entry_created: "time_entry_created",
    payroll_rates_updated: "payroll_rates_updated",
    counterparty_created: "counterparty_created",
    counterparty_updated: "counterparty_updated",
    account_created: "account_created"
  }

  @doc """
  Captures an allowlisted business event on the server.

  Invalid event names or properties are ignored and leave the socket unchanged.
  Analytics failures are also ignored so they cannot affect product actions.
  """
  @spec capture(Socket.t(), atom()) :: Socket.t()
  @spec capture(Socket.t(), atom(), map()) :: Socket.t()
  def capture(socket, event, properties \\ %{})

  def capture(socket, event, properties) when is_struct(socket, Socket) and is_atom(event) and is_map(properties) do
    with {:ok, event_name} <- Map.fetch(@event_names, event),
         {:ok, safe_properties} <- validate_properties(event, properties),
         {:ok, user_id} <- context_ids(socket),
         true <- analytics_enabled?() do
      capture_with_sdk(event_name, user_id, safe_properties, socket)
    else
      _ -> socket
    end
  rescue
    _ -> socket
  end

  def capture(socket, _event, _properties), do: socket

  @doc """
  Captures a successfully created password account when cookie consent allows it.

  Registration is intentionally handled separately from the organization-scoped
  LiveView events: onboarding has not created an organization yet.
  """
  @spec capture_account_created(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def capture_account_created(conn, %{id: user_id}) when not is_nil(user_id) do
    conn = Plug.Conn.fetch_cookies(conn)

    if conn.cookies["cookie_consent"] == "accepted" and analytics_enabled?() do
      PostHog.capture("account_created", %{
        "method" => "password",
        distinct_id: to_string(user_id)
      })
    end

    conn
  rescue
    _ -> conn
  end

  def capture_account_created(conn, _user), do: conn

  defp context_ids(socket) do
    with true <- socket.assigns[:analytics_consent_accepted] == true,
         %{id: user_id} when not is_nil(user_id) <- socket.assigns[:current_user],
         %{id: organization_id} when not is_nil(organization_id) <- socket.assigns[:current_org] do
      {:ok, {to_string(user_id), to_string(organization_id)}}
    else
      _ -> :error
    end
  end

  defp analytics_enabled? do
    case PostHog.config() do
      %{enabled: true} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp capture_with_sdk(event_name, {user_id, organization_id}, properties, socket) do
    properties = Map.put(properties, "$groups", %{"organization" => organization_id})
    PostHog.capture(event_name, Map.put(properties, :distinct_id, user_id))
    socket
  rescue
    _ -> socket
  end

  defp validate_properties(event, properties)
       when event in [
              :invoice_created,
              :bank_connection_completed,
              :time_entry_created,
              :counterparty_created,
              :counterparty_updated
            ] do
    if properties == %{}, do: {:ok, %{}}, else: :error
  end

  defp validate_properties(:payroll_rates_updated, %{changed_employee_count: count})
       when is_integer(count) and count >= 0, do: {:ok, %{"changed_employee_count" => count}}

  defp validate_properties(_event, _properties), do: :error
end
